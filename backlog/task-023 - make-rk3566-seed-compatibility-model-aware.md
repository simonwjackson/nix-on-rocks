---
id: task-023
title: Make RK3566 seed compatibility model-aware
status: To Do
priority: high
labels:
  - rg353m
  - rk3566
  - sd-card-only
  - seed-compatibility
  - follow-up
created: 2026-06-04
source: se-work
context:
  cwd: .worktrees/feat/rg353m-sd-boot-profile
  branch: feat/rg353m-sd-boot-profile
  repo: nix-on-rocks
---

# Make RK3566 seed compatibility model-aware

## Why it matters

RG353M SD boot reports model `Anbernic RG353M` but compatible `anbernic,rg353p`; the flake can disambiguate by model, while the host seed gate currently matches only compatible strings. Without a model-aware seed gate, an RG353M seed either cannot match the SD-boot identity safely or must use the ambiguous RG353P compatible.

## Acceptance Criteria

- [ ] Host seed/promotion checks can validate model plus compatible identity for RK3566 devices, or document a deliberate fallback with evidence.
- [ ] RG353M SD-only seed publication does not rely on generic `rockchip,rk3566`.
- [ ] Wrong-device seeds still fail closed for SM8550 and unrelated RK3566 identities.
- [ ] Static tests cover RG353M model alias, RG353P-compatible ambiguity, and wrong-device seed rejection.

## Related

- `docs/contracts/device-identity-selection.md`
- `patches/rocknix/0006-rocknix-guest-substrate.patch`
- `patches/rocknix/0012-rk3566-guest-substrate-prerequisites.patch`
- `backlog/task-022 - produce-bootable-rg353m-sd-image-with-recovery-acceptance.md`
