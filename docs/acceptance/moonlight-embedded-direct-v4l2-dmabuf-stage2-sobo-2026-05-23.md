# Moonlight Embedded direct V4L2 dma-buf Stage 2 acceptance on Sobo

Date: 2026-05-23  
Device: Sobo / SM8550 / Iris VPU / FD740  
Branch: `feat/moonlight-embedded-sobo-zero-copy`

## Result

**Accepted as experimental, env-gated Stage 2 research.**

The direct V4L2 path can now present V4L2 CAPTURE dma-bufs through EGL/GL without SDL's NV12 texture upload when both gates are set:

```sh
MOONLIGHT_V4L2M2M_DIRECT=1
MOONLIGHT_V4L2M2M_DMABUF=1
```

Pipeline proven:

```text
Sunshine HEVC stream
  -> Moonlight decode units
  -> direct /dev/video0 stateful V4L2 decoder
  -> Iris VPU writes NV12 CAPTURE buffer
  -> VIDIOC_EXPBUF dma-buf fd
  -> eglCreateImageKHR(EGL_LINUX_DMA_BUF_EXT, DRM_FORMAT_NV12, DRM_FORMAT_MOD_LINEAR)
  -> glEGLImageTargetTexture2DOES(GL_TEXTURE_2D)
  -> GL draw / SDL_GL_SwapWindow
  -> Wayland
```

The default `v4l2m2m` platform is unchanged: it remains FFmpeg `hevc_v4l2m2m` / `h264_v4l2m2m` -> NV12 AVFrame -> SDL NV12 renderer.

## Critical findings

### 1. `DRM_FORMAT_MOD_LINEAR` is required

Plain dma-buf import failed even inside the real SDL/Wayland GL context:

```text
direct-dmabuf: import[plain+hints] failed err=0x3003 ... mod=none hints=yes
direct-dmabuf: import[plain] failed err=0x3003 ... mod=none hints=no
```

Adding explicit linear modifiers made import succeed:

```text
direct-dmabuf: import[linear+hints] succeeded import=1280x720 mod=linear hints=yes
direct-dmabuf: first EGL import succeeded index=0 fd=24 visible=1280x720 cap=1280x736 stride=1280
```

The cleaned implementation now imports with `DRM_FORMAT_MOD_LINEAR` directly.

### 2. Import coded CAPTURE height, crop visible height

The Iris decoder reports CAPTURE as `1280x736` for a visible `1280x720` stream:

```text
direct: configure capture=NV12 1280x736 stride=1280 size=1413120
```

The working presenter imports `1280x736` and crops texture coordinates to `720/736` vertically. Importing as `1280x720` with a UV offset derived from 736 lines is layout-inconsistent.

### 3. `GL_TEXTURE_EXTERNAL_OES` was the wrong target in this SDL context

SDL created a desktop GL compatibility context on Sobo:

```text
gl_init: GL_VERSION=4.6 (Compatibility Profile) Mesa 25.2.6 GL_RENDERER=FD740 dmabuf_target=2D
```

Binding the imported EGLImage to `GL_TEXTURE_EXTERNAL_OES` produced `GL_INVALID_ENUM (0x0500)` and a black window. Binding to `GL_TEXTURE_2D` with a plain `sampler2D` shader renders correctly.

## Validation

Final build deployed to Sobo:

```text
/nix/store/8zb532jab91m0s7gs0fzx5f797r3rnm8-moonlight-embedded-2.7.1-sm8550-v4l2m2m
```

Final smoke run:

```text
/storage/.guest/runs/20260523-025425-v4l2m2m-direct-dmabuf-final-smoke
```

Key log lines:

```text
v4l2m2m: setup: decoder=direct_v4l2 presenter=direct-dmabuf 1280x720
v4l2m2m: direct: configure capture=NV12 1280x736 stride=1280 size=1413120
v4l2m2m: direct: capture configured cap_bufs=12 exported_dma_bufs=yes
v4l2m2m: presentation(direct-dmabuf): video=1280x720 output=960x540 dst=0,0 960x540 display=0
v4l2m2m: direct-dmabuf: first EGL import succeeded index=0 fd=28 visible=1280x720 import=1280x736 cap=1280x736 stride=1280
```

Signal counts from final smoke:

| Signal | Count |
|---|---:|
| first EGL import succeeded | 1 |
| Network dropped | 0 |
| Unrecoverable | 0 |
| no free OUTPUT | 0 |
| glEGLImageTargetTexture errors | 0 |
| glDrawArrays errors | 0 |
| presentation(direct-dmabuf) | 2 |

`Waiting for IDR` appeared before source-change in this run, then the stream recovered and rendered. It was not accompanied by network drops or unrecoverable errors.

Screenshot captured:

```text
/storage/.guest/runs/20260523-025425-v4l2m2m-direct-dmabuf-final-smoke/screenshot-final.png
```

## Benchmark

A/B run:

```text
/storage/.guest/runs/20260523-025530-bench-stage2-dmabuf
```

30 seconds sampled after first presentation:

| Variant | Process CPU | System busy | RSS | Notes |
|---|---:|---:|---:|---|
| direct V4L2 + SDL NV12 upload | 11.3% | 6.5% | 314.1 MiB | direct decoder, SDL_UpdateNVTexture presentation |
| direct V4L2 + dma-buf GL presentation | 9.9% | 7.0% | 311.9 MiB | direct decoder, EGLImage + GL_TEXTURE_2D presentation |

The Stage 2 path showed a **~1.4 percentage point process-CPU reduction** versus direct V4L2 + SDL upload in this single 30s run. Treat this as directional, not final: longer runs and thermal/power instrumentation would be needed before promoting the path from research to default.

## Caveats

- The direct V4L2 decoder remains submit-thread-driven. A production version should use a dedicated V4L2 poll/dequeue thread for OUTPUT/CAPTURE servicing and explicit backpressure.
- The direct path still owns substantial queue memory; RSS remains much higher than the FFmpeg wrapper path.
- Audio is still parked behind `SDL_AUDIODRIVER=dummy` for these video-focused runs.
- This path is deliberately env-gated and should not replace the default FFmpeg-wrapper + SDL NV12 implementation until it has longer stability testing, resize/move testing, and cleaner startup/IDR behavior.

## Decision

Keep Stage 2 in-tree behind `MOONLIGHT_V4L2M2M_DIRECT=1 MOONLIGHT_V4L2M2M_DMABUF=1` as validated zero-copy presentation research. Do **not** make it the default yet.
