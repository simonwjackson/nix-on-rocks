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
created: 2026-06-04
source: user
---

# Produce bootable RG353M SD image with recovery acceptance

## Why it matters

The integration is not real until the RK3566 host and NixOS guest boot together from an SD image on the actual device, and a safe recovery path exists for failed guest updates.

## Acceptance Criteria

- [ ] A generated RK3566/RG353M SD image boots on the device without destructive eMMC changes.
- [ ] The image starts the ROCKNIX host and NixOS guest substrate using the intended RG353M profile.
- [ ] RK3566 has a documented recovery/no-nspawn toggle that does not rely on SM8550 fastboot or ABL mechanics.
- [ ] The recovery path is verified on hardware from a normal boot and from a deliberately held or failed guest state.
- [ ] Display, controls, audio, WiFi/Bluetooth, guest status, recovery status, and known limitations are recorded for the image.
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

Logical work group: integrated boot image plus safe recovery acceptance. Consolidates task-015 and task-016. If first boot is unstable, split recovery back out during promotion.
