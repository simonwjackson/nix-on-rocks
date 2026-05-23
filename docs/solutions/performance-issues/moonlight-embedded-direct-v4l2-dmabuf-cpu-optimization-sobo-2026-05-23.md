# Moonlight Embedded direct V4L2 dma-buf CPU optimization on Sobo (2026-05-23)

## Context

The experimental Moonlight Embedded SM8550 path bypasses FFmpeg's `v4l2_m2m` wrapper and owns `/dev/video0` directly. Stage 2 presents V4L2 CAPTURE dma-bufs through EGL/GL instead of uploading NV12 through SDL.

The user asked how close to 0% process CPU the path could get, then requested overnight optimization. The starting color-correct Stage 2 measurement was roughly 11.7% Moonlight process CPU at 720p60.

## Findings

- Literal 0% process CPU is not realistic. Even with VPU decode and dma-buf presentation, Moonlight still pays for network receive/reassembly, protocol/control, V4L2 ioctls, GL draw/swap, input/audio threads, and scheduler overhead.
- The highest-confidence win was caching EGLImages and GL textures per V4L2 CAPTURE buffer index. Per-frame two-plane `eglCreateImageKHR` / `eglDestroyImageKHR` was avoidable.
- Whole-NV12 dma-buf import was not acceptable even though it rendered: colors were visibly wrong. The correct path imports Y as `DRM_FORMAT_R8`, UV as `DRM_FORMAT_GR88`, and runs the explicit BT.709 NV12 shader.
- Updating the GL quad/VBO every frame was unnecessary. Geometry and coded-height crop can be cached until the output size, destination rect, or coded height changes.
- Copying Moonlight decode-unit fragments directly into the selected V4L2 OUTPUT buffer removes one avoidable direct-path copy. This is a small/uncertain CPU win but simplifies the direct path.
- Queue depth is a CPU/RSS trade-off. 32 OUTPUT / 12 CAPTURE remained best CPU in the short sweep, but lowering output buffers dramatically reduced RSS.
- A dedicated poll/dequeue thread was tested and rejected: it raised process CPU from ~10.5% to ~15.7% in the short A/B, with no correctness benefit.
- Bypassing AVFrame allocation entirely for direct dma-buf display was tested and rejected: it rendered initially but then hit repeated IDR waiting / consecutive drop behavior.

## Accepted optimizations

- Cached per-CAPTURE-buffer EGLImage + GL texture state for Y and UV planes.
- Cached dma-buf presentation quad/VBO updates.
- Direct decode-unit fragment copy into V4L2 OUTPUT buffers.
- Runtime queue-depth knobs:

```sh
MOONLIGHT_V4L2M2M_OUT_BUFS=32  # valid 2..32, default 32
MOONLIGHT_V4L2M2M_CAP_BUFS=12  # valid 2..12, default 12
```

## Representative results

Best observed short queue sweep result:

```text
/storage/.guest/runs/20260523-034827-moonlight-direct-ab
q32c12: 9.6% process CPU, 312.6 MiB RSS
```

Repeated accepted direct-dma-buf samples:

```text
/storage/.guest/runs/20260523-040215-moonlight-direct-ab
rep1:  9.8% process CPU
rep2: 11.3% process CPU
rep3: 10.4% process CPU
```

Practical conclusion: after optimization, the path sits around **~10–11% process CPU** in short repeated runs, with best observed **9.6%**. The realistic near-term floor appears to be high single digits, not near-zero.

## What to do next

- Longer soak: run 5–10 minute samples with battery current/voltage and thermal capture.
- Frame pacing: add a better frame counter or presentation cadence metric; process CPU alone is not enough.
- RSS mode: if memory matters, test 16/8 or 12/12 queue settings over longer runs.
- Threading: do not reintroduce the simple poll thread shape; it increased CPU. Any future threading needs condition variables/backpressure rather than polling every 10ms.
- Architecture: if pursuing more CPU reduction, replace the direct path's per-frame AVFrame/AVBuffer allocation carefully, but the first naive index-queue attempt destabilized the stream.

## Guardrail

Keep the FFmpeg `v4l2m2m` + SDL NV12 renderer as the default shipping path. Keep direct V4L2 + dma-buf GL behind `MOONLIGHT_V4L2M2M_DIRECT=1 MOONLIGHT_V4L2M2M_DMABUF=1` until it has longer stability testing and cleaner startup behavior.
