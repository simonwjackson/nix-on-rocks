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

### Session findings (2026-06-06)

Current runtime mitigation in place on the RG353M (temporary, NOT a design):

- **Host owns WiFi; the guest's network managers are masked/inactive.** This was done to stop host SSH and guest SSH from fighting over the RTL8821CS while iterating. It works for development but is not a shippable arrangement.
- All on-device iteration this session went host-WiFi → `ssh yuki` → `ssh -p 2222 root@192.168.1.140` (guest). Guest reachability depends entirely on the host WiFi link staying up; we saw intermittent `No route to host` when the link dropped.
- No Bluetooth work attempted this session.

What the proper design still needs to decide (the real deferred work):
- Who owns the radio (host vs guest) in the shipped image, and how SSH/networking is exposed without the two stacks contending.
- Whether the guest gets a virtual/bridged interface from the host rather than direct rtw88 control, OR the host stays headless-network-only and the guest owns the radio.
- Convert the ad-hoc masks into an explicit, documented RG353M/RK3566 network module rather than runtime `systemctl mask`.
- Keep the `rtw88_core disable_lps_deep=y` workaround regardless of which side owns the radio.

### Deploy / rebuild lane

**Mixed — leans full.** The host radio bits live in the ROCKNIX layer (`work/rocknix/projects/ROCKNIX/devices/RK3566/packages/linux/modprobe.d/rtw88.conf`, kernel/driver), so any change to who owns the radio or the rtw88 workaround needs a **full image rebuild** (`scripts/build-rk3566` / `build-rk3566.yml` → reflash/reseed). The guest-side network-manager design (converting the runtime `systemctl mask` into a guest module) is a **fast (guest-promote)** change. Plan the host/radio decision against the full lane; iterate the guest-manager module on the fast lane.
