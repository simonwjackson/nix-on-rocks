---
id: task-025
title: Fix RG353M guest seed footprint for SD ext4 inode limits
status: To Do
priority: high
labels:
  - rg353m
  - rk3566
  - seed
  - storage
created: 2026-06-05
source: live-rg353m-bringup
---

# Fix RG353M guest seed footprint for SD ext4 inode limits

## Why it matters

The published RG353M seed archive could not extract on the 12.4GiB SD /storage because the default ext4 inode count was exhausted by high-file-count payloads that do not belong in the RK3566 seed. The live recovery booted only after manually excluding heavyweight payload subtrees and docs/man/info from extraction.

## Acceptance Criteria

- [ ] A freshly flashed RG353M SD card seeds the guest rootfs without manual tar excludes.
- [ ] Seed/archive size and inode requirements are checked before publishing or during artifact verification.
- [ ] Large non-RG353M payloads are excluded or split from the RG353M seed unless explicitly required.

## Related

- `guest-rg353m.lock`
- `product-payload-rg353m.lock`
- `patches/rocknix/0015-rk3566-rg353m-model-aware-guest-seed.patch`
