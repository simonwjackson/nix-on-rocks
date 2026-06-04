---
id: task-003
title: Extract product-agnostic seams from SM8550 guest modules
status: To Do
priority: high
labels:
  - rk3566
  - before-device
  - refactor
  - guest-modules
created: 2026-06-04
source: user
---

# Extract product-agnostic seams from SM8550 guest modules

## Why it matters

The current guest module surface is SM8550-shaped; isolating shared seams first makes RK3566 additions smaller and safer for an LLM to implement.

## Acceptance Criteria

- [ ] Shared guest behavior is separated from SM8550-specific options without changing SM8550 behavior.
- [ ] SM8550-specific names, input events, audio packages, display config, and performance knobs remain under an explicit SM8550 owner.
- [ ] Tests or evaluated contracts prove existing Thor and Odin2 Portal profiles still evaluate and expose the same key settings.
- [ ] No RK3566 runtime behavior is introduced in this refactor beyond extension points.

## Related

- `guest/modules/device.nix`
- `guest/modules/audio.nix`
- `guest/modules/input.nix`
- `guest/modules/lid.nix`
- `guest/modules/display.nix`
- `guest/profiles/devices/thor.nix`
- `guest/profiles/devices/odin2portal.nix`
- `nix/tests/`

## Notes

Logical work group: product-blind guest module seam. Keep this as a behavior-preserving PR before adding RK3566 functionality.
