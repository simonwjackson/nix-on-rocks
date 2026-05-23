# Research: FFmpeg `hevc_v4l2m2m` → DRM_PRIME → EGL/GLES zero-copy contract

> **Sourcing note.** The web search backend was unavailable in this session
> (no `BRAVE_API_KEY` / `SERPER_API_KEY`), so this brief is compiled from
> direct knowledge of the FFmpeg public headers, the Khronos EGL extension
> specs, and the upstream Linux V4L2 stateful-decoder documentation. Every
> claim that I cannot pin to a specific file/line **without** running a fresh
> search is marked **[unverified]**. Anything marked **[verifiable from
> upstream headers]** is reproducible by reading the named header in any
> recent FFmpeg checkout, but no URL was fetched here.

---

## Summary

To get zero-copy frames out of FFmpeg's `hevc_v4l2m2m` (or `h264_v4l2m2m`)
decoder you:

1. Open the decoder by **name** (`avcodec_find_decoder_by_name`) so you never
   silently fall back to the software HEVC decoder.
2. In `AVCodecContext.get_format`, pick `AV_PIX_FMT_DRM_PRIME` from the offered
   list.
3. Each output `AVFrame` then carries `data[0]` = pointer to an
   `AVDRMFrameDescriptor`. You import its `objects[].fd` set into EGL via
   `EGL_EXT_image_dma_buf_import(_modifiers)` and sample with
   `samplerExternalOES`.
4. The fds are owned by FFmpeg's frame pool. You do **not** `close()` them.
   `av_frame_unref()` returns the buffer to the V4L2 capture queue. EGLImage
   import must complete before unref / before the next decode cycle reuses the
   buffer.

Caveats specific to the Qualcomm SM8550 stack (Venus/iris, Mesa freedreno):
the V4L2 capture-side pixel format the upstream Venus driver advertises is
typically NV12 (8-bit) and P010 (10-bit) on modern kernels; UBWC/compressed
formats (`V4L2_PIX_FMT_QC08C`, `V4L2_PIX_FMT_QC10C`) appeared in mainline
around the v6.x series and are **not** currently consumed by FFmpeg's
`v4l2m2m` decoder wrapper without patches **[unverified, needs confirmation
against current kernel + FFmpeg trees]**.

---

## 1. Decoder selection

### Signatures (from `libavcodec/avcodec.h`)

```c
const AVCodec *avcodec_find_decoder(enum AVCodecID id);
const AVCodec *avcodec_find_decoder_by_name(const char *name);
```

Both return `NULL` if nothing matches. `_by_name` matches against
`AVCodec.name` (e.g. `"hevc"`, `"hevc_v4l2m2m"`, `"hevc_rkmpp"`,
`"hevc_qsv"`, …). `avcodec_find_decoder(AV_CODEC_ID_HEVC)` returns the
*first* registered decoder for that codec id, which in a stock FFmpeg build
is the software `"hevc"` decoder — it does **not** prefer hardware variants.

**Practical rule:** for a hardware path, always use
`avcodec_find_decoder_by_name("hevc_v4l2m2m")` and treat `NULL` as "this
build wasn't configured with `--enable-v4l2-m2m`, fall back to software".

### Version availability

- `h264_v4l2m2m` and `hevc_v4l2m2m` wrappers live under
  `libavcodec/v4l2_m2m_dec.c` and were merged into FFmpeg around the **4.0**
  release (HEVC support landed slightly after H.264). They are gated by
  `--enable-v4l2-m2m` at configure time **[verifiable from the FFmpeg
  changelog / configure]**.
- `AV_PIX_FMT_DRM_PRIME` and the `AVDRMFrameDescriptor` API in
  `libavutil/hwcontext_drm.h` were added in FFmpeg **3.4** (mid-2017)
  **[verifiable from libavutil/version.h history]**.
- The `v4l2m2m` decoder did **not** emit `AV_PIX_FMT_DRM_PRIME` from day one.
  DRM_PRIME output via `V4L2_MEMORY_DMABUF` on the capture queue stabilised
  around the **4.x → 5.x** window and is selected by passing
  `-pixel_format drm_prime` (CLI) or by accepting `AV_PIX_FMT_DRM_PRIME` from
  `get_format` (API). On older builds it returns `AV_PIX_FMT_NV12` /
  `AV_PIX_FMT_YUV420P` in regular `AVFrame.data[]` planes and there is no
  zero-copy path. **[Version of stabilisation: unverified; check
  `libavcodec/v4l2_m2m_dec.c` and `v4l2_buffers.c` in your target FFmpeg.]**

### Recommended open sequence

