# Moonlight Embedded v4l2m2m Wi-Fi pacing comparison

Date: 2026-05-23
Branch: `feat/moonlight-artemis-first-batch`
Commit: `204f0f3`
Build host: Fuji
Device: Sobo guest (`root@sobo -p 2222`)
Sunshine host: `192.168.1.117`
App: `Desktop (Sway)`
Audio: dummy (`SDL_AUDIODRIVER=dummy`, `MOONLIGHT_AUDIO_GATE=0`)

## Build and deploy

Built current branch on Fuji and deployed to Sobo with `nix copy --no-check-sigs`.

```text
/nix/store/i9q59y0vq1a92fg2xcw80vg2gb07224h-moonlight-embedded-2.7.1-sm8550-v4l2m2m
```

Sobo verification:

```text
-platform <system> ... ffmpeg_drm/v4l2m2m/x11/x11_vdpau/sdl/fake
```

## Wi-Fi state

Traffic to Sunshine used Wi-Fi:

```text
192.168.1.117 dev wlan0 src 192.168.1.103
```

Link during the run:

```text
SSID: vrackie
freq: 5500 MHz, channel 100, 80 MHz
signal: -51 to -53 dBm
rx bitrate: 960.7 MBit/s 80MHz HE-MCS 9 HE-NSS 2
tx bitrate: 648.5 MBit/s 80MHz HE-MCS 6 HE-NSS 2
```

Remote evidence root:

```text
/storage/.guest/runs/wifi-pacing-20260523-123312
```

Per-variant harness roots:

```text
default:  /storage/.guest/runs/20260523-123312-moonlight-direct-ab
lowdelay: /storage/.guest/runs/20260523-123631-moonlight-direct-ab
combo:    /storage/.guest/runs/20260523-123950-moonlight-direct-ab
```

Each variant was run for 180 seconds after first presentation using the existing direct telemetry harness.

## Results

| Variant | Env | CPU | RSS | Max temp | Moonlight stream signals | ICMP Wi-Fi probe to host |
|---|---|---:|---:|---:|---|---|
| default | none | 11.0% | 220.0 MiB | 37.8 C | `Network dropped=0`, `Waiting for IDR=0`, `Unrecoverable=0`, `Frames dropped=0`, `presentation=1` | 954/954 received, 0.00% loss, avg 5.07 ms, p95 6.50 ms, p99 14.10 ms, max 220 ms, >20 ms spikes: 6 |
| lowdelay | `MOONLIGHT_V4L2M2M_PACING=prefer-low-delay` | 13.9% | 220.1 MiB | 37.8 C | `Network dropped=0`, `Waiting for IDR=0`, `Unrecoverable=0`, `Frames dropped=0`, `presentation=1` | 952/953 received, 0.10% loss, avg 4.72 ms, p95 6.07 ms, p99 7.85 ms, max 113 ms, >20 ms spikes: 3 |
| combo | `MOONLIGHT_V4L2M2M_PACING=prefer-low-delay MOONLIGHT_V4L2M2M_TIGHT_THRESHOLDS=1` | 13.9% | 220.3 MiB | 37.0 C | `Network dropped=0`, `Waiting for IDR=0`, `Unrecoverable=0`, `Frames dropped=0`, `presentation=1` | 956/958 received, 0.21% loss, avg 4.80 ms, p95 5.90 ms, p99 7.63 ms, max 127 ms, >20 ms spikes: 2 |

All variants reached presentation:

```text
v4l2m2m: setup: decoder=hevc_v4l2m2m presenter=sdl-nv12 1280x720
Received first video packet after 0 ms
v4l2m2m: presentation(SDL): video=1280x720 output=960x540 dst=0,0 960x540 display=0
Received first audio packet after 300 ms
```

Runtime pacing confirmation:

```text
default:  pacing=balanced, vsync=on
lowdelay: pacing=prefer-low-delay, vsync=off
combo:    pacing=prefer-low-delay, tight_thresholds=yes, vsync=off
```

## Subjective smoothness

Not directly assessed in this run. The test was executed over SSH with telemetry and ICMP probes; no in-person visual inspection was captured. Presentation stayed stable according to logs.

## Interpretation

Wi-Fi did introduce occasional ICMP latency spikes and tiny probe loss on the pacing variants, but Moonlight itself did not report stream-quality degradation in any variant:

- No `Network dropped` events.
- No frame drops reported in logs.
- No `Waiting for IDR` churn.
- No `Unrecoverable` events.
- Presentation was observed for all variants.
- CPU/RSS/temp remained in the same expected band.

The low-delay variants did not provide enough evidence to justify changing defaults. Their ICMP p95/p99 looked slightly lower in this single run, but CPU was higher and the packet-loss differences are too small/noisy to treat as a pacing win. More importantly, Moonlight stream signals were already clean on default v4l2m2m over Wi-Fi.

## Decision

Wi-Fi does **not** change the previous conclusion:

- Keep default `v4l2m2m` as the shipping path.
- Keep `MOONLIGHT_V4L2M2M_PACING=prefer-low-delay` and tight-threshold mode as research-only env gates.
- Do not enable pacing knobs by default without visual smoothness evidence or a dedicated latency metric that shows a repeatable improvement.
