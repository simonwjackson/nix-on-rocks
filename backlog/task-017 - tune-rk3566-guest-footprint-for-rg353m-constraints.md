---
id: task-017
title: Tune RK3566 guest footprint for RG353M constraints
status: To Do
priority: medium
labels:
  - rg353m
  - rk3566
  - after-device
  - performance
  - guest-profile
  - sd-card-only
created: 2026-06-04
source: user
---

# Tune RK3566 guest footprint for RG353M constraints

## Why it matters

RG353M has much less CPU, GPU, and RAM headroom than SM8550 devices, so the guest should avoid heavyweight defaults that make the product unusable. Tuning must fit the removable-SD product target rather than relying on eMMC installation or internal-storage swap/state.

## Acceptance Criteria

- [ ] The RG353M guest profile disables or defers heavyweight SM8550-oriented features that are not viable on RK3566 by default.
- [ ] Memory, service footprint, and SD-card storage pressure are measured after SD boot and recorded in an acceptance or performance note.
- [ ] Graphics defaults prefer Panfrost/OpenGL or GLES paths unless hardware evidence from the SD-booted lane proves a better Mali strategy.
- [ ] Defaults avoid depending on eMMC swap, eMMC state directories, or Android replacement.
- [ ] Deferred high-end features such as Cemu, Steam, Moonlight hardware decode, or proprietary libmali Vulkan are documented as separate follow-up work if still desired.

## Related

- `guest/profiles/devices/rg353m.nix`
- `guest/modules/display.nix`
- `guest/modules/moonlight.nix`
- `packages/cemu/`
- `devices/rk3566/`
- `docs/acceptance/`

## Notes

Logical work group: product tuning after SD boot works. This should not block the first bootable proof and should preserve Android/eMMC as a fallback.
