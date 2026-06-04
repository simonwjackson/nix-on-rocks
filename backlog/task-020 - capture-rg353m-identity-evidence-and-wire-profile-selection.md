---
id: task-020
title: Capture RG353M identity evidence and wire profile selection
status: Done
priority: high
labels:
  - rg353m
  - rk3566
  - after-device
  - evidence
  - hardware-probe
  - device-selection
  - tests
created: 2026-06-04
source: user
---

# Capture RG353M identity evidence and wire profile selection

## Why it matters

The real RG353M device-tree identity should drive guest profile selection, especially if U-Boot exposes an RG353P compatible string for the RG353M.

## Acceptance Criteria

- [x] A dated evidence document records model and all compatible strings from `/proc/device-tree`.
- [x] The evidence includes `aplay -l`, DRM nodes, input device names, sound devices, WiFi/Bluetooth devices, backlight/devfreq paths, and relevant dmesg excerpts.
- [x] The document records which OS/image was booted to collect evidence and whether eMMC was untouched.
- [x] Profile selection uses the captured RG353M model/compatible values from the evidence document.
- [x] Tests cover the real captured values and preserve existing SM8550 selection behavior.
- [x] Seed compatibility and promotion checks accept the intended RG353M identity and reject mismatched device seeds clearly.
- [x] The implementation documents whether RG353M is selected by compatible string, model fallback, or an explicit RG353-family alias rule.
- [x] Open assumptions in the RK3566 support plan are updated or linked to the captured evidence.

## Related

- `docs/brainstorms/evidence/`
- `docs/plans/`
- `guest/profiles/devices/rg353m.nix`
- `flake.nix`
- `patches/rocknix/0006-rocknix-guest-substrate.patch`
- `nix/tests/`

## Notes

Logical work group: first after-device hardware evidence plus identity wiring. Consolidates task-009 and task-010.
