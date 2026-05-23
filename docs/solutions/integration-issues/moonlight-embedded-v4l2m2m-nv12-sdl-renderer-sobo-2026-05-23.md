---
title: "Moonlight Embedded SM8550 v4l2m2m needs SDL NV12 presentation"
date: 2026-05-23
category: integration-issues
module: moonlight-embedded-sm8550
problem_type: integration_issue
component: tooling
symptoms:
  - "FFmpeg hevc_v4l2m2m opened the Iris decoder but returned NV12 CPU-visible frames instead of DRM_PRIME frames"
  - "Custom GLES presentation produced a cropped top-left view under Sway logical scaling on Sobo"
  - "SDL fullscreen flags did not make the v4l2m2m GL surface adopt the compositor-visible size"
  - "The stream rendered correctly after switching presentation to SDL NV12 texture and SDL renderer"
root_cause: wrong_api
resolution_type: code_fix
severity: high
related_components:
  - moonlight-embedded
  - sm8550
  - ffmpeg-v4l2m2m
  - sdl
  - sway
  - sunshine
tags:
  - moonlight-embedded
  - sm8550
  - v4l2m2m
  - iris-vpu
  - nv12
  - sdl-renderer
  - sway
  - hardware-decode
---

# Moonlight Embedded SM8550 v4l2m2m needs SDL NV12 presentation

## Problem

Moonlight Embedded's new SM8550 `v4l2m2m` platform successfully reached the Iris VPU and received video packets, but the first display design was not shippable. The intended DRM PRIME zero-copy path did not receive DRM PRIME frames from FFmpeg, and the initial custom GLES NV12 fallback rendered video but cropped under Sway/Wayland logical scaling.

The working path is:

```text
Sunshine stream -> hevc_v4l2m2m / Iris VPU -> NV12 AVFrame -> SDL NV12 texture -> SDL renderer
```

This keeps the expensive HEVC decode on hardware while letting SDL own Wayland presentation, resize, monitor, and aspect-fit behavior.

## Symptoms

- `v4l2m2m` platform initialized and opened the hardware decoder:

  ```text
  Platform V4L2 M2M + EGL DMA-BUF (SM8550)
  [hevc_v4l2m2m @ ...] Using device /dev/video0
  [hevc_v4l2m2m @ ...] driver 'iris_driver' on card 'Iris Decoder' in mplane mode
  ```

- FFmpeg advertised DRM PRIME intent, but decoded frames still arrived as NV12:

  ```text
  [hevc_v4l2m2m @ ...] requesting formats: output=HEVC/none capture=NV12/drm_prime
  v4l2m2m: submit: first frame from decoder format=nv12 (DRM_PRIME=no)
  ```

- The custom GLES NV12 renderer produced real video, but Sobo showed only the top-left crop. Sway reported a `960x540` or `960x517` visible logical surface while the v4l2m2m GL surface stayed `1280x720`.

- `SDL_WINDOW_FULLSCREEN_DESKTOP` and `SDL_WINDOW_FULLSCREEN` did not fix the crop. SDL still reported:

  ```text
  window=1280x720 drawable=1280x720 viewport=1280x720
  ```

  while Sway showed the visible window rect as `960x540`.

- The SDL baseline did not crop, because it uses `SDL_RenderCopy()` and lets SDL's renderer scale the decoded texture to the current output.

## What Didn't Work

### Forcing FFmpeg v4l2m2m to emit DRM PRIME

The zero-copy attempt set DRM PRIME intent before opening the decoder:

```c
codec_ctx->pix_fmt = AV_PIX_FMT_DRM_PRIME;
codec_ctx->get_format = get_drm_prime_fmt;

AVBufferRef *hw_dev = NULL;
av_hwdevice_ctx_create(&hw_dev, AV_HWDEVICE_TYPE_DRM,
                       "/dev/dri/renderD128", NULL, 0);
codec_ctx->hw_device_ctx = av_buffer_ref(hw_dev);
```

That changed FFmpeg's log to `capture=NV12/drm_prime`, but `avcodec_receive_frame()` still returned `AV_PIX_FMT_NV12` frames. The `get_format` callback was not a reliable control point for this wrapper on the Iris stateful V4L2 M2M path.

