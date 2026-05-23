# moonlight-embedded `rk` platform — structural brief

Source root: `/tmp/me-research/moonlight-embedded`. Line numbers below are relative to that root.

> **Critical finding up front.** `src/video/rk.c` is **not** an EGL/GLES pipeline. It is a pure DRM/KMS overlay-plane composer: it allocates DRM dumb buffers, hands their PRIME fds to rkmpp as an external buffer group, then commits the resulting `fb_id` onto a hardware overlay plane via `drmModeAtomicCommit` / `drmModeSetPlane`. No `eglCreateImageKHR`, no `samplerExternalOES`, no fragment shader anywhere in `rk.c`.
>
> Likewise `src/video/egl.c` is a **software** YUV path — it `glTexSubImage2D`'s three `GL_LUMINANCE` planes per frame from CPU pointers. There is no `EGL_LINUX_DMA_BUF_EXT` or `GL_TEXTURE_EXTERNAL_OES` anywhere in the tree (`grep` for `EGL_LINUX_DMA_BUF|eglCreateImage|samplerExternalOES|TEXTURE_EXTERNAL_OES|AVDRMFrameDescriptor` over `src/` returns zero matches).
>
> So **rk.c gives us the platform-registration scaffolding and the rkmpp→DMA-BUF→display zero-copy *idea*, but the EGLImage/GLES sampling code has to be written from scratch.** Reusing `egl.c` directly is not viable; either extend it or add a sibling `egl_dmabuf.c`.

---

## 1. Platform contract (what every video plugin must implement)

A platform exports a single `DECODER_RENDERER_CALLBACKS` struct. The struct definition lives in upstream `Limelight.h` (moonlight-common-c submodule, not vendored in this checkout), but the usage at `src/video/rk.c:760-763` pins the shape:

```c
DECODER_RENDERER_CALLBACKS decoder_callbacks_rk = {
  .setup            = rk_setup,
  .cleanup          = rk_cleanup,
  .submitDecodeUnit = rk_submit_decode_unit,
  .capabilities     = CAPABILITY_DIRECT_SUBMIT,
};
```

Callback signatures (consistent across `rk.c`, `sdl.c`, `x11.c`, `imx.c`, `aml.c`):

| Field | Signature | Semantics |
|---|---|---|
| `setup` | `int (*)(int videoFormat, int width, int height, int redrawRate, void* context, int drFlags)` | Init decoder + display. Return 0 on success, negative on error. `videoFormat` is a bitmask: `VIDEO_FORMAT_MASK_H264 / _H265 / _AV1 / _10BIT`. `drFlags` carries `DISPLAY_FULLSCREEN`, `DISPLAY_ROTATE_*`, `ENABLE_HARDWARE_ACCELERATION_*` (see `src/video/video.h:23-37`). |
| `start` (optional) | `void (*)(void)` | Not used by rk/sdl; aml/imx leave it NULL. |
| `stop`  (optional) | `void (*)(void)` | Likewise. |
| `cleanup` | `void (*)(void)` | Tear down decoder + display. |
| `submitDecodeUnit` | `int (*)(PDECODE_UNIT)` | Called per encoded NALU/access-unit from moonlight-common-c. Must return `DR_OK` (0). When `CAPABILITY_DIRECT_SUBMIT` is set, this runs on the network thread; otherwise it runs on common-c's decode thread. |
| `capabilities` | `int` | OR of `CAPABILITY_DIRECT_SUBMIT`, `CAPABILITY_SLICES_PER_FRAME(n)`, `CAPABILITY_REFERENCE_FRAME_INVALIDATION_HEVC`, etc. |

`PDECODE_UNIT` (inferred from `rk_submit_decode_unit` at `src/video/rk.c:619-757`):
- `bufferList` — `PLENTRY` linked list of `{ char* data; int length; PLENTRY next; }`.
- `fullLength` — sum of all entry lengths.
- `hdrActive` — bool; HDR enable flag for this AU.
- `colorspace` — `COLORSPACE_REC_601 / _REC_709 / _REC_2020`.

`platform_get_video()` in `src/platform.c:160-194` is the dispatch table that maps `enum platform` → `DECODER_RENDERER_CALLBACKS*`. For dlopen'd plugins (imx/pi/mmal/aml/rk) it does `dlsym(RTLD_DEFAULT, "decoder_callbacks_rk")`. For statically linked ones (sdl/x11) it returns `&decoder_callbacks_sdl` etc.

