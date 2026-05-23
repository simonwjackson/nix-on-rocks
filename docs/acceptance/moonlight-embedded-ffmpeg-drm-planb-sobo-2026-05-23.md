# moonlight-embedded `ffmpeg_drm` Plan B probe on Sobo — 2026-05-23

## Result

Rejected as a better zero-copy path for Sobo/SM8550.

The vendored `ffmpeg_drm` backend from upstream PR #932 reaches DRM/KMS setup, but it does not use the iris VPU stateful M2M decoder and does not receive DRM PRIME frames. It therefore does not solve the zero-copy goal we deferred from the `v4l2m2m` SDL NV12 path.

## Probe

Run dir:

```text
/storage/.guest/runs/20260523-020254-ffmpeg-drm-planb-sway
```

Command shape:

```sh
moonlight -verbose stream \
  -platform ffmpeg_drm \
  -keydir /storage/.cache/moonlight \
  -mapping /nix/store/.../share/moonlight/gamecontrollerdb.txt \
  -app "Desktop (Sway)" \
  192.168.1.117
```

## Evidence

Relevant log lines:

```text
Platform FFmpeg V4L2 + DRM PRIME
Starting video stream...ffmpeg_drm: crtc=105 plane=51 display=1080x1920
ffmpeg_drm: decoder=hevc display=1080x1920
done
Starting audio stream...Alsa error code -22
Audio stream start failed: -1
Stopping video stream...No video traffic was ever received from the host!
Received first video packet after 0 ms
ffmpeg_drm: DRM_PRIME not available
[hevc @ ...] Invalid setup for format vaapi: does not match the type of the provided device context.
ffmpeg_drm: DRM_PRIME not available
[hevc @ ...] Invalid setup for format vdpau: does not match the type of the provided device context.
ffmpeg_drm: DRM_PRIME not available
[hevc @ ...] Invalid setup for format cuda: does not match the type of the provided device context.
ffmpeg_drm: DRM_PRIME not available
[hevc @ ...] Invalid setup for format vulkan: does not match the type of the provided device context.
ffmpeg_drm: DRM_PRIME not available
```

## Interpretation

- `ffmpeg_drm` can inspect KMS objects (`crtc=105 plane=51 display=1080x1920`), even while the Sway session is active.
- It selects plain `hevc`, not `hevc_v4l2m2m`, so it does not engage the iris VPU stateful M2M decoder.
- It never obtains `AV_PIX_FMT_DRM_PRIME`; the backend repeatedly reports `DRM_PRIME not available`.
- It also uses the default non-SDL audio path and hits the same Sobo audio-substrate failure (`Alsa error code -22`), but that is secondary. The decoder/pixel-format behavior is already enough to reject it as the zero-copy answer.

## Decision

Do not pursue `ffmpeg_drm` as the Sobo shipping path.

Keep the accepted practical path:

```text
hevc_v4l2m2m / iris VPU -> NV12 AVFrame -> SDL_UpdateNVTexture -> SDL renderer
```

If true zero-copy is still desired later, the likely path is a direct V4L2 implementation that owns the capture queue and calls `VIDIOC_EXPBUF`, then imports those dma-bufs into EGL/GL or hands them to a compositor-aware renderer. That is a larger Plan C, not a small patch to PR #932.
