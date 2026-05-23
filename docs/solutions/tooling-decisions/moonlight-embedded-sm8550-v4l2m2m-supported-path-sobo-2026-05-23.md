---
title: "Moonlight Embedded SM8550 ships v4l2m2m while direct V4L2 remains research"
date: 2026-05-23
category: tooling-decisions
module: moonlight-embedded-sm8550
problem_type: tooling_decision
component: tooling
severity: medium
applies_when:
  - "Choosing the supported Moonlight Embedded launch path on Sobo / SM8550"
  - "Comparing FFmpeg v4l2m2m, direct V4L2, and direct dma-buf GL presentation"
  - "Deciding whether lower CPU justifies experimental decoder/presenter complexity"
related_components:
  - moonlight-embedded
  - sm8550
  - sobo
  - ffmpeg-v4l2m2m
  - iris-vpu
  - sdl
  - dma-buf
  - sunshine
tags:
  - moonlight-embedded
  - sm8550
  - sobo
  - v4l2m2m
  - iris-vpu
  - sdl-nv12
  - dma-buf
  - tooling-decision
---

# Moonlight Embedded SM8550 ships v4l2m2m while direct V4L2 remains research

## Context

The Moonlight Embedded SM8550 work produced three viable-looking paths on Sobo:

1. **Default FFmpeg v4l2m2m + SDL NV12**

   ```text
   Sunshine stream
     -> FFmpeg hevc_v4l2m2m / h264_v4l2m2m
     -> Iris VPU hardware decode
     -> CPU-visible NV12 AVFrame
     -> SDL_UpdateNVTexture()
     -> SDL renderer / Wayland
   ```

2. **Direct V4L2 decoder + SDL NV12**

   ```text
   Sunshine stream
     -> Moonlight decode units
     -> direct /dev/video0 stateful V4L2 decoder
     -> Iris VPU NV12 CAPTURE buffer
     -> CPU-visible NV12 AVFrame
     -> SDL NV12 renderer
   ```

3. **Direct V4L2 decoder + dma-buf GL presentation**

   ```text
   Sunshine stream
     -> direct /dev/video0 stateful V4L2 decoder
     -> Iris VPU NV12 CAPTURE dma-buf
     -> EGLImage Y/UV plane imports
     -> GL_TEXTURE_2D + BT.709 NV12 shader
     -> Wayland
   ```

The product decision is to **ship only `-platform v4l2m2m` as the supported/default path**. Keep direct V4L2 and direct dma-buf GL behind explicit research gates.

## Guidance

For user-facing Sobo Moonlight runs, launcher integration, acceptance testing, and regression testing, use:

```sh
moonlight -verbose stream \
  -platform v4l2m2m \
  -keydir /storage/.cache/moonlight \
  -mapping /nix/store/.../share/moonlight/gamecontrollerdb.txt \
  -app "Desktop (Sway)" \
  192.168.1.117
```

During video-focused validation on Sobo, keep audio parked unless explicitly testing audio:

```sh
SDL_AUDIODRIVER=dummy
```

Do **not** enable these gates in the shipping launcher:

```sh
MOONLIGHT_V4L2M2M_DIRECT=1
MOONLIGHT_V4L2M2M_DMABUF=1
```

Those gates are for research and benchmarking only.

## Why this matters

The direct dma-buf path is technically interesting and measurably faster, but the default path has the better product tradeoff today.

| Path | Status | Process CPU | RSS | Tradeoff |
|---|---|---:|---:|---|
| FFmpeg `v4l2m2m` + SDL NV12 | Ship | ~12.9% | ~219 MiB | Best stability/complexity/memory balance |
| Direct V4L2 + SDL NV12 | Research | ~12.7% | ~315 MiB | Similar CPU to default, much higher RSS |
| Direct V4L2 + cached dma-buf GL | Research | ~10-11%, best 9.6% | ~312 MiB | Lowest CPU, but higher complexity and research risk |

The direct dma-buf path saves roughly 2-3 percentage points of process CPU over the default, but costs:

- direct ownership of the stateful V4L2 decoder lifecycle
- explicit CAPTURE buffer ownership and requeueing
- EGL dma-buf import details
- per-buffer EGLImage/GL texture cache lifetime
- custom BT.709 NV12 shader and color correctness responsibility
- queue-depth/RSS tuning
- more fragile startup/IDR behavior
- more maintenance burden than FFmpeg's wrapper path

The default path is not true zero-copy, but at 720p60 the SDL NV12 upload cost is acceptable and SDL buys back important compositor behavior: resize, aspect fit, display moves, logical Wayland sizing, and normal renderer semantics.

## Direct path findings to preserve

If future work resumes direct V4L2 / dma-buf research, keep these findings:

- FFmpeg's `v4l2_m2m` wrapper reaches Iris VPU, but returns native NV12 AVFrames rather than DRM PRIME frames on this stack.
- `ffmpeg_drm` was rejected for Sobo because it selected plain `hevc`, did not engage `hevc_v4l2m2m`, and repeatedly reported `DRM_PRIME not available`.
- Direct V4L2 Stage 1 works if the stateful decoder lifecycle is respected:
  1. configure OUTPUT
  2. stream compressed packets
  3. wait for `V4L2_EVENT_SOURCE_CHANGE`
  4. configure/allocate/export/queue CAPTURE
  5. dequeue NV12 frames
