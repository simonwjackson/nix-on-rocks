# moonlight-embedded v4l2m2m Sobo acceptance — 2026-05-23

## Result

Accepted for the practical shipping path:

`Sunshine on aka → moonlight-embedded on Sobo → hevc_v4l2m2m/iris VPU decode → NV12 frames → SDL NV12 texture/renderer presentation`

True DRM PRIME zero-copy is **deferred**. FFmpeg 8.0's `v4l2_m2m` decoder wrapper advertises `capture=NV12/drm_prime` when asked for DRM PRIME, but on iris it still dequeues native NV12 frames. The practical cost of uploading NV12 to SDL is small enough for the current target.

## Hardware / runtime

- Client: Sobo SM8550 guest (`root@sobo:2222`)
- Host: aka (`192.168.1.117`) running Sunshine + Sway
- App: `Desktop (Sway)`
- Workload on host during benchmark: `glmark2-es2 --fullscreen --run-forever`
- Audio: parked with `SDL_AUDIODRIVER=dummy` because the Sobo PipeWire substrate is still deferred

## Evidence

### v4l2m2m renderer path

Run dir:

```text
/storage/.guest/runs/20260523-013701-v4l2m2m-sdl-renderer
```

Relevant log lines:

```text
[hevc_v4l2m2m @ ...] Using device /dev/video0
[hevc_v4l2m2m @ ...] driver 'iris_driver' on card 'Iris Decoder' in mplane mode
[hevc_v4l2m2m @ ...] requesting formats: output=HEVC/none capture=NV12/drm_prime
v4l2m2m: display thread: SDL renderer output=960x540 display=0 driver=wayland
Received first video packet after 0 ms
v4l2m2m: draw_frame: #1 size=1280x720 fmt=nv12 linesize=[1280,1280,0,0]
v4l2m2m: presentation(SDL): video=1280x720 output=960x540 dst=0,0 960x540 display=0
v4l2m2m: SDL renderer: created NV12 texture 1280x720
v4l2m2m: window event: type=5 data=960,517 display=0
v4l2m2m: presentation(SDL): video=1280x720 output=960x517 dst=20,0 919x517 display=0
Received first audio packet after 300 ms
```

### Resize / aspect-fit

Live resize was verified through Sway commands while the stream was running:

```text
swaymsg '[app_id="moonlight"] floating enable'
swaymsg '[app_id="moonlight"] fullscreen disable'
swaymsg '[app_id="moonlight"] resize set 640 360'
swaymsg '[app_id="moonlight"] resize set 500 360'
```

Relevant logs:

```text
presentation(SDL): video=1280x720 output=640x360 dst=0,0 640x360 display=0
presentation(SDL): video=1280x720 output=500x360 dst=0,39 500x281 display=0
```

Interpretation:

- 16:9 resize fills exactly.
- Aspect-mismatched resize letterboxes rather than cropping or stretching.

### CPU A/B

Run dirs:

```text
/storage/.guest/runs/20260523-014632-bench2-sdl
/storage/.guest/runs/20260523-014722-bench2-v4l2m2m
```

30s sample summary:

| Path | Decoder | Moonlight process CPU | System busy | RSS | Threads | Dropped/IDR log lines |
|---|---:|---:|---:|---:|---:|---:|
| SDL baseline | FFmpeg `h264` software | ~49.0% | ~11.3% | ~200.7 MiB | 25 | 0 |
| v4l2m2m + SDL renderer | iris `hevc_v4l2m2m` | ~12.9% | ~7.2% | ~218.9 MiB | 19 | 0 |

Interpretation:

- v4l2m2m path cut Moonlight process CPU by ~74% / ~3.8x versus the SDL software-decode baseline.
- The v4l2m2m path used ~18 MiB more RSS.
- Both runs had no `Network dropped` or `Waiting for IDR` log lines.

Caveat: this is the practical default comparison, not a same-codec microbenchmark. SDL baseline used software H.264, while v4l2m2m used hardware HEVC.

## Decisions from acceptance

- Ship the SDL NV12 presentation path as the practical Sobo/Thor-ready implementation.
- Keep `MOONLIGHT_DISPLAY_INDEX` support for dual-screen device bring-up.
- Defer true zero-copy to a separate experiment:
  - first try `ffmpeg_drm` / PR #932 behavior on Sobo,
  - then consider direct V4L2 + `VIDIOC_EXPBUF` only if the perf win justifies the maintenance surface.