---

## 2. `rk.c` end-to-end flow

### 2a. Init — `rk_setup` (`src/video/rk.c:341-526`)

1. **Codec mapping** (`:349-358`): translate `VIDEO_FORMAT_MASK_*` to rkmpp constants `RK_H264 / RK_H265 / RK_AV1`.
2. **HDR/atomic toggle** (`:363`): use atomic KMS only when 10-bit, because RK3588 atomic perf degrades.
3. **DRM display setup** (`:373-525`):
   - `open("/dev/dri/card0", O_RDWR | O_CLOEXEC)` → `fd`.
   - `drmModeGetResources` → walk connectors, find connected one with modes (`:391-402`).
   - Collect all connector properties into `conn_props[]` and remember `HDR_OUTPUT_METADATA` (`:406-421`).
   - Find matching encoder + crtc → cache `crtc_id, crtc_width, crtc_height` (`:423-449`).
   - `drmSetClientCap(DRM_CLIENT_CAP_UNIVERSAL_PLANES)` + optionally `DRM_CLIENT_CAP_ATOMIC` (`:451-466`).
   - `drmModeGetPlaneResources` → iterate planes, pick the first OVERLAY/CURSOR/PRIMARY plane whose CRTC bit matches and which advertises `DRM_FORMAT_NV12` (8-bit) or `DRM_FORMAT_NA12/NV15` (10-bit) (`:468-525`).
   - Cache all plane properties into `plane_props[]` for later atomic commits.
   - Apply DRM `rotation` property (`:529-547`) and hide hardware cursor (`:550`).
4. **MPP setup** (`:554-579`):
   - `mpp_packet_init` against a `pkt_buf` grown on demand.
   - `mpp_create(&mpi_ctx, &mpi_api)`.
   - `mpi_api->control(MPP_DEC_SET_PARSER_SPLIT_MODE, ...)` so the decoder can accept partial AUs.
   - `mpp_init(MPP_CTX_DEC, mpp_type)`.
   - `mpi_api->control(MPP_SET_OUTPUT_BLOCK, &MPP_POLL_BLOCK)` so `decode_get_frame` blocks.
5. **Threads** (`:581-587`):
   - `frame_thread` — pulls decoded `MppFrame`s out of MPP.
   - `display_thread` — waits on a condvar for an `fb_id` and commits it to the overlay plane.

### 2b. Per-packet — `rk_submit_decode_unit` (`src/video/rk.c:619-757`)

1. Grow `pkt_buf` to `decodeUnit->fullLength` and re-bind it into `mpi_packet` if reallocated (`:625-629`).
2. `memcpy` every `PLENTRY` into `pkt_buf`, compute `length` (`:631-635`).
3. `mpp_packet_set_pos / _set_length` on the cached `mpi_packet` (`:637-638`).
4. **HDR state change** (`:640-693`): build a `rk_hdr_output_metadata` blob from `LiGetHdrMetadata()`, set it on the connector's `HDR_OUTPUT_METADATA` property, also flip the plane's `EOTF` property between SDR(0) and PQ(2).
5. **Colorspace change** (`:695-717`): map `COLORSPACE_REC_*` to `V4L2_COLORSPACE_*` and set the plane's `COLOR_SPACE` property.
6. `while (MPP_OK != mpi_api->decode_put_packet(mpi_ctx, mpi_packet));` — busy-retry submit (`:723`).

### 2c. Frame thread — `frame_thread` (`src/video/rk.c:178-285`)

This is the **zero-copy hand-off** loop and the part most analogous to what we need for v4l2m2m:

