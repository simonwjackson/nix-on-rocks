---
id: task-014
title: Stabilize RG353M WiFi and Bluetooth path
status: To Do
priority: medium
labels:
  - rg353m
  - rk3566
  - after-device
  - wifi
  - bluetooth
  - rtw88
  - sd-card-only
created: 2026-06-04
source: user
---

# Stabilize RG353M WiFi and Bluetooth path

## Why it matters

RG353M uses RTL8821CS with known rtw88 quirks, and networking is needed for productive on-device iteration and guest updates. The target is a self-contained removable-SD image; Android/eMMC must remain available as the fallback path.

## Acceptance Criteria

- [ ] Host modprobe configuration preserves the `rtw88_core disable_lps_deep=y` workaround for RK3566 in the SD-booted ROCKNIX lane.
- [ ] WiFi interface discovery, connection, and reboot persistence are verified on hardware with configuration stored on the removable SD image, not eMMC.
- [ ] Bluetooth device discovery is documented and enabled or explicitly deferred with evidence from the SD-booted image.
- [ ] Any observed WiFi/audio interference is recorded in an acceptance or solution note with recommended operator workaround.
- [ ] The task does not require replacing Android, modifying eMMC boot partitions, or depending on internal storage for network persistence.

## Related

- `work/rocknix/projects/ROCKNIX/devices/RK3566/packages/linux/modprobe.d/rtw88.conf`
- `guest/modules/`
- `docs/brainstorms/evidence/`
- `docs/acceptance/`

## Notes

Logical work group: network bring-up. Should follow first SD-boot evidence and can be after core display/input/audio if needed. Do not promote any eMMC/network-manager migration as part of this slice.
