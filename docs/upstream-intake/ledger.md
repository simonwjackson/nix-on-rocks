# Upstream Intake Ledger

This ledger accumulates ROCKNIX upstream changes that matter to the SM8550
Nix-on-ROCK product lane. Generated run reports live under
`docs/upstream-intake/runs/`; durable decisions and unresolved rebase work stay
here until the upstream pin is deliberately moved.

## Run index

- 2026-05-29: [f080b462f5 → c15de1d2d3](runs/2026-05-29-f080b462f5-to-c15de1d2d3-sm8550.md) — 159 upstream commits reviewed.

## Open rebase decisions

| Topic | First seen | Evidence | Decision needed | Status |
|---|---|---|---|---|
| SM8550 CPU/build flag scheme | 2026-05-29 | `projects/ROCKNIX/devices/SM8550/options`, `config/arch.aarch64`, `config/arch.arm` | Rebase our cgroup v2, nspawn, and minimal-host settings onto upstream's `TARGET_CPU_FLAGS` / armv9a scheme without restoring removed legacy flags. | open |
| Thor touchscreen identifiers | 2026-05-29 | `projects/ROCKNIX/devices/SM8550/linux/dts/qcom/qcs8550-ayn-thor.dts`, `projects/ROCKNIX/packages/sysutils/systemd/hwdb.d/61-thor-ft5x06.hwdb` | Choose whether the guest-facing contract remains `ft5x06-top` / `ft5x06-bottom` or moves to upstream's `top_touchscreen` / `bottom_touchscreen` labels; update guest sway config if changing. | open |
| SM8550 guest-owned InputPlumber maps | 2026-05-29 | Upstream SM8550 maps under `projects/ROCKNIX/devices/SM8550/filesystem/usr/share/inputplumber/`; guest copies under `packages/inputplumber/maps/` | Decide whether to import upstream `ds5` virtual-device and `KeyF1` hotkey changes into the guest-owned maps, or keep the current `xbox-series + mouse + keyboard` / `QuickAccess2` behavior. | open |
| Qualcomm display/GPU kernel fixes | 2026-05-29 | `projects/ROCKNIX/packages/linux/patches/7.0/0010-msm-resource-cleanup.patch`, SM8550 `0505-msm_gem-lock-before-put_iova_spaces.patch` | Validate guest sway, gamescope/Steam fallback, suspend/resume, and V4L2/DRM workloads before accepting the upstream kernel patch set. | open |

## Validation gates for a future upstream pin bump

- `scripts/apply-rocknix-patches` applies cleanly without relying on manual conflict resolution.
- `scripts/verify-sm8550-contract` passes against the patched ROCKNIX tree.
- SM8550 options still expose `SM8550_MINIMAL_HOST` and the SYSTEM budget.
- The patched host still keeps `systemd-nspawn` for SM8550 and cgroup v2 for the guest.
- Thor/Sobo device smoke verifies boot, `/flash`, `/storage`, guest start, input, touch routing, network/SSH recovery, and display/GPU paths.