The relevant FFmpeg 8.0 behavior is in `libavcodec/v4l2_m2m_dec.c::v4l2_try_start()`:

```c
avctx->pix_fmt = ff_v4l2_format_v4l2_to_avfmt(
    capture->format.fmt.pix_mp.pixelformat,
    AV_CODEC_ID_RAWVIDEO);

capture->av_pix_fmt = avctx->pix_fmt;
```

On Sobo's Iris driver, `VIDIOC_G_FMT` reports native `NV12`, so the wrapper overwrites the requested DRM PRIME pixel format with NV12. True DRM PRIME zero-copy would require either changing the FFmpeg wrapper behavior or bypassing it and owning the V4L2 capture queue directly with `VIDIOC_EXPBUF`.

### Trying the ffmpeg_drm backend as a shortcut

A prior Plan B probe of the upstream `ffmpeg_drm` backend from PR #932 did not solve this (session history). It initialized its KMS/DRM output path, but selected plain software `hevc` rather than `hevc_v4l2m2m`, reported `DRM_PRIME not available`, and conflicted with the gamescope-owned DRM master model. It was not a drop-in zero-copy path for the Sobo kiosk setup.

### Custom GLES NV12 upload and shader presentation

After accepting NV12, the first fallback uploaded Y and UV planes to GL textures and converted YUV to RGB in a GLES shader. That rendered real content, but it also made the v4l2m2m platform responsible for all presentation behavior:

- Wayland logical output size
- Sway scale/rotation
- fullscreen vs floating behavior
- live resize
- monitor movement
- aspect fit
- dual-screen device targeting for AYN Thor

The bug appeared because the custom GL window was created at the stream size:

```c
SDL_CreateWindow("Moonlight",
                 SDL_WINDOWPOS_UNDEFINED,
                 SDL_WINDOWPOS_UNDEFINED,
                 width, height,                 // 1280x720 stream size
                 SDL_WINDOW_OPENGL | SDL_WINDOW_BORDERLESS);
```

Sobo's Sway output is exposed to Wayland clients as a smaller logical surface (`960x540`, then `960x517` after panel/status area changes), so Sway clipped the `1280x720` surface.

### SDL fullscreen flags

Both fullscreen variants were tried:

```c
SDL_WINDOW_FULLSCREEN_DESKTOP
SDL_WINDOW_FULLSCREEN
```

Neither made SDL adopt Sway's logical size in this environment. SDL still reported `window=1280x720 drawable=1280x720`, so the crop remained.

### Display-bounds plus custom viewport

A temporary fix queried `SDL_GetDisplayUsableBounds()` and rendered a custom aspect-fit quad into that size. It worked on Sobo and handled live resize, but it was still too much custom presentation code. It also defaulted to display 0, which is fragile on dual-screen devices like AYN Thor unless policy is added.

## Solution

### Route v4l2m2m audio through SDL

Before display debugging, the non-SDL v4l2m2m platform also hit the audio cascade: it fell through to Pulse/ALSA, and Sobo's parked audio substrate caused audio init failure to tear down the stream.

Route `V4L2M2M` through SDL audio callbacks so `SDL_AUDIODRIVER=dummy` works for video-only smoke tests:

```c
AUDIO_RENDERER_CALLBACKS* platform_get_audio(enum platform system, char* audio_device) {
  switch (system) {
  case FAKE:
    return NULL;

#ifdef HAVE_SDL
  case SDL:
    return &audio_callbacks_sdl;
#endif

#ifdef HAVE_V4L2M2M
  case V4L2M2M:
    return &audio_callbacks_sdl;
#endif

  default:
#ifdef HAVE_PULSE
    if (audio_pulse_init(audio_device))
      return &audio_callbacks_pulse;
#endif
#ifdef HAVE_ALSA
    return &audio_callbacks_alsa;
#endif
  }

  return NULL;
}
```

The launcher/runner can then set:

```sh
SDL_AUDIODRIVER=dummy
# or via repo launcher:
MOONLIGHT_AUDIO_DRIVER=dummy
```

### Accept NV12 frames from FFmpeg v4l2m2m

