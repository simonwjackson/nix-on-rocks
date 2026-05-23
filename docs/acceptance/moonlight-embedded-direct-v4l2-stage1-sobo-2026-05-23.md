# Moonlight Embedded direct V4L2 Stage 1 acceptance on Sobo

Date: 2026-05-23  
Device: Sobo / SM8550 / Iris VPU  
Branch: `feat/moonlight-embedded-sobo-zero-copy`

## Result

**Accepted as an experimental, env-gated Plan C Stage 1 milestone.**

`MOONLIGHT_V4L2M2M_DIRECT=1` now bypasses FFmpeg's `v4l2_m2m` wrapper and owns the stateful `/dev/video0` decoder directly while still presenting through the proven SDL NV12 renderer:

```text
Sunshine HEVC stream
  -> Moonlight decode units
  -> direct V4L2 OUTPUT queue
  -> iris VPU
  -> V4L2 CAPTURE NV12 buffers
  -> AVFrame wrapper
  -> SDL_UpdateNVTexture()
  -> SDL renderer / Wayland
```

This is **not** true presentation zero-copy yet: SDL still uploads NV12 into its renderer texture. It does prove direct V4L2 decode ownership and CAPTURE dma-buf export (`VIDIOC_EXPBUF`) for a later EGL/Wayland import stage.

## Implementation notes

The direct path is guarded by:

```sh
MOONLIGHT_V4L2M2M_DIRECT=1
```

Default `-platform v4l2m2m` remains the accepted shipping path:

```text
FFmpeg hevc_v4l2m2m / h264_v4l2m2m -> NV12 AVFrame -> SDL NV12 renderer
```

The direct stateful decoder lifecycle now follows the required ordering:

1. open `/dev/video0` and configure compressed OUTPUT (`HEVC` / `H264`);
2. allocate and stream-on OUTPUT buffers;
3. queue Moonlight decode-unit payloads;
4. wait for `V4L2_EVENT_SOURCE_CHANGE`;
5. `G_FMT`/allocate/export/queue/stream-on CAPTURE buffers;
6. dequeue NV12 CAPTURE frames and wrap them as `AVFrame`s for the existing SDL renderer;
7. requeue CAPTURE buffers from the `AVBufferRef` free callback after presentation releases the frame.

The earlier green-screen/failure mode came from configuring CAPTURE too early. The failing signature was:

```text
v4l2m2m: direct: DQBUF CAPTURE errno=32 (Broken pipe)
v4l2m2m: direct: no free OUTPUT buffer
```

After the source-change fix, direct decode produced frames and exported dma-bufs:

```text
v4l2m2m: direct: event type=0x5 changes=0x1
v4l2m2m: direct: configure capture=NV12 1280x736 stride=1280 size=1413120
v4l2m2m: direct: capture configured cap_bufs=12 exported_dma_bufs=yes
v4l2m2m: direct: first capture frame index=0 visible=1280x720 cap=1280x736 stride=1280 bytesused=1413120 uv_offset=942080 dma_fd=27
v4l2m2m: presentation(SDL): video=1280x720 output=960x540 dst=0,0 960x540 display=0
```

## Validation

Built on Fuji and copied to Sobo:

```text
/nix/store/mhjs93a45dhvadyg67ijpsqhx18hv0wp-moonlight-embedded-2.7.1-sm8550-v4l2m2m
```

Cold-start A/B run:

```text
/storage/.guest/runs/20260523-023123-bench-cold-direct-wrapper
```

Command shape for the direct run:

```sh
XDG_RUNTIME_DIR=/run/user/0 \
WAYLAND_DISPLAY=wayland-1 \
SDL_VIDEODRIVER=wayland \
SDL_AUDIODRIVER=dummy \
MOONLIGHT_V4L2M2M_DIRECT=1 \
moonlight -verbose stream \
  -platform v4l2m2m \
  -keydir /storage/.cache/moonlight \
  -mapping /nix/store/.../share/moonlight/gamecontrollerdb.txt \
  -app "Desktop (Sway)" \
  192.168.1.117
```

### Cold-start benchmark

30 seconds sampled after first SDL presentation:

| Variant | Process CPU | System busy | RSS | Notes |
|---|---:|---:|---:|---|
| direct V4L2 (`MOONLIGHT_V4L2M2M_DIRECT=1`) | 12.7% | 6.0% | 314.5 MiB | no `Waiting for IDR`, no network drops, screenshot captured |
| FFmpeg `v4l2m2m` wrapper | 13.0% | 6.2% | 218.9 MiB | 120 `Waiting for IDR` lines before first decoded frame, no network drops, screenshot captured |

The CPU result is effectively tied with the wrapper path. Direct V4L2 uses more RSS in this prototype because it owns a larger OUTPUT queue and explicit CAPTURE MMAP/export state.

### Signal counts

From `/storage/.guest/runs/20260523-023123-bench-cold-direct-wrapper`:

| Variant | `Network dropped` | `Waiting for IDR` | `Unrecoverable` | `no free OUTPUT` | first video | presentations |
|---|---:|---:|---:|---:|---:|---:|
| direct | 0 | 0 | 0 | 0 | 1 | 2 |
| wrapper | 0 | 120 | 0 | 0 | 1 | 2 |

The presentation count is not a frame count; the platform logs `presentation(SDL)` only on first render and geometry changes.

## Caveats / next stage

- This is still **decode-direct + SDL-upload presentation**, not full dma-buf/EGL/Wayland zero-copy.
- CAPTURE `VIDIOC_EXPBUF` succeeds, but prior EGL import probes failed or were inconclusive. A true zero-copy Stage 2 needs a separate EGL/Wayland import and buffer-lifetime design.
- The direct path is submit-thread-driven. It is acceptable for a spike, but a production direct decoder should use a dedicated V4L2 poll/dequeue thread for OUTPUT/CAPTURE events and clearer backpressure.
- Real audio remains parked behind `SDL_AUDIODRIVER=dummy` / `MOONLIGHT_AUDIO_GATE=0`; PipeWire repair is still separate U6/G5b work.

## Decision

Keep the FFmpeg `v4l2m2m` wrapper path as the default shipping implementation. Keep direct V4L2 Stage 1 behind `MOONLIGHT_V4L2M2M_DIRECT=1` as validated research scaffolding for a future zero-copy Stage 2.
