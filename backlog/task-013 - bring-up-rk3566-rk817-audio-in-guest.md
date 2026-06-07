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

### Session findings (2026-06-06)

Observed on the live RG353M guest while bringing up SMBR/RetroArch + gamescope:

- The guest currently ships `rk3566-empty-ucm` — an empty/placeholder UCM, so there is no real RK817 routing. This is the concrete blocker, not just "SM8550 assumptions".
- PipeWire/WirePlumber on the guest do **not** auto-enumerate the real ALSA RK817 devices, so even apps that try PipeWire get no usable sink (consistent with the empty UCM).
- RetroArch under gamescope opened audio via PulseAudio shim → ALSA (`[PulseAudio]: Requested 24576 bytes buffer, got 18432`, `[ALSA] Using ALSA version 1.2.14`, `Started synchronous audio driver`) but with the empty UCM there is no guarantee sound reaches the RK817 speaker. Output was never confirmed audible (we were told **not** to emit loud tones without confirmation; RK817 hardware volume kept at 25%).
- Net: Mario/SMBR has audio *plumbing* but speaker output is unverified and almost certainly silent until a real RK817 UCM + WirePlumber config lands.

Concrete next steps when picked up:
- Capture `aplay -l`, `amixer`/`alsaucm` topology, and the RK817 card/mixer names from an SD-booted ROCKNIX image (ground truth).
- Replace `rk3566-empty-ucm` with a real UCM (or a minimal ALSA `.conf` route) for speaker + headphone-detect.
- Verify with a quiet sample first (explicit confirmation before anything loud), volume capped.

### Deploy / rebuild lane

**Fast (guest-promote).** `rk3566-empty-ucm` is defined in `guest/modules/rk3566.nix`, so the real UCM/WirePlumber config is a guest-module change: rebuild the guest closure and `rocknix-guest-promote` (build packaged main-space config in the running guest, repoint the guest-system profile, restart guest once) — no SD reflash. Only needs a **full image rebuild** (`scripts/build-rk3566` / `build-rk3566.yml` → reflash) if the fix turns out to require host-ROCKNIX-layer ALSA/kernel bits or a fresh seeded baseline.