The v4l2m2m submit path should accept both the future DRM PRIME path and today's practical NV12 path:

```c
while ((ret = avcodec_receive_frame(codec_ctx, f)) == 0) {
  if (!logged_first_frame) {
    LOG("submit: first frame from decoder format=%s (DRM_PRIME=%s)",
        av_get_pix_fmt_name(f->format),
        f->format == AV_PIX_FMT_DRM_PRIME ? "YES" : "no");
    logged_first_frame = true;
  }

  if (f->format == AV_PIX_FMT_DRM_PRIME || f->format == AV_PIX_FMT_NV12) {
    AVFrame *clone = av_frame_clone(f);
    if (clone) {
      pthread_mutex_lock(&disp_mtx);
      if (disp_pending)
        av_frame_free(&disp_pending);  // drop if display lags
      disp_pending = clone;
      pthread_cond_signal(&disp_cond);
      pthread_mutex_unlock(&disp_mtx);
    }
  }

  av_frame_unref(f);
}
```

`av_frame_clone()` is still important for NV12: it keeps the V4L2/MMAP plane data alive until the display thread finishes uploading it.

### Present NV12 with SDL renderer

Use SDL's renderer path for CPU-visible NV12 frames instead of custom GLES:

```c
static SDL_Window   *window = NULL;
static SDL_Renderer *sdl_renderer = NULL;
static SDL_Texture  *sdl_nv12_texture = NULL;

static int sdl_tex_w = 0;
static int sdl_tex_h = 0;
static SDL_Rect sdl_dst_rect = {0, 0, 0, 0};
```

Create the window from the selected display's usable bounds. `MOONLIGHT_DISPLAY_INDEX` provides an explicit override for dual-screen devices such as AYN Thor:

```c
int display_index = 0;
const char *display_env = getenv("MOONLIGHT_DISPLAY_INDEX");
if (display_env && *display_env) {
  char *endptr = NULL;
  long parsed = strtol(display_env, &endptr, 10);
  if (endptr && *endptr == '\0' &&
      parsed >= 0 && parsed < SDL_GetNumVideoDisplays()) {
    display_index = (int) parsed;
  } else {
    LOG("setup: ignoring invalid MOONLIGHT_DISPLAY_INDEX=%s", display_env);
  }
}

SDL_Rect bounds = {0, 0, width, height};
if (SDL_GetDisplayUsableBounds(display_index, &bounds) != 0 ||
    bounds.w <= 0 || bounds.h <= 0) {
  LOG("SDL_GetDisplayUsableBounds(%d) failed, falling back to stream size: %s",
      display_index, SDL_GetError());
  bounds.x = 0;
  bounds.y = 0;
  bounds.w = width;
  bounds.h = height;
}

window = SDL_CreateWindow("Moonlight",
                          bounds.x, bounds.y,
                          bounds.w, bounds.h,
                          SDL_WINDOW_BORDERLESS |
                          SDL_WINDOW_RESIZABLE |
                          SDL_WINDOW_HIDDEN);

if (window) {
  SDL_SetWindowPosition(window, bounds.x, bounds.y);
  SDL_SetWindowSize(window, bounds.w, bounds.h);
  SDL_ShowWindow(window);
}
```

Create the renderer on the display thread:

```c
sdl_renderer = SDL_CreateRenderer(window, -1,
                                  SDL_RENDERER_ACCELERATED |
                                  SDL_RENDERER_PRESENTVSYNC);
if (!sdl_renderer) {
  LOG("SDL_CreateRenderer failed: %s", SDL_GetError());
  disp_setup_rc = -1;
  return NULL;
}

SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, "linear");
```

Pump resize/display events and recompute the destination rectangle when the window changes:

```c
static void pump_sdl_window_events(void) {
  SDL_Event event;
  while (SDL_PollEvent(&event)) {
    if (event.type == SDL_WINDOWEVENT) {
      switch (event.window.event) {
      case SDL_WINDOWEVENT_SIZE_CHANGED:
      case SDL_WINDOWEVENT_RESIZED:
      case SDL_WINDOWEVENT_DISPLAY_CHANGED:
        LOG("window event: type=%u data=%d,%d display=%d",
            event.window.event,
            event.window.data1,
            event.window.data2,
            SDL_GetWindowDisplayIndex(window));
        gl_viewport_w = 0;
        gl_viewport_h = 0;
        break;
      default:
        break;
      }
    }
  }
}
```

