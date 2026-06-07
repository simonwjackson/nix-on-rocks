---
id: task-026
title: Persist guest SSH authorization and SMBR product in RG353M seed
status: To Do
priority: high
labels:
  - rg353m
  - ssh
  - smbr
  - product
created: 2026-06-05
source: live-rg353m-bringup
---

# Persist guest SSH authorization and SMBR product in RG353M seed

## Why it matters

The guest reached multi-user and opened SSH on port 2222, but root login initially failed because authorized_keys was only restored to host /storage, not the guest root. SMBR also had to be copied into the guest store after boot instead of being present in the RG353M seed/product closure.

## Acceptance Criteria

- [ ] Port 2222 accepts the expected authorized key on first guest boot without manual injection.
- [ ] The RG353M guest seed/product closure includes the intended SMBR runtime payload or a documented post-seed install path.
- [ ] The legal ROM remains user-provided/preserved without embedding secrets or copyrighted content in artifacts.

## Related

- `guest/profiles/devices/rg353m.nix`
- `product-payload-rg353m.lock`
- `guest-rg353m.lock`