- Direct V4L2 CAPTURE on Sobo used coded height `1280x736` for visible `1280x720`; import coded size and crop visible size.
- EGL import of V4L2-exported buffers required explicit `DRM_FORMAT_MOD_LINEAR`.
- Whole-buffer `DRM_FORMAT_NV12` import rendered with wrong colors. The accepted Stage 2 renderer imports the same dma-buf fd as:
  - Y plane: `DRM_FORMAT_R8`
  - UV plane: `DRM_FORMAT_GR88`
  - explicit BT.709 NV12 shader
- Cache EGLImages and GL textures per CAPTURE buffer. Per-frame import/destroy churn was avoidable.
- Queue-depth knobs exist for research sweeps:

  ```sh
  MOONLIGHT_V4L2M2M_OUT_BUFS=32  # valid 2..32, default 32
  MOONLIGHT_V4L2M2M_CAP_BUFS=12  # valid 2..12, default 12
  ```

- Smaller queues substantially lower RSS but need longer soak before becoming defaults. Short sweep examples:
  - `q32c12`: ~9.6% CPU, ~312.6 MiB RSS
  - `q24c12`: ~10.4% CPU, ~258.5 MiB RSS
  - `q16c12`: ~10.8% CPU, ~204.5 MiB RSS
  - `q12c12`: ~10.5% CPU, ~177.3 MiB RSS
  - `q16c8`: ~10.1% CPU, ~199.0 MiB RSS

## Rejected approaches

Do not reintroduce these shapes without a new design and new evidence:

### Simple V4L2 poll/dequeue thread

A `MOONLIGHT_V4L2M2M_POLL_THREAD=1` experiment raised process CPU from roughly 10.5% to roughly 15.7% in the short A/B and did not provide correctness benefit.

### Direct display-index queue

A direct-index display queue tried to bypass per-frame AVFrame/AVBuffer allocation entirely. It rendered initially, then hit repeated IDR waiting / consecutive drop behavior. The current safer handoff retains AVFrame ownership semantics for the direct path.

### Chasing literal near-zero process CPU

Even with VPU decode and dma-buf presentation, Moonlight still pays for network receive/reassembly, protocol/control work, V4L2 ioctls, GL draw/swap, input/audio threads, and scheduler overhead. Treat high-single-digit CPU as the realistic research target unless profiling proves otherwise.

## When to apply

Use **shipping `-platform v4l2m2m`** when:

- the goal is a working user-facing Sobo Moonlight path
- changing launchers or guest module defaults
- writing acceptance/regression checks
- comparing against software decode
- validating resize/aspect/display behavior
- stability matters more than the last few CPU points

Use **direct V4L2 / dma-buf gates** only when:

- explicitly benchmarking lower CPU or RSS tradeoffs
- developing direct decoder lifecycle code
- researching EGL/GL dma-buf presentation
- collecting evidence for a possible future promotion

## Examples

Shipping launcher shape:

```sh
SDL_VIDEODRIVER=wayland \
SDL_AUDIODRIVER=dummy \
moonlight -verbose stream \
  -platform v4l2m2m \
  -keydir /storage/.cache/moonlight \
  -app "Desktop (Sway)" \
  192.168.1.117
```

Research-only direct dma-buf shape:

```sh
SDL_VIDEODRIVER=wayland \
SDL_AUDIODRIVER=dummy \
MOONLIGHT_V4L2M2M_DIRECT=1 \
MOONLIGHT_V4L2M2M_DMABUF=1 \
moonlight -verbose stream \
  -platform v4l2m2m \
  -keydir /storage/.cache/moonlight \
  -app "Desktop (Sway)" \
  192.168.1.117
```

Benchmark direct variants with:

```sh
MOONLIGHT_BIN=/nix/store/.../bin/moonlight \
MOONLIGHT_DURATION_S=30 \
MOONLIGHT_REPS=3 \
guest/launchers/remote-moonlight-direct-ab.sh direct_sdl direct_dmabuf
```

## Related

- `docs/solutions/integration-issues/moonlight-embedded-v4l2m2m-nv12-sdl-renderer-sobo-2026-05-23.md` — canonical integration learning for the shipping FFmpeg v4l2m2m + SDL NV12 path.
- `docs/solutions/performance-issues/moonlight-embedded-direct-v4l2-dmabuf-cpu-optimization-sobo-2026-05-23.md` — direct V4L2 / dma-buf optimization findings.
- `docs/solutions/runtime-errors/guest-moonlight-no-v4l2m2m-decoder-missing-video-passthrough-rocknix-2026-05-22.md` — prerequisite guest V4L2 passthrough substrate.
- `docs/solutions/integration-issues/moonlight-embedded-sobo-substrate-2026-05-22.md` — pairing/keydir/audio/substrate notes.
- `docs/acceptance/moonlight-embedded-v4l2m2m-sobo-2026-05-23.md` — acceptance evidence for default hardware decode.
- `docs/acceptance/moonlight-embedded-ffmpeg-drm-planb-sobo-2026-05-23.md` — rejected `ffmpeg_drm` evidence.
- `docs/acceptance/moonlight-embedded-direct-v4l2-stage1-sobo-2026-05-23.md` — direct V4L2 Stage 1 evidence.
- `docs/acceptance/moonlight-embedded-direct-v4l2-dmabuf-stage2-sobo-2026-05-23.md` — direct dma-buf GL Stage 2 evidence.
