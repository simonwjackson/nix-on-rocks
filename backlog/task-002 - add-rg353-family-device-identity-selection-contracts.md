---
id: task-002
title: Add RG353-family device identity selection contracts
status: To Do
priority: high
labels:
  - rg353m
  - rk3566
  - before-device
  - device-selection
  - tests
created: 2026-06-04
source: user
---

# Add RG353-family device identity selection contracts

## Why it matters

U-Boot may boot RG353M with an RG353P DTB, so profile selection must be tested before implementation relies on a possibly wrong first compatible string.

## Acceptance Criteria

- [ ] Tests cover direct compatible-string selection for known devices.
- [ ] Tests cover the RG353M ambiguity where model and compatible may not name the same product.
- [ ] The expected behavior is documented: select by compatible when unambiguous, and use model-aware fallback only where required by captured RG353-family behavior.
- [ ] Existing SM8550 device-profile selection remains unchanged.

## Related

- `flake.nix`
- `nix/tests/`
- `patches/rocknix/0006-rocknix-guest-substrate.patch`

## Notes

Logical work group: device identity contracts. This can be done before hardware using U-Boot source behavior, then adjusted after probe evidence.
