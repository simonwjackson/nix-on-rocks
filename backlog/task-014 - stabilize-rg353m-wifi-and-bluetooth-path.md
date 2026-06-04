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
created: 2026-06-04
source: user
---

# Stabilize RG353M WiFi and Bluetooth path

## Why it matters

RG353M uses RTL8821CS with known rtw88 quirks, and networking is needed for productive on-device iteration and guest updates.

## Acceptance Criteria

- [ ] Host modprobe configuration preserves the `rtw88_core disable_lps_deep=y` workaround for RK3566.
- [ ] WiFi interface discovery, connection, and reboot persistence are verified on hardware.
- [ ] Bluetooth device discovery is documented and enabled or explicitly deferred with evidence.
- [ ] Any observed WiFi/audio interference is recorded in an acceptance or solution note with recommended operator workaround.

## Related

- `work/rocknix/projects/ROCKNIX/devices/RK3566/packages/linux/modprobe.d/rtw88.conf`
- `guest/modules/`
- `docs/brainstorms/evidence/`
- `docs/acceptance/`

## Notes

Logical work group: network bring-up. Should follow first-boot evidence and can be after core display/input/audio if needed.
