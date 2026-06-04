---
id: task-013
title: Bring up RK3566 RK817 audio in guest
status: To Do
priority: high
labels:
  - rg353m
  - rk3566
  - after-device
  - audio
  - rk817
  - sd-card-only
created: 2026-06-04
source: user
---

# Bring up RK3566 RK817 audio in guest

## Why it matters

RG353M audio uses RK3566/RK817 topology, so SM8550 UCM and routing assumptions will not provide reliable speaker/headphone behavior. Bring-up must be validated from the removable-SD boot lane so Android/eMMC remains an untouched fallback.

## Acceptance Criteria

- [ ] The audio implementation is based on captured RK3566/RK817 `aplay -l` card names and mixer topology from an SD-booted Linux/ROCKNIX image, not SM8550 UCM assumptions.
- [ ] Guest PipeWire/WirePlumber or ALSA config routes speaker and headphones correctly for RG353M while running from removable SD.
- [ ] Speaker playback and headphone detection/playback are verified on device without writing to eMMC or replacing Android.
- [ ] Static contracts prevent RK3566 from accidentally importing the SM8550 AYN Odin2 UCM package.

## Related

- `devices/rk3566/audio/`
- `guest/modules/audio.nix`
- `guest/profiles/devices/rg353m.nix`
- `docs/brainstorms/evidence/`
- `docs/acceptance/`

## Notes

Logical work group: audio bring-up. Can run in parallel with display/input once first SD-boot evidence exists. Keep all persistence and recovery assumptions on the removable SD image unless a later task explicitly approves eMMC work.
