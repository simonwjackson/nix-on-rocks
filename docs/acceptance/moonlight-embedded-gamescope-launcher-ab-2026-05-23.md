# Moonlight Embedded gamescope launcher A/B validation

Date: 2026-05-23
Branch: `feat/moonlight-artemis-first-batch`
Commit under test: `02c7343`
Build host: Fuji
Device: Sobo guest (`root@sobo -p 2222`)
Sunshine host: `192.168.1.117`
App: `Desktop (Sway)`
Audio: dummy (`MOONLIGHT_AUDIO_GATE=0`, `SDL_AUDIODRIVER=dummy`)

## Purpose

Final validation pass for the real gamescope launcher path after switching gamescope from the crashing SDL backend to the Wayland backend, plus a final software-vs-hardware sanity A/B.

This is a validation pass only. No runtime defaults were changed.

## Build and deploy

Built the current branch on Fuji and deployed to Sobo with `nix copy --no-check-sigs`.

```text
/nix/store/i9q59y0vq1a92fg2xcw80vg2gb07224h-moonlight-embedded-2.7.1-sm8550-v4l2m2m
```

Sobo verification:

```text
-platform <system> ... ffmpeg_drm/v4l2m2m/x11/x11_vdpau/sdl/fake
```

Updated launcher/harness scripts were deployed to `/storage/.guest/` before testing.

## Command

Primary run:

```sh
MOONLIGHT_BIN=/nix/store/i9q59y0vq1a92fg2xcw80vg2gb07224h-moonlight-embedded-2.7.1-sm8550-v4l2m2m/bin/moonlight \
MOONLIGHT_HOST=192.168.1.117 \
MOONLIGHT_APP='Desktop (Sway)' \
MOONLIGHT_DURATION_S=180 \
MOONLIGHT_AUDIO_GATE=0 \
SDL_AUDIODRIVER=dummy \
MOONLIGHT_CAPTURE=0 \
/storage/.guest/remote-moonlight-runtime-ab.sh sdl v4l2m2m
```

Primary evidence root:

```text
/storage/.guest/runs/20260523-130343-moonlight-runtime-ab
```

A secondary 30s smoke with screenshot capture also completed without launcher crashes:

```text
/storage/.guest/runs/20260523-131018-moonlight-runtime-ab
```

The 180s run is the decision evidence below.

## Results: 180s gamescope launcher A/B

| Variant | Launcher exit | CPU | RSS | Max temp | Stream signals | Presentation |
|---|---:|---:|---:|---:|---|---|
| `sdl` software decode | 0 | 73.6% | up to 212.4 MiB | 41.4 C | `Network dropped=0`, `Waiting for IDR=120`, `Unrecoverable=0`, `Frames dropped=0`, `Received first=2` | no v4l2m2m presentation marker; stream started but software decode could not stay clean |
| `v4l2m2m` hardware decode + SDL NV12 | 0 | 15.1% | 256.4 MiB | 37.0 C | `Network dropped=0`, `Waiting for IDR=0`, `Unrecoverable=0`, `Frames dropped=0`, `Received first=2` | `presentation(SDL)=1` |

Relevant `v4l2m2m` launcher log markers:

```text
v4l2m2m: setup: pacing=balanced tight_thresholds=no tight_late_us=25000
v4l2m2m: display thread: SDL renderer output=1920x1080 display=0 driver=x11 vsync=on
v4l2m2m: setup: decoder=hevc_v4l2m2m presenter=sdl-nv12 1920x1080
v4l2m2m: presentation(SDL): video=1920x1080 output=1920x1080 dst=0,0 1920x1080 display=0
Received first video packet after 0 ms
Received first audio packet after 100 ms
launcher exit=0
```

Relevant `sdl` launcher log markers:

```text
Starting video stream...Using FFmpeg decoder: h264
Received first video packet after 0 ms
Received first audio packet after 400 ms
Waiting for IDR frame ...
Reached consecutive drop limit
IDR frame request sent
launcher exit=0
```

## Launcher reliability

The historical launcher failure mode was gamescope `--backend sdl` exiting with `139`. A later transient startup failure was gamescope exiting with `134` / `waitable: IWaitable hung up`.

This validation did **not** reproduce either launcher crash:

- `sdl` launcher exit: `0`
- `v4l2m2m` launcher exit: `0`
- no `139`
- no `134`

The real launcher path is now reliable enough for the shipping `v4l2m2m` path.

## Software-vs-hardware conclusion

The final launcher-path A/B restates the core value proposition:

- `sdl` software decode consumed much higher CPU: **73.6%** process CPU, reached **41.4 C**, and showed sustained `Waiting for IDR` churn during the 180s run.
- `v4l2m2m` hardware decode + SDL NV12 presentation consumed **15.1%** process CPU, stayed at **37.0 C**, reached presentation, and had clean stream signals.

That is roughly a **4.9x process-CPU reduction** for the hardware path in the real launcher environment.

## Decision

Ready for review from the launcher/A-B validation perspective:

- Keep default shipping path as `v4l2m2m` hardware decode + SDL NV12 presentation.
- Keep pacing knobs research-only; this pass used default balanced pacing and validated it through the real launcher.
- Do not promote `sdl` software decode beyond fallback status; it starts through the launcher but is not a viable performance baseline for sustained 1080p streaming on Sobo.
- No launcher-path blocker remains from the earlier `139` / `134` failures.
