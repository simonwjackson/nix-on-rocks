---
id: task-002
title: Add RG353-family device identity selection contracts
status: In Progress
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

- [x] Tests cover direct compatible-string selection for known devices.
- [x] Tests cover the RG353M ambiguity where model and compatible may not name the same product.
- [x] The expected behavior is documented: select by compatible when unambiguous, and use model-aware fallback only where required by captured RG353-family behavior.
- [x] Existing SM8550 device-profile selection remains unchanged.

## Related

- `flake.nix`
- `nix/tests/`
- `patches/rocknix/0006-rocknix-guest-substrate.patch`

## Notes

Logical work group: device identity contracts. This can be done before hardware using U-Boot source behavior, then adjusted after probe evidence.

Completed with `lib.deviceProfileKeyFromIdentity`, `lib.selectDeviceProfileFromIdentity`, fixture-backed flake-surface contracts, and `docs/contracts/device-identity-selection.md`. Verification: `nix build .#checks.x86_64-linux.flake-surface-contract --no-link --print-build-logs`; `nix flake check --no-build`.