1. `mpi_api->decode_get_frame(mpi_ctx, &frame)` blocks for a `MppFrame`.
2. **First frame: info-change branch** (`:194-265`):
   - Read `mpp_frame_get_{width,height,hor_stride,ver_stride,fmt}`.
   - Compute aspect-fit rectangle (`fb_x, fb_y, fb_width, fb_height`).
   - Build an *external* MPP buffer group: `mpp_buffer_group_get_external(&mpi_frm_grp, MPP_BUFFER_TYPE_DRM)` (`:215-216`).
   - For each of `MAX_FRAMES=3` slots:
     - `drmIoctl(DRM_IOCTL_MODE_CREATE_DUMB)` with `bpp=8, width=hor_stride, height=ver_stride*2` (NV12 Y+UV packed vertically). → `dmcd.handle`. (`:219-230`)
     - `drmIoctl(DRM_IOCTL_PRIME_HANDLE_TO_FD)` to export a dmabuf fd. (`:233-241`)
     - `mpp_buffer_commit(mpi_frm_grp, &info)` registers that fd as MPP's output buffer (MPP *dups* the fd). (`:242-247`)
     - `drmModeAddFB2(fd, frm_width, frm_height, pixel_format, handles[2], pitches[2], offsets[2], &fb_id, 0)` — Y plane at offset 0, UV plane at `pitch * ver_stride`. (`:250-258`)
   - `mpi_api->control(MPP_DEC_SET_EXT_BUF_GROUP, mpi_frm_grp)` + `MPP_DEC_SET_INFO_CHANGE_READY`. (`:260-262`)
   - Seed atomic plane SRC/CRTC rects + ZPOS + ALLM + Colorspace (`:265-280`).
3. **Normal frame branch** (`:282-302`):
   - `mpp_frame_get_buffer(frame)` → `MppBuffer`.
   - `mpp_buffer_info_get(buffer, &info)` → recover the dmabuf fd.
   - Linear search `frame_to_drm[]` for the matching `prime_fd` → recover the cached `fb_id`.
   - Lock + signal the `display_thread` condvar with that `fb_id`.
4. `mpp_frame_deinit(&frame)`.

### 2d. Display thread — `display_thread` (`src/video/rk.c:142-176`)

- Block on `cond`/`mutex` until `fb_id != 0`.
- Atomic path: `set_property(plane_id, ..., "FB_ID", _fb_id)` + `drmModeAtomicCommit(... ALLOW_MODESET, NULL)`.
- Legacy path: `drmModeSetPlane(fd, plane_id, crtc_id, _fb_id, 0, fb_x, fb_y, fb_width, fb_height, 0, 0, frm_width<<16, frm_height<<16)`.

### 2e. Cleanup — `rk_cleanup` (`src/video/rk.c:583-617`)

