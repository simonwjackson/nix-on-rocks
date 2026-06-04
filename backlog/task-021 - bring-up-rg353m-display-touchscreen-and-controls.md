---
id: task-021
title: Bring up RG353M display touchscreen and controls
status: To Do
priority: high
labels:
  - rg353m
  - rk3566
  - after-device
  - display
  - touchscreen
  - input
  - controls
  - guest-profile
  - sd-card-only
created: 2026-06-04
source: user
---

# Bring up RG353M display touchscreen and controls

## Why it matters

A visible compositor and working handheld controls are the core proof that the RK3566 guest profile is viable on the RG353M. The proof should come from the removable-SD boot lane, with Android/eMMC left untouched.

## Acceptance Criteria

- [ ] RG353M guest display config uses DRM connector/output name, orientation, and resolution captured from an SD-booted Linux/ROCKNIX image.
- [ ] Touchscreen mapping is configured only if the SD-booted hardware exposes one and is verified with the real input device.
- [ ] Hardcoded AYN input-device names are parameterized or bypassed for RK3566.
- [ ] RG353M button, d-pad, shoulder, trigger, analog stick, power, and volume event names are derived from captured SD-boot evidence.
- [ ] The guest exposes controls through the intended input path, with InputPlumber used only if it is actually required for RG353M.
- [ ] Hardware smoke results show the chosen guest UI appears correctly on the panel and controls generate expected events inside the guest while booted from removable SD.
- [ ] No display/input acceptance step requires replacing Android, modifying eMMC, or storing state on internal storage.
- [ ] SM8550 display and input configuration remain unchanged.

## Related

- `guest/modules/display.nix`
- `guest/modules/input.nix`
- `guest/modules/lid.nix`
- `packages/inputplumber/maps/`
- `guest/profiles/devices/rg353m.nix`
- `docs/brainstorms/evidence/`
- `docs/acceptance/`

## Notes

Logical work group: display/touch/control bring-up. Consolidates task-011 and task-012. Can still be split during promotion if captured SD-boot input evidence is unexpectedly complex.