```c
const AVCodec *codec = avcodec_find_decoder_by_name("hevc_v4l2m2m");
if (!codec) { /* fall back to avcodec_find_decoder(AV_CODEC_ID_HEVC) */ }

AVCodecContext *ctx = avcodec_alloc_context3(codec);
ctx->get_format = negotiate_drm_prime;          /* see §2 */
ctx->opaque     = my_app_state;                 /* optional */
/* No av_hwdevice_ctx_create() call is mandatory for v4l2m2m — see §3. */

if (avcodec_open2(ctx, codec, NULL) < 0) { /* error */ }
```

---

## 2. `get_format` callback

### Signature

```c
/* libavcodec/avcodec.h */
enum AVPixelFormat (*get_format)(struct AVCodecContext *s,
                                 const enum AVPixelFormat *fmt);
```

`fmt` is a `AV_PIX_FMT_NONE`-terminated array of pixel formats the decoder is
*willing* to output for the current stream. The callback must return one of
them (or `AV_PIX_FMT_NONE` to abort).

### When it's called

Called from inside `avcodec_send_packet` / the decoder's first real decode,
after the bitstream has been parsed enough to know profile / chroma / bit
depth — i.e. after SPS for H.264/HEVC. It may be called again on stream
parameter changes (resolution change, new SPS).

### How to pick `AV_PIX_FMT_DRM_PRIME`

```c
static enum AVPixelFormat negotiate_drm_prime(AVCodecContext *ctx,
                                              const enum AVPixelFormat *fmts)
{
    for (const enum AVPixelFormat *p = fmts; *p != AV_PIX_FMT_NONE; p++) {
        if (*p == AV_PIX_FMT_DRM_PRIME)
            return *p;
    }
    /* Decoder did not offer DRM_PRIME on this build/kernel.
     * Either accept a software format (return fmts[0]) and copy,
     * or return AV_PIX_FMT_NONE to fail hard. */
    av_log(ctx, AV_LOG_WARNING,
           "hevc_v4l2m2m did not offer AV_PIX_FMT_DRM_PRIME; "
           "falling back to %s\n", av_get_pix_fmt_name(fmts[0]));
    return fmts[0];
}
```

If `AV_PIX_FMT_DRM_PRIME` is **not** offered, typical causes are:
- FFmpeg built without `--enable-libdrm` / `--enable-v4l2-m2m`
  **[unverified — flag name from memory; check `./configure --help`]**.
- Kernel V4L2 decoder does not support `V4L2_MEMORY_DMABUF` export on the
  capture queue.
- Older FFmpeg version that always copies to system memory.

### Equivalent CLI

`ffmpeg -c:v hevc_v4l2m2m -pixel_format drm_prime -i in.hevc ...` — useful
for smoke-testing whether the wrapper exposes DRM_PRIME at all on your
target board before writing C.

---

## 3. `AV_HWDEVICE_TYPE_DRM` vs `AV_HWDEVICE_TYPE_VAAPI`

### Does `hevc_v4l2m2m` need `av_hwdevice_ctx_create(AV_HWDEVICE_TYPE_DRM, …)`?

**No.** Unlike VAAPI / QSV / CUDA, the `v4l2m2m` decoder wrapper opens the
V4L2 device itself (driven by the `device` AVOption or autodetection of
`/dev/videoN`). It does **not** require the caller to attach an
`AVHWDeviceContext` of type `AV_HWDEVICE_TYPE_DRM` to
`AVCodecContext.hw_device_ctx`, and it does **not** require a pre-built
`hw_frames_ctx` of type DRM. The frame pool is allocated internally by the
V4L2 wrapper when it programs the capture queue.

This is in contrast to VAAPI / DRM-as-render-node decoders where you must:

```c
av_hwdevice_ctx_create(&hw, AV_HWDEVICE_TYPE_VAAPI, "/dev/dri/renderD128",
                       NULL, 0);
ctx->hw_device_ctx = av_buffer_ref(hw);
```

and then `hw_frames_ctx` is set up either by the decoder or by you in
`get_format`.

`AV_HWDEVICE_TYPE_DRM` exists (`libavutil/hwcontext_drm.h`) and is used by
the **mapping** API — e.g. `av_hwframe_map()` to convert a VAAPI frame into a
`AV_PIX_FMT_DRM_PRIME` frame for downstream EGL — but for `v4l2m2m` you
receive `AV_PIX_FMT_DRM_PRIME` directly without going through it.

### What `hw_frames_ctx` you'll actually see

After the first frame is decoded, `AVFrame.hw_frames_ctx` on the returned
frame may or may not be populated depending on FFmpeg version
**[unverified]**. What you can rely on is:

- `frame->format == AV_PIX_FMT_DRM_PRIME`
- `frame->data[0]` is an `AVDRMFrameDescriptor *` (cast it — see §4)
- `frame->buf[0]` is the `AVBufferRef` that owns the descriptor's lifetime.

### When DRM hwdevice **is** useful for this pipeline

Only if you want to **map** the resulting `AV_PIX_FMT_DRM_PRIME` frame to a
different domain (e.g. import it into VAAPI for post-processing). For the
"V4L2 decoder → EGL display" path you do not need it.

