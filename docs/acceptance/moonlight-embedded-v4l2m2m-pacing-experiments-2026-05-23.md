# Moonlight Embedded v4l2m2m pacing experiments

Date: 2026-05-23
Device: Sobo guest (`root@sobo -p 2222`)
Sunshine host: `192.168.1.117`
App: `Desktop (Sway)`
Binary: `/nix/store/i9q59y0vq1a92fg2xcw80vg2gb07224h-moonlight-embedded-2.7.1-sm8550-v4l2m2m/bin/moonlight`

## Change under test

Patch `0003-add-env-gated-v4l2m2m-pacing-experiments.patch` adds two runtime-only gates:

- `MOONLIGHT_V4L2M2M_PACING=prefer-low-delay`
  - disables SDL present vsync for the v4l2m2m SDL NV12 renderer.
  - default remains `balanced` with vsync enabled.
- `MOONLIGHT_V4L2M2M_TIGHT_THRESHOLDS=1`
  - drops a decoded display frame if it waited longer than `MOONLIGHT_V4L2M2M_TIGHT_LATE_US` before presentation.
  - default threshold: `25000` microseconds.

Defaults are unchanged.

## Validation

Local/package validation:

```text
guest/scripts/static-checks.sh: pass
git diff --check: pass
nix eval --impure --expr '(import packages/moonlight-embedded/manifest.nix).version': "2.7.1-sm8550-v4l2m2m"
```

Fuji build:

```text
/nix/store/i9q59y0vq1a92fg2xcw80vg2gb07224h-moonlight-embedded-2.7.1-sm8550-v4l2m2m
```

Sobo copied/verified, binary advertises:

```text
-platform <system> ... ffmpeg_drm/v4l2m2m/x11/x11_vdpau/sdl/fake
```

## Measurement notes

The gamescope launcher path showed intermittent gamescope aborts while starting the stream:

```text
[gamescope] Error waitable: IWaitable hung up. Aborting.
launcher exit=134
```

The direct Wayland harness was used for the pacing matrix because it avoids that gamescope startup instability while still exercising the same v4l2m2m SDL NV12 renderer.

During this pass, `remote-moonlight-direct-ab.sh` was also fixed to discover a live Sway IPC socket instead of using the stale historical `/run/user/0/sway-ipc.0.263.sock` default.

## 30s smoke matrix

Evidence root:

```text
/storage/.guest/runs/20260523-121850-moonlight-direct-ab/evidence.md
```

| Variant | Rep | CPU | RSS | Max temp | Signals |
|---|---:|---:|---:|---:|---|
| default | 1 | 12.9% | 219.0 MiB | 37.0 C | `Waiting for IDR=120`, presentation observed |
| prefer-low-delay | 1 | 15.7% | 219.2 MiB | 37.0 C | no drops/IDR, presentation observed |
| prefer-low-delay + tight | 1 | 15.2% | 218.8 MiB | 37.0 C | `Waiting for IDR=120`, presentation observed |
| default | 2 | 15.5% | 219.0 MiB | 37.0 C | no drops/IDR, presentation observed |
| prefer-low-delay | 2 | 14.8% | 218.8 MiB | 37.0 C | no drops/IDR, presentation observed |
| prefer-low-delay + tight | 2 | 13.1% | 218.7 MiB | 37.0 C | no drops/IDR, presentation observed |

Renderer log confirmation:

```text
default:             pacing=balanced tight_thresholds=no  vsync=on
prefer-low-delay:    pacing=prefer-low-delay tight_thresholds=no  vsync=off
prefer-low-delay+tight: pacing=prefer-low-delay tight_thresholds=yes vsync=off
```

## Conclusion

No clear performance improvement was observed in the 30s smoke runs.

- CPU stayed in the same broad band as the established direct v4l2m2m baseline.
- RSS and thermals were unchanged.
- `prefer-low-delay` did not produce a measurable CPU win; it is only useful if a human-visible latency/smoothness check later proves it feels better.
- Tight thresholds did not show obvious harm in sane runs, but the smoke data is not enough to promote it.

Recommendation: keep the env gates as research scaffolding, keep default `balanced` behavior, and do not ship either pacing mode as default without a visual/latency-specific test.
