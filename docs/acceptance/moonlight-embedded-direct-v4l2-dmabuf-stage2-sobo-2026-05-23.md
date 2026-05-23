# Moonlight Embedded direct V4L2 dma-buf Stage 2 acceptance on Sobo

Date: 2026-05-23  
Device: Sobo / SM8550 / Iris VPU / FD740  
Branch: `feat/moonlight-embedded-sobo-zero-copy`

## Result

**Accepted as experimental, env-gated Stage 2 research.**

The direct V4L2 path can present V4L2 CAPTURE dma-bufs through EGL/GL without SDL's NV12 texture upload when both gates are set:

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
  -> cached EGLImage(Y plane as DRM_FORMAT_R8 + linear modifier)
  -> cached EGLImage(UV plane as DRM_FORMAT_GR88 + linear modifier)
  -> cached GL_TEXTURE_2D bindings for each CAPTURE buffer
  -> explicit BT.709 NV12 shader
  -> GL draw / SDL_GL_SwapWindow
  -> Wayland
```

The default `v4l2m2m` platform is unchanged: it remains FFmpeg `hevc_v4l2m2m` / `h264_v4l2m2m` -> NV12 AVFrame -> SDL NV12 renderer.

## Critical findings

### 1. Explicit linear modifiers are required

Plain dma-buf import failed in the real SDL/Wayland GL context with `EGL_BAD_ALLOC`. Adding `DRM_FORMAT_MOD_LINEAR` made import succeed. The final path imports Y as `DRM_FORMAT_R8` and UV as `DRM_FORMAT_GR88`, both with linear modifiers.

### 2. Import coded CAPTURE height, crop visible height

The Iris decoder reports CAPTURE as `1280x736` for a visible `1280x720` stream:

```text
direct: configure capture=NV12 1280x736 stride=1280 size=1413120
```

The presenter imports `1280x736` and crops texture coordinates to `720/736` vertically.

### 3. Whole-NV12 import rendered with wrong colors

A whole-buffer `DRM_FORMAT_NV12` import rendered, but colors were visibly wrong. The accepted renderer imports the same dma-buf fd twice — Y (`DRM_FORMAT_R8`) and UV (`DRM_FORMAT_GR88`) — then uses the known-good BT.709 NV12 shader.

### 4. Cache per-CAPTURE-buffer EGLImages/textures

The first color-correct implementation created/destroyed two EGLImages every displayed frame. The optimized Stage 2 path now caches plane EGLImages and GL textures per V4L2 CAPTURE buffer index. The hot path binds cached textures, updates geometry only when needed, draws, swaps, then requeues the CAPTURE buffer.

### 5. Some attempted optimizations were rejected

- Direct display-index queue (bypassing AVFrame entirely) rendered initially but then hit repeated IDR waiting / consecutive drop behavior. Rejected.
- `MOONLIGHT_V4L2M2M_POLL_THREAD=1` raised process CPU from ~10.5% to ~15.7% with no correctness benefit. Rejected.

## Validation

Latest accepted optimized build deployed to Sobo:

```text
/nix/store/c6mk5i55k81hmsa33iaamy17apyrr8ii-moonlight-embedded-2.7.1-sm8550-v4l2m2m
```

Representative accepted run dirs:

```text
/storage/.guest/runs/20260523-032332-moonlight-direct-ab
/storage/.guest/runs/20260523-034827-moonlight-direct-ab
/storage/.guest/runs/20260523-040215-moonlight-direct-ab
```

Key log lines:

```text
v4l2m2m: setup: decoder=direct_v4l2 presenter=direct-dmabuf 1280x720
v4l2m2m: direct: configure capture=NV12 1280x736 stride=1280 size=1413120
v4l2m2m: direct-dmabuf: cached plane EGLImages index=0 count=1 import=1280x736 stride=1280 uv_offset=942080
v4l2m2m: direct-dmabuf: first cached plane EGL import succeeded index=0 fd=28 visible=1280x720 import=1280x736 cap=1280x736 stride=1280 uv_offset=942080
```

## Benchmark summary

### Before optimization

Color-correct Stage 2 before overnight optimization:

| Variant | Process CPU | System busy | RSS |
|---|---:|---:|---:|
| direct V4L2 + SDL NV12 upload | 12.7% | 6.4% | 314.7 MiB |
| direct V4L2 + dma-buf GL presentation | 11.7% | 6.2% | 312.7 MiB |

### After caching + direct-copy + quad-cache work

Short A/B, `/storage/.guest/runs/20260523-032332-moonlight-direct-ab`:

| Variant | Process CPU | System busy | RSS |
|---|---:|---:|---:|
| direct V4L2 + SDL NV12 upload | 13.3% | 6.7% | 314.2 MiB |
| direct V4L2 + cached dma-buf GL | 10.4% | 6.0% | 312.4 MiB |

Queue-depth sweep, `/storage/.guest/runs/20260523-034827-moonlight-direct-ab`:

| Variant | OUT/CAP | Process CPU | RSS | Notes |
|---|---:|---:|---:|---|
| `q32c12` | 32/12 | 9.6% | 312.6 MiB | lowest CPU in sweep |
| `q24c12` | 24/12 | 10.4% | 258.5 MiB | much lower RSS |
| `q16c12` | 16/12 | 10.8% | 204.5 MiB | lower RSS, no CPU win |
| `q12c12` | 12/12 | 10.5% | 177.3 MiB | no `no free OUTPUT` in this run |
| `q16c8` | 16/8 | 10.1% | 199.0 MiB | good RSS/CPU compromise |

Repeated accepted direct-dma-buf samples, `/storage/.guest/runs/20260523-040215-moonlight-direct-ab`:

| Rep | Process CPU | System busy | RSS | Signals |
|---:|---:|---:|---:|---|
| 1 | 9.8% | 6.1% | 312.4 MiB | green |
| 2 | 11.3% | 6.5% | 312.5 MiB | green |
| 3 | 10.4% | 6.2% | 312.6 MiB | rendered; startup IDR waits |

Interpretation: the accepted optimized Stage 2 path now sits around **~10–11% process CPU** in short repeated runs, with a best observed 9.6% and a median around 10.4%. This is a real improvement over the pre-optimization 11.7% color-correct Stage 2 number and a larger improvement over direct V4L2 + SDL upload, but it is not near 0% and remains benchmark-noisy.

## Runtime knobs added

Queue depth can now be swept without rebuilding, bounded by compile-time maxima:

```sh
MOONLIGHT_V4L2M2M_OUT_BUFS=32  # valid 2..32, default 32
MOONLIGHT_V4L2M2M_CAP_BUFS=12  # valid 2..12, default 12
```

Defaults remain 32/12 because that was the lowest-CPU candidate in the sweep. Lower values are useful when RSS matters more than absolute CPU.

## Caveats

- The direct V4L2 decoder remains submit-thread-driven. A poll thread was tested and rejected because it increased CPU.
- RSS remains much higher than the FFmpeg wrapper path, mostly due V4L2 queue ownership and cached per-buffer EGL/GL state.
- Audio is still parked behind `SDL_AUDIODRIVER=dummy` for these video-focused runs.
- The optimized path is deliberately env-gated and should not replace the default FFmpeg-wrapper + SDL NV12 implementation until it has longer stability testing, resize/move testing, and cleaner startup/IDR behavior.

## Decision

Keep Stage 2 in-tree behind `MOONLIGHT_V4L2M2M_DIRECT=1 MOONLIGHT_V4L2M2M_DMABUF=1` as validated zero-copy presentation research. Do **not** make it the default yet.