---

## 4. `AVDRMFrameDescriptor` layout

Defined in `libavutil/hwcontext_drm.h` **[verifiable from upstream header]**:

```c
enum { AV_DRM_MAX_PLANES = 4 };

typedef struct AVDRMPlaneDescriptor {
    int          object_index;   /* index into objects[] */
    ptrdiff_t    offset;         /* byte offset of plane within the object */
    ptrdiff_t    pitch;          /* row stride in bytes */
} AVDRMPlaneDescriptor;

typedef struct AVDRMLayerDescriptor {
    uint32_t              format;        /* DRM_FORMAT_* fourcc */
    int                   nb_planes;
    AVDRMPlaneDescriptor  planes[AV_DRM_MAX_PLANES];
} AVDRMLayerDescriptor;

typedef struct AVDRMObjectDescriptor {
    int       fd;               /* dma-buf file descriptor (owned by AVFrame) */
    size_t    size;             /* size of the buffer object in bytes */
    uint64_t  format_modifier;  /* DRM_FORMAT_MOD_* */
} AVDRMObjectDescriptor;

typedef struct AVDRMFrameDescriptor {
    int                       nb_objects;
    AVDRMObjectDescriptor     objects[AV_DRM_MAX_PLANES];
    int                       nb_layers;
    AVDRMLayerDescriptor      layers[AV_DRM_MAX_PLANES];
} AVDRMFrameDescriptor;
```

### Semantics worth knowing

- **One layer = one logical image** (an NV12 frame is *one* layer with
  *two* planes, not two layers).
- **`nb_objects` may be 1 even for NV12.** V4L2 commonly exports the luma
  and chroma planes as a single contiguous dma-buf; the two planes live at
  different offsets in the same object. EGL import for NV12 must then point
  both `EGL_DMA_BUF_PLANE0_FD_EXT` and `EGL_DMA_BUF_PLANE1_FD_EXT` at the
  **same** fd, with different `_OFFSET_EXT`s.
- **`format_modifier` is per-object**, not per-layer. For linear NV12 it is
  `DRM_FORMAT_MOD_LINEAR` (= 0). For Qualcomm UBWC tiled formats it is
  `DRM_FORMAT_MOD_QCOM_COMPRESSED` (defined in `drm/drm_fourcc.h` upstream).
- Common `layers[].format` values you may see:
  - `DRM_FORMAT_NV12` — 8-bit 4:2:0, two planes Y / interleaved CbCr.
  - `DRM_FORMAT_P010` — 10-bit 4:2:0 in 16-bit containers, two planes.
  - `DRM_FORMAT_NV21` — Y / interleaved CrCb (chroma order swapped).
  - `DRM_FORMAT_NV12_Y_TILED_INTEL` — *deprecated* style; modern Intel uses
    `DRM_FORMAT_NV12` + `I915_FORMAT_MOD_Y_TILED` modifier. Not relevant on
    Qualcomm hardware.
  - Qualcomm UBWC: `DRM_FORMAT_NV12` (or `DRM_FORMAT_P010`) +
    `DRM_FORMAT_MOD_QCOM_COMPRESSED`. There is no separate fourcc for the
    UBWC layout; it is expressed by the modifier.

### Extraction snippet

```c
#include <libavutil/hwcontext_drm.h>
#include <drm_fourcc.h>

static int import_drm_frame(AVFrame *frame, struct egl_image_out *out)
{
    if (frame->format != AV_PIX_FMT_DRM_PRIME)
        return -1;

    const AVDRMFrameDescriptor *desc =
        (const AVDRMFrameDescriptor *)frame->data[0];

    if (desc->nb_layers != 1)
        return -1;                       /* multi-layer frames not handled */

    const AVDRMLayerDescriptor *layer = &desc->layers[0];

    out->fourcc        = layer->format;
    out->nb_planes     = layer->nb_planes;
    out->width         = frame->width;
    out->height        = frame->height;

    for (int p = 0; p < layer->nb_planes; p++) {
        const AVDRMPlaneDescriptor *pl = &layer->planes[p];
        const AVDRMObjectDescriptor *obj = &desc->objects[pl->object_index];

        out->planes[p].fd        = obj->fd;             /* DO NOT close */
        out->planes[p].offset    = pl->offset;
        out->planes[p].pitch     = pl->pitch;
        out->planes[p].modifier  = obj->format_modifier;
    }
    return 0;
}
```

---

## 5. DMA-buf fd lifecycle

### Ownership

- The fds in `desc->objects[i].fd` are **owned by `frame->buf[0]`'s
  `AVBufferRef`**, which in turn is owned by FFmpeg's V4L2 capture-queue
  buffer pool.
- The consumer (EGL importer) **must not** `close()` these fds. EGL's
  `eglCreateImageKHR` with `EGL_LINUX_DMA_BUF_EXT` **dups** the fd
  internally (it must, per the spec, so that the caller may close it
  afterwards). FFmpeg holds the *original* — letting you close it as well
  would be a double-close in this design.