Aspect-fit into the current renderer output:

```c
static void update_render_geometry(int video_w, int video_h) {
  int out_w = 0;
  int out_h = 0;

  if (sdl_renderer)
    SDL_GetRendererOutputSize(sdl_renderer, &out_w, &out_h);
  if (out_w <= 0 || out_h <= 0)
    SDL_GetWindowSize(window, &out_w, &out_h);
  if (out_w <= 0 || out_h <= 0)
    return;

  SDL_Rect dst = {0, 0, out_w, out_h};
  float video_aspect = (float) video_w / (float) video_h;
  float out_aspect = (float) out_w / (float) out_h;

  if (out_aspect > video_aspect) {
    dst.w = (int) ((float) out_h * video_aspect + 0.5f);
    dst.x = (out_w - dst.w) / 2;
  } else if (out_aspect < video_aspect) {
    dst.h = (int) ((float) out_w / video_aspect + 0.5f);
    dst.y = (out_h - dst.h) / 2;
  }

  sdl_dst_rect = dst;
}
```

Upload and present NV12 through SDL:

```c
static void draw_frame_nv12(AVFrame *frame) {
  if (!sdl_renderer)
    return;

  if (!sdl_nv12_texture ||
      sdl_tex_w != frame->width ||
      sdl_tex_h != frame->height) {
    if (sdl_nv12_texture)
      SDL_DestroyTexture(sdl_nv12_texture);

    sdl_nv12_texture = SDL_CreateTexture(sdl_renderer,
                                         SDL_PIXELFORMAT_NV12,
                                         SDL_TEXTUREACCESS_STREAMING,
                                         frame->width,
                                         frame->height);
    if (!sdl_nv12_texture) {
      LOG("SDL_CreateTexture(NV12 %dx%d) failed: %s",
          frame->width, frame->height, SDL_GetError());
      return;
    }

    sdl_tex_w = frame->width;
    sdl_tex_h = frame->height;
  }

  if (SDL_UpdateNVTexture(sdl_nv12_texture, NULL,
                          frame->data[0], frame->linesize[0],
                          frame->data[1], frame->linesize[1]) != 0) {
    LOG("SDL_UpdateNVTexture failed: %s", SDL_GetError());
    return;
  }

  SDL_SetRenderDrawColor(sdl_renderer, 0, 0, 0, 255);
  SDL_RenderClear(sdl_renderer);
  SDL_RenderCopy(sdl_renderer, sdl_nv12_texture, NULL, &sdl_dst_rect);
  SDL_RenderPresent(sdl_renderer);
}
```

The first working run logged:

```text
v4l2m2m: display thread: SDL renderer output=960x540 display=0 driver=wayland
v4l2m2m: draw_frame: #1 size=1280x720 fmt=nv12 linesize=[1280,1280,0,0]
v4l2m2m: presentation(SDL): video=1280x720 output=960x540 dst=0,0 960x540 display=0
v4l2m2m: SDL renderer: created NV12 texture 1280x720
```

Live resize also worked:

```text
# 16:9 resize
presentation(SDL): video=1280x720 output=640x360 dst=0,0 640x360

# aspect-mismatched resize
presentation(SDL): video=1280x720 output=500x360 dst=0,39 500x281
```

## Why This Works

The hardware decode win comes from using `hevc_v4l2m2m`, not from the presentation API. SDL renderer presentation still receives frames decoded by the Iris VPU:

```text
[hevc_v4l2m2m @ ...] Using device /dev/video0
[hevc_v4l2m2m @ ...] driver 'iris_driver' on card 'Iris Decoder'
```

The compromise is that NV12 frames are uploaded to an SDL texture instead of imported zero-copy as a DRM PRIME EGLImage. At 720p60, NV12 upload costs roughly:

```text
1280 * 720 * 1.5 * 60 ≈ 83 MiB/s
```