Order matters:
1. `frm_eos = 1`, signal cond, `pthread_join(tid_display)`.
2. `mpi_api->reset(mpi_ctx)`, then `pthread_join(tid_frame)`.
3. `mpp_buffer_group_put(mpi_frm_grp)` (this releases MPP's dups of the fds).
4. For each cached slot: `drmModeRmFB(fb_id)` then `DRM_IOCTL_MODE_DESTROY_DUMB(handle)`.
5. `mpp_packet_deinit` + `mpp_destroy` + `free(pkt_buf)`.
6. Restore connector HDR/ALLM/Colorspace to defaults, atomic-commit, free the request.
7. Free all drm objects + `close(fd)`.

> **Note on dmabuf fd ownership in rk.c**: rk **does not** explicitly `close()` the per-slot `prime_fd` — it relies on `drmModeRmFB` + `DRM_IOCTL_MODE_DESTROY_DUMB` to release the underlying GEM object, and assumes MPP releases its dup'd copy in `mpp_buffer_group_put`. The original exported fd in `frame_to_drm[i].prime_fd` is **leaked** at the FD-table level. For our EGLImage path we'll want to be more careful and close fds after `eglDestroyImageKHR`.

---

## 3. Registration

### Name → enum
- Declared in `src/platform.h:30`: `enum platform { NONE, SDL, X11, X11_VDPAU, X11_VAAPI, PI, MMAL, IMX, AML, RK, FAKE };`
- `platform_check(name)` (`src/platform.c:36-103`) is a string-match chain wrapped in `#ifdef HAVE_*`. The rk branch is `src/platform.c:71-77`:
  ```c
  #ifdef HAVE_ROCKCHIP
  if (std || strcmp(name, "rk") == 0) {
    void *handle = dlopen("libmoonlight-rk.so", RTLD_NOW | RTLD_GLOBAL);
    if (handle != NULL && dlsym(RTLD_DEFAULT, "mpp_init") != NULL)
      return RK;
  }
  #endif
  ```
- `platform_get_video(RK)` does `dlsym(RTLD_DEFAULT, "decoder_callbacks_rk")` (`src/platform.c:189-191`).
- `platform_prefers_codec(RK, CODEC_HEVC) → true` (`src/platform.c:212-220`) — so HEVC is auto-selected when `-codec auto`.
- `platform_name(RK) → "Rockchip VPU"` (`src/platform.c:244`).

### CLI surface
- `src/main.c:213`: usage string lists `pi/imx/aml/rk/x11/x11_vdpau/sdl/fake`.
- `src/config.c:62`: `{"platform", required_argument, NULL, 'p'}` → `config->platform` (default `"auto"` at `:367`).

### CMake gate
- `src/video/rk.c` is built into a **separate shared library** `libmoonlight-rk.so`, gated by `if(ROCKCHIP_FOUND)` at `CMakeLists.txt:155-163`:
  ```cmake
  if(ROCKCHIP_FOUND)
    list(APPEND MOONLIGHT_DEFINITIONS HAVE_ROCKCHIP)
    list(APPEND MOONLIGHT_OPTIONS ROCKCHIP)
    add_library(moonlight-rk SHARED ./src/video/rk.c ./src/util.c)
    target_include_directories(moonlight-rk PRIVATE ${ROCKCHIP_INCLUDE_DIRS} ...)
    target_link_libraries(moonlight-rk gamestream ${ROCKCHIP_LIBRARIES})
    install(TARGETS moonlight-rk DESTINATION ${CMAKE_INSTALL_LIBDIR})
  endif()
  ```
- `ROCKCHIP_FOUND` comes from `cmake/FindRockchip.cmake` (looks for `rockchip/rk_mpi.h` + `librockchip_mpp`).
- `HAVE_EMBEDDED` is also set whenever any embedded platform is found (`CMakeLists.txt:214-217`).
- The dlopen-as-plugin pattern (vs. statically linking like SDL/X11) exists so that you don't need rkmpp installed on machines that won't run on RK silicon.

---

## 4. What changes for a v4l2m2m + AVDRMFrameDescriptor pipeline

### Conceptual diff

| Concern | rk.c (rkmpp + DRM overlay) | v4l2m2m + EGLImage (us) |
|---|---|---|
| Decoder API | librockchip_mpp `MppCtx` / `decode_put_packet` / `decode_get_frame` | FFmpeg `hevc_v4l2m2m` via existing `src/video/ffmpeg.c` (`avcodec_send_packet` / `avcodec_receive_frame`) |
| Output buffer allocator | **App** allocates DRM dumb buffers, exports PRIME fds, gives them to MPP via `mpp_buffer_group_get_external` + `mpp_buffer_commit` | **Decoder** allocates V4L2 CAPTURE buffers. We extract dmabuf fds from `AVFrame->data[0]` cast to `AVDRMFrameDescriptor*` (requires `hw_device_ctx` of type `AV_HWDEVICE_TYPE_DRM` and `AV_PIX_FMT_DRM_PRIME`) |
| Buffer pool lifecycle | App owns, MPP dups fds, app frees in `cleanup` | FFmpeg owns; we hold an `AVFrame*` reference until the EGLImage is no longer in flight |
| Display path | DRM/KMS overlay plane composited by display controller; no GPU | Adreno 740 / freedreno: import dmabuf → `EGLImage` → bind to `GL_TEXTURE_EXTERNAL_OES` → sample with `samplerExternalOES` in a fragment shader → swap buffers |
| HDR handling | Connector `HDR_OUTPUT_METADATA` property blob + plane `EOTF` property | Out of scope for first cut. SM8550/Mesa HDR path is separate. |
| Colorspace conversion | Display controller does YUV→RGB via `COLOR_SPACE` plane prop | `samplerExternalOES` returns RGB directly when the EGLImage was created with `EGL_YUV_COLOR_SPACE_HINT_EXT` + `EGL_SAMPLE_RANGE_HINT_EXT`; the EGL driver inserts the conversion. (No manual shader math.) |
| Window system | Direct DRM (no compositor). KMS plane is the surface. | Need an EGL context on a real surface: either GBM+KMS (kiosk) or a Wayland surface. SM8550 + Mesa supports both. Match what `sdl.c` / `x11.c` already use; on Wayland that means `eglGetDisplay(wl_display)` + `eglCreateWindowSurface(wl_egl_window)`. |
| HW cursor | Hidden via `drmModeMoveCursor` | N/A |
| Threading | Custom `frame_thread` + `display_thread` with condvar | Could keep the same shape (decode on submit thread, render on dedicated thread fed via pipe/eventfd like `x11.c:54-66`). Or fold render into `submitDecodeUnit` when `CAPABILITY_DIRECT_SUBMIT` is set. |

### What stays the same as rk.c
- Platform-callback struct shape and dispatch.
- The pattern of packet buffer reallocation in `submitDecodeUnit`.
- The platform-as-dlopen-plugin layout (so the module only loads when v4l2m2m + freedreno are available).
- Codec capability flags.

### What is genuinely new
- All the EGL/GLES code for dmabuf import + external-OES sampling. This **does not exist** in upstream moonlight-embedded today.
- `AVDRMFrameDescriptor` extraction from `AVFrame`. Requires:
  - `decoder_ctx->hw_device_ctx = av_hwdevice_ctx_create(AV_HWDEVICE_TYPE_DRM, ...)` — analogous to `vaapi_init` at `src/video/ffmpeg_vaapi.c:64-68`.
  - `decoder_ctx->get_format` returns `AV_PIX_FMT_DRM_PRIME` when offered.
  - Frame layout: `frame->format == AV_PIX_FMT_DRM_PRIME`, `frame->data[0] = (uint8_t*) AVDRMFrameDescriptor*`, which has `nb_objects` (dmabuf fds + size + format_modifier), `nb_layers` (planes with `format`, `nb_planes`, per-plane `object_index/offset/pitch`).

### Can we reuse `src/video/egl.c`?
**No, not as-is.** `egl.c` is a software uploader: three `GL_LUMINANCE` 2D textures, `glTexSubImage2D` per frame from `uint8_t* image[3]`, hand-rolled BT.601 matrix in the fragment shader (`src/video/egl.c:37-52`). It has neither `eglCreateImageKHR` nor `GL_TEXTURE_EXTERNAL_OES` plumbing.

Two viable approaches:

1. **Extend `egl.c`** with new entry points (e.g. `egl_init_dmabuf`, `egl_draw_dmabuf(AVDRMFrameDescriptor*)`, `egl_destroy_dmabuf`) and a sibling shader using `#extension GL_OES_EGL_image_external : require` and `samplerExternalOES`. Keep the existing software path intact so `x11.c` (software fallback) keeps working.
2. **Add a new `egl_dmabuf.{c,h}`** sibling that shares nothing with `egl.c` but the EGL context bootstrap. Cleaner separation, but duplicates the context-creation boilerplate.

Recommendation: **(1) extend `egl.c`**. The existing public API (`egl_init`, `egl_draw`, `egl_destroy`) is only called from `x11.c` (one place), so adding parallel `_dmabuf` entry points is low-risk and keeps EGL bootstrap centralized. The shader text and texture-setup code is the only real divergence.

---

## 5. Suggested new platform: name & file layout

**Name: `v4l2m2m`** (matches the FFmpeg decoder name and is the smallest surprise for users).

If you want a one-line CLI hint, advertise it alongside `sdl` (i.e. `-platform v4l2m2m`). Aliasing it as `sdl-drm` is also reasonable, but `v4l2m2m` is the more discoverable label for someone debugging — it names the actual hardware path. Pick `v4l2m2m` for the platform enum and the dlopen name; document `sdl-drm` only if marketing requires.

### File layout
```
src/video/v4l2m2m.c          # new — DECODER_RENDERER_CALLBACKS + ffmpeg DRM wiring
src/video/egl.c              # extend — add egl_init_dmabuf / egl_draw_dmabuf / egl_destroy_dmabuf
src/video/egl.h              # extend — declare the new entry points and #include <EGL/eglext.h>
src/platform.h               # add V4L2M2M to enum platform
src/platform.c               # add platform_check / platform_get_video / platform_name / platform_prefers_codec branches
src/main.c                   # update usage string
CMakeLists.txt               # add cmake/FindV4L2M2M.cmake gate + add_library(moonlight-v4l2m2m ...)
cmake/FindV4L2M2M.cmake      # new — probe for /dev/video* + libdrm + EGL + GLESv2
```

### CMake variable
`V4L2M2M_FOUND` → `HAVE_V4L2M2M`. The library is built as `libmoonlight-v4l2m2m.so` so it can be dlopen'd just like rk.

If the v4l2m2m plugin needs a runtime probe (analog of rk's `dlsym(... "mpp_init")` check at `src/platform.c:74`), use the existence of `/dev/video0` (or a successful `V4L2_CAP_VIDEO_M2M_MPLANE` query) plus `eglGetDisplay() != EGL_NO_DISPLAY`.

### Linkage
- `pkg-config --libs libdrm egl glesv2 libavcodec libavutil`
- Reuse `gamestream` static dep like rk does (`CMakeLists.txt:160`).
- Because `ffmpeg.c` is currently only compiled into the **main** `moonlight` binary (gated on `SOFTWARE_FOUND`, see `CMakeLists.txt:170`), we either:
  - (a) also compile `./src/video/ffmpeg.c` into `libmoonlight-v4l2m2m.so` (acceptable — small file, no global state collision since the plugin runs in-process and `ffmpeg.c`'s symbols become local to the .so), **or**
  - (b) move `ffmpeg.c` to always-built and have the plugin link against the moonlight binary's symbols (more intrusive, requires `-rdynamic`).
  - Prefer (a) for first patch.

---

## 6. Concrete change checklist

### New files
1. **`src/video/v4l2m2m.c`** (~250 lines, modeled on `x11.c` + `sdl.c`, with rk-style cleanup ordering):
   - `static int v4l2m2m_setup(int videoFormat, int width, int height, int redrawRate, void* context, int drFlags)`:
     - Create DRM device context: `av_hwdevice_ctx_create(&drm_device_ref, AV_HWDEVICE_TYPE_DRM, "/dev/dri/renderD128", NULL, 0)`.
     - Call `ffmpeg_init(videoFormat, width, height, 0, 2, 1)` — rely on its existing try-table to pick `hevc_v4l2m2m`. (May need a small `ffmpeg.c` tweak; see below.)
     - Override `decoder_ctx->get_format` so it returns `AV_PIX_FMT_DRM_PRIME` when offered. Set `decoder_ctx->hw_device_ctx = av_buffer_ref(drm_device_ref)`.
     - Open a window/surface (GBM+KMS for kiosk, or Wayland — choose based on env). Call `egl_init_dmabuf(native_display, native_window, width, height)`.
     - Spawn a render thread fed by a pipefd, mirroring `x11.c:54-66` and `:147-152`.
   - `static int v4l2m2m_submit_decode_unit(PDECODE_UNIT decodeUnit)`:
     - Same packet-coalesce + `ffmpeg_decode(buf, len)` as `x11_submit_decode_unit` (`src/video/x11.c:181-202`).
     - `AVFrame* f = ffmpeg_get_frame(true);` (native frame).
     - `write(pipefd[1], &f, sizeof(void*))` (transfer ownership to render thread).
   - Render-thread frame handler:
     - Cast `f->data[0]` to `AVDRMFrameDescriptor*`.
     - Call `egl_draw_dmabuf(desc, f->width, f->height)`.
     - `av_frame_unref(f)` once GL is done with it (after `glFinish` or fence).
   - `static void v4l2m2m_cleanup()`: stop render thread, `egl_destroy_dmabuf()`, `ffmpeg_destroy()`, `av_buffer_unref(&drm_device_ref)`, close window/surface.
   - Export `DECODER_RENDERER_CALLBACKS decoder_callbacks_v4l2m2m` with `.capabilities = CAPABILITY_DIRECT_SUBMIT | CAPABILITY_REFERENCE_FRAME_INVALIDATION_HEVC`.

2. **`cmake/FindV4L2M2M.cmake`** — probe `libdrm`, `egl`, `glesv2`, `libavcodec ≥ 4.x` (for `AV_PIX_FMT_DRM_PRIME`). Set `V4L2M2M_FOUND`, `V4L2M2M_INCLUDE_DIRS`, `V4L2M2M_LIBRARIES`.

### Edits
3. **`src/video/egl.h`** (`+ ~5 lines`):
   - `#include <EGL/eglext.h>`, `#include <libavutil/hwcontext_drm.h>`.
   - Declare `void egl_init_dmabuf(EGLNativeDisplayType, NativeWindowType, int, int);`
   - Declare `void egl_draw_dmabuf(AVDRMFrameDescriptor* desc, int width, int height);`
   - Declare `void egl_destroy_dmabuf(void);`

4. **`src/video/egl.c`** (`+ ~180 lines`):
   - New fragment shader using `samplerExternalOES`:
     ```glsl
     #extension GL_OES_EGL_image_external : require
     uniform samplerExternalOES tex;
     varying mediump vec2 tex_position;
     void main() { gl_FragColor = texture2D(tex, tex_position); }
     ```
   - `egl_init_dmabuf`: same EGL context bootstrap as `egl_init` but choose ES2 config with `EGL_RENDERABLE_TYPE | EGL_OPENGL_ES2_BIT`, create one `GL_TEXTURE_EXTERNAL_OES` texture, link the new program, resolve `eglCreateImageKHR`/`eglDestroyImageKHR`/`glEGLImageTargetTexture2DOES` via `eglGetProcAddress`.
   - `egl_draw_dmabuf`:
     1. For each layer in the descriptor, build an attribute list:
        ```
        EGL_WIDTH, width,
        EGL_HEIGHT, height,
        EGL_LINUX_DRM_FOURCC_EXT, desc->layers[0].format,
        EGL_DMA_BUF_PLANE0_FD_EXT,      desc->objects[idx].fd,
        EGL_DMA_BUF_PLANE0_OFFSET_EXT,  desc->layers[0].planes[0].offset,
        EGL_DMA_BUF_PLANE0_PITCH_EXT,   desc->layers[0].planes[0].pitch,
        EGL_DMA_BUF_PLANE0_MODIFIER_LO_EXT, mod_lo,
        EGL_DMA_BUF_PLANE0_MODIFIER_HI_EXT, mod_hi,
        // PLANE1_* for NV12 UV
        EGL_YUV_COLOR_SPACE_HINT_EXT, EGL_ITU_REC709_EXT,
        EGL_SAMPLE_RANGE_HINT_EXT,    EGL_YUV_NARROW_RANGE_EXT,
        EGL_NONE
        ```
     2. `EGLImageKHR img = eglCreateImageKHR(display, EGL_NO_CONTEXT, EGL_LINUX_DMA_BUF_EXT, NULL, attrs);`
     3. `glEGLImageTargetTexture2DOES(GL_TEXTURE_EXTERNAL_OES, img);`
     4. `glDrawElements(...)`, `eglSwapBuffers`.
     5. `eglDestroyImageKHR(display, img);` — every frame; the underlying dmabuf fd is owned by the `AVFrame`.
   - `egl_destroy_dmabuf`: tear down the program/texture, destroy context+surface like the existing `egl_destroy`.

5. **`src/video/ffmpeg.c`** (`+ ~30 lines`):
   - Add an optional hook (similar to `vaapi_init` at `src/video/ffmpeg_vaapi.c:64-68`) so the v4l2m2m plugin can install a `get_format` that pins `AV_PIX_FMT_DRM_PRIME` and attach the DRM `hw_device_ctx`. Either expose `decoder_ctx` via a new accessor, or add a new init flag like `DRM_PRIME_ACCELERATION` that ffmpeg.c handles internally (preferred — keeps the seam narrow).
   - Make sure the decoder picker in `ffmpeg.c:73-83` still finds `hevc_v4l2m2m` before plain `hevc`. (Already true today: it's tried at `try == 3`.)

6. **`src/platform.h`** (`+1 line`):
   - `enum platform { NONE, SDL, X11, X11_VDPAU, X11_VAAPI, PI, MMAL, IMX, AML, RK, V4L2M2M, FAKE };` — append before `FAKE` to preserve existing enum values.

7. **`src/platform.c`** (`+ ~25 lines`):
   - In `platform_check`: add a `#ifdef HAVE_V4L2M2M` branch matching `"v4l2m2m"` that dlopens `libmoonlight-v4l2m2m.so` and probes for the presence of `/dev/dri/renderD128` (or a successful `v4l2_capability` query on `/dev/video0`).
   - In `platform_get_video`: `case V4L2M2M: return dlsym(RTLD_DEFAULT, "decoder_callbacks_v4l2m2m");`.
   - In `platform_prefers_codec`: add `V4L2M2M` to the `CODEC_HEVC: return true` list (since we exist for HEVC).
   - In `platform_name`: `case V4L2M2M: return "V4L2 M2M + freedreno (EGL dmabuf)";`.

8. **`src/main.c`** (`:213`): update the `-platform` usage string to include `v4l2m2m`.

9. **`CMakeLists.txt`** (`+ ~10 lines`, mirroring `:155-163`):
   ```cmake
   if(V4L2M2M_FOUND)
     list(APPEND MOONLIGHT_DEFINITIONS HAVE_V4L2M2M)
     list(APPEND MOONLIGHT_OPTIONS V4L2M2M)
     add_library(moonlight-v4l2m2m SHARED
       ./src/video/v4l2m2m.c
       ./src/video/egl.c
       ./src/video/ffmpeg.c
       ./src/util.c)
     target_include_directories(moonlight-v4l2m2m PRIVATE ${V4L2M2M_INCLUDE_DIRS} ${AVCODEC_INCLUDE_DIRS} ${AVUTIL_INCLUDE_DIRS} ${GAMESTREAM_INCLUDE_DIR} ${MOONLIGHT_COMMON_INCLUDE_DIR})
     target_link_libraries(moonlight-v4l2m2m gamestream ${V4L2M2M_LIBRARIES} ${AVCODEC_LIBRARIES} ${AVUTIL_LIBRARIES})
     install(TARGETS moonlight-v4l2m2m DESTINATION ${CMAKE_INSTALL_LIBDIR})
   endif()
   ```
   - Also extend the `HAVE_EMBEDDED` aggregator at `:214` to include `V4L2M2M_FOUND`.

### Open questions / risks for the planner
- **Surface choice**: GBM+KMS (no compositor) vs Wayland (with one). RockNIX on SM8550 — does it ship a compositor? If yes, EGL bootstrap reuses Wayland; if no, we need a GBM path mirroring rk's DRM ownership. This is the single biggest unknown.
- **Buffer pool depth**: V4L2 CAPTURE typically allocates 4–8 buffers; we must hold the `AVFrame*` ref until `eglSwapBuffers` returns *and* the GPU is done. A 1-frame display queue is usually enough; verify with `EGL_KHR_fence_sync` or just `glFinish` before unref in the first iteration.
- **Modifier negotiation**: `hevc_v4l2m2m` on SM8550 may produce tiled NV12 with a Qualcomm-specific modifier. Mesa freedreno must accept it as a dmabuf import; if not, fall back to `DRM_FORMAT_MOD_LINEAR` by querying `V4L2_PIX_FMT_NV12` (linear) instead of `V4L2_PIX_FMT_NV12_UBWC`.
- **Reference counting on AVFrame**: `ffmpeg_get_frame()` returns a frame from a small ring buffer (`dec_frames[]`, see `src/video/ffmpeg.c:170-184`). When we hand the pointer to the render thread, the **next** call to `ffmpeg_get_frame` will overwrite the same slot. We must `av_frame_clone()` or `av_frame_ref()` before queueing — `ffmpeg.c` as written does not do this. This is a real bug source for any async-render plugin. Worth either:
  - Refcounting in the v4l2m2m plugin (clone on hand-off), or
  - Adding `av_frame_ref` in `ffmpeg_get_frame(native_frame=true)` and a matching `ffmpeg_put_frame()` API.
- **HDR**: defer entirely for the first patch. SDR-only path is enough to validate the pipeline.

---

## Start here

Open **`src/video/rk.c:178-285`** (the `frame_thread` info-change + normal-frame branches). That single function captures the entire zero-copy idea: register an *external* pool of dmabuf-backed buffers with the decoder, then on each output frame look up the corresponding pre-built display object by fd. Our v4l2m2m plugin inverts the ownership (FFmpeg/V4L2 owns the pool, we just import per-frame), but the **per-frame lookup → display submit** shape carries over verbatim. After that, read `src/video/x11.c:54-66, 147-152, 181-202` to see the pipefd-based render-thread pattern we'll copy, and skim `src/video/ffmpeg_vaapi.c:31-50` for the `get_format` + `hw_device_ctx` install pattern we'll mirror for `AV_PIX_FMT_DRM_PRIME`.