### Safe import window

- Safe to call `eglCreateImageKHR` any time between receiving the frame
  from `avcodec_receive_frame()` and dropping the last reference to
  `frame->buf[0]`.
- It is safe to call `av_frame_unref(frame)` **after** `eglCreateImageKHR`
  returns. EGL retains a reference to the underlying dma-buf via its dup.
- The dma-buf memory itself is held alive by either side (kernel
  dma-buf refcount: V4L2 keeps a ref while the buffer is in its pool;
  EGL keeps a ref via its dup'd fd or its GEM import).

### What `av_frame_unref` does

When the last reference to `frame->buf[0]` is dropped, FFmpeg's V4L2
wrapper requeues the underlying V4L2 buffer to the capture queue
(`VIDIOC_QBUF`), making it eligible to be filled with the next decoded
frame. **If you re-use the EGLImage / sample from the texture after this
point and the buffer has been recycled, you will see tearing / the next
frame's contents.** This is the most common bug.

### Recommended discipline

```c
/* 1. receive */
avcodec_receive_frame(ctx, frame);

/* 2. import: EGL dups the fd internally */
EGLImageKHR img = eglCreateImageKHR(dpy, EGL_NO_CONTEXT,
                                    EGL_LINUX_DMA_BUF_EXT, NULL, attribs);

/* 3. bind to a GL_TEXTURE_EXTERNAL_OES texture */
glBindTexture(GL_TEXTURE_EXTERNAL_OES, tex);
glEGLImageTargetTexture2DOES(GL_TEXTURE_EXTERNAL_OES, img);

/* 4. draw using the texture (issue GL commands).
 *    The GL driver now holds its own reference to the underlying BO. */
draw_frame(tex);

/* 5. it is now safe to release the FFmpeg frame; the BO stays alive
 *    until GL is done. */
eglDestroyImageKHR(dpy, img);   /* drops EGL's dup ref */
av_frame_unref(frame);          /* drops FFmpeg's ref → V4L2 requeue */
```

### Common bugs

1. **`close(fd)` after import** — double-close, since FFmpeg owns it and
   EGL dups it.
2. **`av_frame_unref` before `eglCreateImageKHR`** — buffer may be
   requeued and overwritten before EGL imports.
3. **Caching one EGLImage per fd** — fds get reused across frames as
   buffers are recycled. Compare by `(fd, offset, modifier)` *and* the
   `AVBufferRef` identity if you must cache.
4. **Drawing after `av_frame_unref` without GL having flushed** — if your
   GL driver lazily imports / doesn't take a refcount until draw, you can
   race the V4L2 recycle. Safest is to `glFinish()` or use a fence
   (`EGL_KHR_fence_sync`) before unref.

---

## 6. Output format control for v4l2m2m

### Who chooses the capture-side pixel format

The V4L2 stateful decoder API specifies a negotiation between userspace and
driver via `VIDIOC_ENUM_FMT` / `VIDIOC_S_FMT` on the capture (`CAPTURE`)
queue. **FFmpeg's `v4l2m2m` wrapper drives this internally.** The consumer
cannot directly inject a `VIDIOC_S_FMT` from outside.

In practice the wrapper picks the *first* capture format from the driver's
enumeration that it knows how to map to an `AVPixelFormat`
**[verifiable in `libavcodec/v4l2_m2m.c` / `v4l2_fmt.c`]**. Drivers that
advertise a compressed/tiled format *first* (e.g. Venus advertising
`V4L2_PIX_FMT_QC08C` ahead of `V4L2_PIX_FMT_NV12`) will produce frames in
that format whether or not the FFmpeg wrapper has a mapping for it; if it
does **not** have a mapping, `avcodec_open2()` may fail or fall back.

### Asking for linear NV12

There is no clean public AVOption to say "give me linear NV12 specifically".
Available levers:

- The `pixel_format` AVOption / `-pixel_format` CLI option selects the
  **AVPixelFormat** the wrapper will negotiate to the *user* (e.g.
  `drm_prime`, `nv12`, `yuv420p`). It does **not** override the V4L2
  capture fourcc.
- Some forks (notably the LibreELEC / Kodi tree) carry patches that add an
  explicit V4L2 fourcc selector, e.g. `-fourcc NM12` or `-fourcc Q08C`,
  for exactly this use case **[unverified]**.
- The "right" upstream fix is to teach the driver to advertise the linear
  format first when the client doesn't request the tiled one, or for
  FFmpeg to call `VIDIOC_S_FMT` with the application's preferred fourcc.

### Qualcomm Venus / iris capture-side formats

(`iris` is the new Qualcomm V4L2 driver replacing `venus` on SM8550+
**[unverified for SM8550 specifically — confirm with `dmesg` / `v4l2-ctl
--list-formats-ext -d /dev/videoN` on the target board]**.)

Typical formats you may see enumerated on the capture queue:

| V4L2 fourcc            | DRM equivalent                                | Notes                                |
| ---------------------- | --------------------------------------------- | ------------------------------------ |
| `V4L2_PIX_FMT_NV12`    | `DRM_FORMAT_NV12`, linear modifier            | 8-bit, semi-planar, linear           |
| `V4L2_PIX_FMT_NV12M`   | same fourcc, multi-planar layout              | two dma-bufs (one per plane)         |
| `V4L2_PIX_FMT_QC08C`   | `DRM_FORMAT_NV12` + `DRM_FORMAT_MOD_QCOM_COMPRESSED` | UBWC 8-bit                |
| `V4L2_PIX_FMT_QC10C`   | `DRM_FORMAT_P010` + `DRM_FORMAT_MOD_QCOM_COMPRESSED` | UBWC 10-bit               |
| `V4L2_PIX_FMT_P010`    | `DRM_FORMAT_P010`, linear                     | 10-bit, semi-planar, may be absent on Venus |

The exact set is kernel-version and driver-build dependent. Run
`v4l2-ctl --list-formats-ext -d /dev/video0` (or whichever node the decoder
appears on) on the target image to ground-truth this.

### Practical recommendation for SM8550

If freedreno cannot sample the UBWC modifier through
`EGL_EXT_image_dma_buf_import_modifiers` (see §7), the cleanest fix is at
the **driver/FFmpeg** boundary, not the EGL boundary: either patch the
v4l2m2m wrapper to prefer the linear fourcc, or use the
`v4l2-request`-based decoder where modifier negotiation is explicit, or
fall back to a software copy via `libyuv` or `sws_scale`.

---

## 7. 10-bit HEVC (Main 10) output

### Format options

- `DRM_FORMAT_P010` — two planes; each component stored in the upper 10 of
  16 bits.
- `DRM_FORMAT_P016` — same layout, 16 bits used (less common from decoders).
- `V4L2_PIX_FMT_QC10C` — Qualcomm UBWC 10-bit; surfaces as
  `DRM_FORMAT_P010` + `DRM_FORMAT_MOD_QCOM_COMPRESSED`.

### What FFmpeg's v4l2m2m wrapper negotiates

Depends on what the driver enumerates first. On Venus you may get the UBWC
format unless the driver/build prefers `P010`. FFmpeg's mapping table in
`libavcodec/v4l2_fmt.c` determines which V4L2 fourccs are even considered
**[verify against the FFmpeg version you ship]**. On older FFmpeg builds
10-bit may not be wired through at all and HEVC Main 10 streams fall back
to software.

### Known issues sampling 10-bit DMA-buf in GLES on freedreno

- `samplerExternalOES` is defined to give you RGBA after YUV conversion,
  but Mesa's implementation of the YUV→RGB conversion path for **P010**
  has historically been less mature than for NV12. Whether freedreno's
  current Mesa implements the 10-bit external-image sampler correctly is
  **[unverified — check Mesa's `src/gallium/drivers/freedreno` and
  `src/egl/drivers/dri2/platform_drm.c` for the modifier/fourcc table the
  freedreno driver advertises]**.
- The UBWC modifier (`DRM_FORMAT_MOD_QCOM_COMPRESSED`) on **P010** is even
  less likely to be supported in the EGL importer than on NV12.
- Workaround: have FFmpeg/Venus produce **linear P010**, then either
  (a) sample directly if freedreno supports it, or (b) convert to NV12 /
  RGB10A2 with a one-pass compute / blit before sampling.

### Pragmatic fallback

If the EGL import fails for the 10-bit/UBWC combination, log the
`(fourcc, modifier)` pair and fall back to:

1. `av_hwframe_transfer_data()` → software `AVFrame` in `AV_PIX_FMT_P010`,
2. `sws_scale` to `AV_PIX_FMT_NV12` (or RGBA),
3. `glTexImage2D` upload.

This loses zero-copy but keeps playback working.

---

## 8. EGL import contract

### Required extensions

Query `eglQueryString(dpy, EGL_EXTENSIONS)`:

- `EGL_KHR_image_base` — gives you `EGLImageKHR` and `eglCreateImageKHR` /
  `eglDestroyImageKHR`.
- `EGL_EXT_image_dma_buf_import` — base dma-buf import (mandatory).
- `EGL_EXT_image_dma_buf_import_modifiers` — required if you ever pass a
  non-`DRM_FORMAT_MOD_LINEAR` / non-`DRM_FORMAT_MOD_INVALID` modifier
  (i.e. any tiled / compressed format). Also lets you enumerate supported
  `(fourcc, modifier)` pairs via `eglQueryDmaBufFormatsEXT` /
  `eglQueryDmaBufModifiersEXT`.
- GL extension: `GL_OES_EGL_image_external` (GLES2) /
  `GL_OES_EGL_image_external_essl3` (GLES3) — provides
  `glEGLImageTargetTexture2DOES` and the `samplerExternalOES` type.

### Full attrib list for NV12 (two planes, one dma-buf object)

```c
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <drm_fourcc.h>

static EGLImageKHR import_nv12(EGLDisplay dpy,
                               int width, int height,
                               int fd,             /* same fd for both planes */
                               uint64_t modifier,
                               ptrdiff_t y_offset, int y_pitch,
                               ptrdiff_t uv_offset, int uv_pitch)
{
    const EGLint attribs[] = {
        EGL_WIDTH,                     width,
        EGL_HEIGHT,                    height,
        EGL_LINUX_DRM_FOURCC_EXT,      DRM_FORMAT_NV12,

        /* Plane 0 (Y) */
        EGL_DMA_BUF_PLANE0_FD_EXT,     fd,
        EGL_DMA_BUF_PLANE0_OFFSET_EXT, (EGLint)y_offset,
        EGL_DMA_BUF_PLANE0_PITCH_EXT,  y_pitch,
        EGL_DMA_BUF_PLANE0_MODIFIER_LO_EXT, (EGLint)(modifier & 0xffffffff),
        EGL_DMA_BUF_PLANE0_MODIFIER_HI_EXT, (EGLint)(modifier >> 32),

        /* Plane 1 (CbCr) — same fd, different offset */
        EGL_DMA_BUF_PLANE1_FD_EXT,     fd,
        EGL_DMA_BUF_PLANE1_OFFSET_EXT, (EGLint)uv_offset,
        EGL_DMA_BUF_PLANE1_PITCH_EXT,  uv_pitch,
        EGL_DMA_BUF_PLANE1_MODIFIER_LO_EXT, (EGLint)(modifier & 0xffffffff),
        EGL_DMA_BUF_PLANE1_MODIFIER_HI_EXT, (EGLint)(modifier >> 32),

        /* Optional but recommended for video frames: */
        EGL_YUV_COLOR_SPACE_HINT_EXT,  EGL_ITU_REC709_EXT,
        EGL_SAMPLE_RANGE_HINT_EXT,     EGL_YUV_NARROW_RANGE_EXT,
        EGL_YUV_CHROMA_HORIZONTAL_SITING_HINT_EXT, EGL_YUV_CHROMA_SITING_0_EXT,
        EGL_YUV_CHROMA_VERTICAL_SITING_HINT_EXT,   EGL_YUV_CHROMA_SITING_0_5_EXT,

        EGL_NONE
    };

    return eglCreateImageKHR(dpy, EGL_NO_CONTEXT,
                             EGL_LINUX_DMA_BUF_EXT,
                             (EGLClientBuffer)NULL, attribs);
}
```

Notes:
- `EGL_DMA_BUF_PLANEi_MODIFIER_{LO,HI}_EXT` are **only legal** if
  `EGL_EXT_image_dma_buf_import_modifiers` is present. Omit them for the
  base extension and the implementation treats it as
  `DRM_FORMAT_MOD_INVALID` (implementation chooses, usually only LINEAR).
- For multi-object frames (one fd per plane), pass `desc->objects[
  plane->object_index].fd` for each plane.
- The YUV hint attribs are optional but materially affect color
  correctness; the default in some drivers is BT.601 limited range, which
  for HEVC content is wrong (HEVC tends to be BT.709 or BT.2020).

### GL side

```c
GLuint tex;
glGenTextures(1, &tex);
glBindTexture(GL_TEXTURE_EXTERNAL_OES, tex);
glTexParameteri(GL_TEXTURE_EXTERNAL_OES, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
glTexParameteri(GL_TEXTURE_EXTERNAL_OES, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
glTexParameteri(GL_TEXTURE_EXTERNAL_OES, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
glTexParameteri(GL_TEXTURE_EXTERNAL_OES, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
glEGLImageTargetTexture2DOES(GL_TEXTURE_EXTERNAL_OES, img);
```

Fragment shader (GLES2):

```glsl
#extension GL_OES_EGL_image_external : require
precision mediump float;
uniform samplerExternalOES uTex;
varying vec2 vUV;
void main() {
    gl_FragColor = texture2D(uTex, vUV);   /* already RGBA */
}
```

Fragment shader (GLES3, ESSL 3.00):

```glsl
#version 300 es
#extension GL_OES_EGL_image_external_essl3 : require
precision mediump float;
uniform samplerExternalOES uTex;
in vec2 vUV;
out vec4 fragColor;
void main() {
    fragColor = texture(uTex, vUV);
}
```

`samplerExternalOES` performs the YUV→RGB conversion (and de-tiles /
de-compresses if the driver supports the modifier). The vertex shader is
unchanged from a normal `sampler2D` pipeline.

---

## 9. Fallback / failure modes

### Failure surfaces of `eglCreateImageKHR`

Returns `EGL_NO_IMAGE_KHR`. Inspect `eglGetError()`:

- `EGL_BAD_MATCH` — most common signal that the `(fourcc, modifier)` pair
  is not in the driver's supported list. E.g. asking freedreno to import
  `DRM_FORMAT_NV12` + `DRM_FORMAT_MOD_QCOM_COMPRESSED` when its
  enumeration only lists `DRM_FORMAT_MOD_LINEAR`.
- `EGL_BAD_ACCESS` — the fd is not a dma-buf, was closed, or the kernel
  refuses the import (typical when the underlying memory is not
  CPU-cached/coherent in a way the GPU can access).
- `EGL_BAD_PARAMETER` — malformed attrib list (wrong number of planes for
  the fourcc, missing required attribs, modifier-LO/HI without the
  modifiers extension).
- `EGL_BAD_ALLOC` — out-of-memory in the GEM importer.

### Pre-flight: enumerate supported pairs

```c
PFNEGLQUERYDMABUFFORMATSEXTPROC qfmts =
    (void *)eglGetProcAddress("eglQueryDmaBufFormatsEXT");
PFNEGLQUERYDMABUFMODIFIERSEXTPROC qmods =
    (void *)eglGetProcAddress("eglQueryDmaBufModifiersEXT");

EGLint nfmts = 0;
qfmts(dpy, 0, NULL, &nfmts);
EGLint *fmts = calloc(nfmts, sizeof *fmts);
qfmts(dpy, nfmts, fmts, &nfmts);

/* For each fourcc you care about: */
EGLint nmods = 0;
qmods(dpy, DRM_FORMAT_NV12, 0, NULL, NULL, &nmods);
uint64_t *mods = calloc(nmods, sizeof *mods);
EGLBoolean *external = calloc(nmods, sizeof *external);
qmods(dpy, DRM_FORMAT_NV12, nmods, mods, external, &nmods);
/* `external[i]` indicates the modifier requires GL_TEXTURE_EXTERNAL_OES. */
```

This lets you decide **before** even opening the decoder whether your
zero-copy path is viable, and pick the correct fallback up front.

### Graceful degrade

```c
/* attempt zero-copy */
EGLImageKHR img = import_nv12(...);
if (img == EGL_NO_IMAGE_KHR) {
    EGLint err = eglGetError();
    av_log(NULL, AV_LOG_WARNING,
           "EGL dma-buf import failed (fourcc=0x%08x mod=0x%" PRIx64
           ") err=0x%04x — falling back to software upload\n",
           fourcc, modifier, err);
    upload_via_glteximage2d(frame);     /* sws_scale + glTexImage2D */
}
```

Make the fallback path *also* exercise the same texture interface so that
the rest of the renderer doesn't care which path produced the texture
(see Bedrock: "Convert async/runtime primitives into domain-specific
tagged unions" — model the result as `Imported(EGLImageKHR) |
Uploaded(GLuint)`, not as a boolean flag).

---

## 10. Reference projects with working code

All paths are upstream-tree-relative. The code is the source of truth;
treat any prose summary (including this one) as a hint.

- **FFmpeg's own example.** `doc/examples/hw_decode.c` — minimal end-to-end
  hardware decode with `get_format` negotiation and `av_hwframe_transfer_data`.
  Doesn't use DRM_PRIME directly but shows the negotiation pattern.
- **FFmpeg v4l2m2m source.** `libavcodec/v4l2_m2m.c`,
  `libavcodec/v4l2_m2m_dec.c`, `libavcodec/v4l2_buffers.c`,
  `libavcodec/v4l2_fmt.c`. The mapping from V4L2 fourcc ↔ `AVPixelFormat`
  and the DRM_PRIME export path live here. Read these for the *actual*
  semantics on the FFmpeg version you ship.
- **FFmpeg DRM hwcontext.** `libavutil/hwcontext_drm.h` and
  `libavutil/hwcontext_drm.c` — the descriptor type and the
  `av_hwframe_map` plumbing.
- **mpv.** `video/out/hwdec/hwdec_drmprime.c` and the corresponding EGL
  importer in `video/out/opengl/hwdec_drmprime_overlay.c` /
  `video/out/hwdec/hwdec_drmprime_drm.c` — production-quality consumer of
  `AV_PIX_FMT_DRM_PRIME` over EGL. Path names have drifted across mpv
  versions; grep for `AV_PIX_FMT_DRM_PRIME` in the mpv tree.
- **Kodi.** `xbmc/cores/VideoPlayer/DVDCodecs/Video/DVDVideoCodecDRMPRIME.cpp`
  and `xbmc/cores/VideoPlayer/VideoRenderers/HwDecRender/RendererDRMPRIMEGLES.cpp`.
  The Kodi/LibreELEC/CoreELEC trees carry the most battle-tested v4l2m2m +
  EGL path, including the SoC-specific quirks. The LibreELEC fork
  (`libreelec/LibreELEC.tv` on GitHub) carries the FFmpeg patches that
  expose the fourcc-selection option.
- **gstreamer.** `subprojects/gst-plugins-bad/sys/v4l2codecs/` — modern
  V4L2 stateless decoder; `gstv4l2codecsh264dec.c` etc. Not directly
  FFmpeg, but the kernel-side contract is identical and the EGL/GL import
  in `gst-plugins-base/ext/gl/gstglmemorydma.c` is a good reference.
- **gstreamer-vaapi** (legacy) — only useful if you want to compare the
  VAAPI dma-buf export path (`gstvaapidisplay_drm.c`) with the v4l2m2m one.
- **Mesa, freedreno side.** `src/gallium/drivers/freedreno/freedreno_resource.c`
  and `src/egl/main/eglimage.c` / `src/egl/drivers/dri2/egl_dri2.c` —
  authoritative answer for "which (fourcc, modifier) tuples can EGL
  actually import on this driver".
- **Kernel V4L2 docs.** `Documentation/userspace-api/media/v4l/dev-decoder.rst`
  and `Documentation/userspace-api/media/drivers/qcom-venus.rst` (or the
  iris equivalent on newer trees).

---

## Sources

All citations are to upstream source paths rather than URLs, because
web search was unavailable in this session.

- Kept:
  - `libavutil/hwcontext_drm.h` — authoritative `AVDRMFrameDescriptor`
    layout and ownership semantics.
  - `libavcodec/avcodec.h` — `avcodec_find_decoder_by_name`, `get_format`
    signatures.
  - `libavcodec/v4l2_m2m_dec.c` / `v4l2_fmt.c` — actual v4l2m2m
    DRM_PRIME negotiation and fourcc table.
  - Khronos `EGL_EXT_image_dma_buf_import` and
    `EGL_EXT_image_dma_buf_import_modifiers` extension specs — attrib
    names, error semantics, fd dup semantics.
  - Khronos `GL_OES_EGL_image_external` / `_essl3` specs —
    `samplerExternalOES`, `glEGLImageTargetTexture2DOES`.
  - `include/uapi/drm/drm_fourcc.h` (kernel) — `DRM_FORMAT_NV12`,
    `DRM_FORMAT_P010`, `DRM_FORMAT_MOD_LINEAR`,
    `DRM_FORMAT_MOD_QCOM_COMPRESSED`.
  - `Documentation/userspace-api/media/v4l/dev-decoder.rst` (kernel) —
    V4L2 stateful decoder capture-queue negotiation.

- Dropped: none — search backend not available.

---

## Gaps

Items that need verification on the target SM8550 image before depending
on them in code:

1. **FFmpeg version cutoff** at which `hevc_v4l2m2m` reliably emits
   `AV_PIX_FMT_DRM_PRIME`. Check the FFmpeg in the ROCKNIX / LibreELEC /
   custom build you intend to ship.
2. **Which V4L2 driver** is on SM8550 (`venus` vs `iris`) and **which
   capture-side fourccs** it enumerates. Confirm with
   `v4l2-ctl --list-formats-ext -d /dev/videoN` on hardware.
3. **freedreno's `eglQueryDmaBufModifiersEXT` answer** for `DRM_FORMAT_NV12`
   and `DRM_FORMAT_P010` on the Mesa version you ship — specifically
   whether `DRM_FORMAT_MOD_QCOM_COMPRESSED` is in the list. If not, plan
   for forcing linear output at the V4L2 layer.
4. **Whether FFmpeg's wrapper accepts a config knob to pick the V4L2
   capture fourcc**, or whether you need a patch (the LibreELEC fork is
   the place to look for prior art).
5. **10-bit path correctness** in freedreno's `samplerExternalOES` —
   sample a test stream and verify color/quality before committing to
   zero-copy P010.
6. **Behaviour of `hw_frames_ctx` on v4l2m2m DRM_PRIME frames** —
   varies by FFmpeg version; check whether you can rely on it being
   populated for `av_hwframe_map` to other domains.

Suggested next steps:

- Run on-device probes: `v4l2-ctl --list-formats-ext`,
  `eglinfo`, `wlinfo` / `weston-info`, `eglQueryDmaBufFormatsEXT` dump
  from a tiny C program.
- Re-run web search (once a backend key is available) for:
  - `FFmpeg v4l2_m2m_dec.c DRM_PRIME export site:git.ffmpeg.org`
  - `Mesa freedreno modifier NV12 QCOM_COMPRESSED`
  - `Qualcomm iris v4l2 driver mainline NV12 P010 formats`
  - `mpv hwdec drmprime SM8550 OR sdm OR snapdragon`
- Cross-check against the LibreELEC `packages/multimedia/ffmpeg/patches/`
  tree for any v4l2m2m fourcc-selection patches and pick the smallest
  one that applies.
