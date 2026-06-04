---
id: task-008
title: Add RK3566 SD image build lane and artifact checks
status: To Do
priority: medium
labels:
  - rk3566
  - before-device
  - ci
  - image-build
  - artifacts
created: 2026-06-04
source: user
---

# Add RK3566 SD image build lane and artifact checks

## Why it matters

RG353M boots from a U-Boot/extlinux SD image, so SM8550 fastboot artifact assumptions need a separate CI lane before hardware smoke testing.

## Acceptance Criteria

- [ ] A RK3566 build workflow or script can be dispatched with `DEVICE=RK3566` without affecting SM8550 workflows.
- [ ] Artifact verification checks for SD-image expectations: U-Boot placement boundary, FAT `ROCKNIX` partition, extlinux/DTB presence, and ext4 `STORAGE` label.
- [ ] SM8550 artifact verification remains separate and continues to check its fastboot/ABL-specific contract.
- [ ] The workflow clearly marks hardware boot as unverified until post-arrival acceptance evidence exists.

## Related

- `.github/workflows/`
- `scripts/`
- `work/rocknix/scripts/mkimage`
- `work/rocknix/projects/ROCKNIX/config.xml`
- `scripts/verify-sm8550-contract`

## Notes

Logical work group: build artifact lane. This is the last major before-device PR because it composes earlier contracts and host changes.