That cost is small on SM8550 compared with CPU HEVC decode. The measured 30-second A/B under a moving glmark2 workload showed the practical payoff:

| Path | Decoder | Moonlight CPU | System busy | RSS | Threads | Drops |
|---|---:|---:|---:|---:|---:|---:|
| SDL baseline | FFmpeg `h264` software | 49.0% | 11.3% | 200.7 MiB | 25 | 0 |
| v4l2m2m + SDL renderer | Iris `hevc_v4l2m2m` | 12.9% | 7.2% | 218.9 MiB | 19 | 0 |

Result: roughly **74% lower Moonlight process CPU** and **3.8x less process CPU**, with no dropped frames in either run.

The comparison is not a pure same-codec renderer benchmark: the SDL baseline negotiated software H.264 while v4l2m2m negotiated hardware HEVC. It is still the relevant real-world comparison for the shipping path.

Using SDL renderer also removes the fragile custom presentation layer. SDL already handles Wayland logical coordinates, compositor resize events, monitor selection, and renderer output sizing. That is especially important for dual-screen devices like AYN Thor, where windows can open on either monitor and be resized or moved at any time.

## Prevention

- Verify the first decoded frame format when integrating FFmpeg hardware paths:

  ```c
  LOG("first frame format=%s", av_get_pix_fmt_name(frame->format));
  ```

  Do not assume a requested `AV_PIX_FMT_DRM_PRIME` is what `avcodec_receive_frame()` returns.

- Treat FFmpeg v4l2m2m DRM PRIME zero-copy as a separate project until proven on-device. On Iris/SM8550 with FFmpeg 8.0, NV12 is the practical output format.

- For CPU-visible frames, prefer SDL renderer presentation over custom GLES unless there is a specific reason to own compositor behavior. `SDL_UpdateNVTexture()` plus `SDL_RenderCopy()` keeps the hardware decode win and avoids reimplementing Wayland presentation.

- Keep live resize acceptance tests:
  - launch the stream
  - resize to a same-aspect window such as `640x360`
  - resize to an aspect-mismatched window such as `500x360`
  - verify logs show the expected destination rectangle and no crop

- Keep dual-screen readiness in the launcher/platform contract:
  - support `MOONLIGHT_DISPLAY_INDEX`
  - log `SDL_GetNumVideoDisplays()`
  - log selected display bounds
  - log display index on resize/display-change events

- Keep video-only smoke posture separate from real audio support. `SDL_AUDIODRIVER=dummy` is useful for G5a video validation, but the PipeWire/ALSA substrate still needs its own fix before shipping with real audio.

- Keep the Moonlight CLI and pairing invariants tested:
  - app name is `-app "$APP"`, not positional
  - host remains the final positional argument
  - pair and stream both use the same explicit keydir, usually `/storage/.cache/moonlight`

## Related Issues

- `docs/solutions/integration-issues/moonlight-embedded-sobo-substrate-2026-05-22.md` — prerequisite substrate debugging for Sunshine pairing, CLI shape, keydir, audio cascade, and IDR/green-screen symptoms. This new doc picks up the v4l2m2m follow-up that older doc left open.
- `docs/solutions/runtime-errors/guest-moonlight-no-v4l2m2m-decoder-missing-video-passthrough-rocknix-2026-05-22.md` — prerequisite `/dev/video*` passthrough and `char-video4linux` access for the NixOS guest.
- `docs/solutions/runtime-errors/guest-pipewire-dummy-sink-missing-udev-sound-records-rocknix-2026-05-13.md` — explains the parked audio substrate and why dummy audio was used for video validation.
- `docs/solutions/best-practices/manual-steam-game-launching-rocknix-arm64-2026-05-04.md` — related Sway/SDL/Wayland launch and windowing context for ROCKNIX handhelds.
- `docs/solutions/performance-issues/rocknix-layer14-cemu-performance-audit-2026-05-09.md` — related performance A/B methodology under guest Sway and glmark2.

## Follow-up

Refresh `docs/solutions/integration-issues/moonlight-embedded-sobo-substrate-2026-05-22.md` with a short note that the v4l2m2m follow-up is now documented here. Its earlier “open questions” section is now partially resolved.