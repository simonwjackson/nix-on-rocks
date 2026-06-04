---
id: task-022
title: Produce bootable RG353M SD image with recovery acceptance
status: To Do
priority: high
labels:
  - rg353m
  - rk3566
  - after-device
  - image-build
  - hardware-smoke
  - recovery
  - acceptance
  - sd-card-only
created: 2026-06-04
source: user
---

# Produce bootable RG353M SD image with recovery acceptance

## Why it matters

The integration is not real until the RK3566 host and NixOS guest boot together from a removable SD image on the actual device, and a safe recovery path exists for failed guest updates. The product target for first bring-up is SD-card-only: Android/eMMC stays intact and usable as fallback.

## Acceptance Criteria

- [ ] A generated RK3566/RG353M removable-SD image boots on the device without destructive eMMC changes.
- [ ] The image starts the ROCKNIX host and NixOS guest substrate using the intended RG353M profile from SD-resident boot/root/state paths.
- [ ] Android/eMMC remains unmodified and can still be used as the fallback boot path after removing or not selecting the SD image.
- [ ] RK3566 has a documented recovery/no-nspawn toggle that is implemented on the SD image and does not rely on SM8550 fastboot, ABL mechanics, or eMMC boot-partition edits.
- [ ] The recovery path is verified on hardware from a normal SD boot and from a deliberately held or failed guest state.
- [ ] Display, controls, audio, WiFi/Bluetooth, guest status, recovery status, SD-card persistence behavior, and known limitations are recorded for the image.
- [ ] Artifact verification output and hardware boot evidence are linked from an acceptance document.
- [ ] Existing SM8550 recovery behavior remains unchanged.

## Related

- `.github/workflows/`
- `scripts/`
- `docs/acceptance/`
- `docs/brainstorms/evidence/`
- `guest/profiles/devices/rg353m.nix`
- `patches/rocknix/0006-rocknix-guest-substrate.patch`
- `guest/modules/`
- `scripts/verify-rk3566-contract`

## Notes

Logical work group: integrated boot image plus safe recovery acceptance. Consolidates task-015 and task-016. If first SD boot is unstable, split recovery back out during promotion. Do not expand this slice into eMMC install support without a separate explicit approval.
