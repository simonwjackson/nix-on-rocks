---
id: task-021
title: Bring up RG353M display touchscreen and controls
status: To Do
priority: high
labels:
  - rg353m
  - rk3566
  - after-device
  - display
  - touchscreen
  - input
  - controls
  - guest-profile
  - sd-card-only
created: 2026-06-04
source: user
---

# Bring up RG353M display touchscreen and controls

## Why it matters

A visible compositor and working handheld controls are the core proof that the RK3566 guest profile is viable on the RG353M. The proof should come from the removable-SD boot lane, with Android/eMMC left untouched.

## Acceptance Criteria

- [ ] RG353M guest display config uses DRM connector/output name, orientation, and resolution captured from an SD-booted Linux/ROCKNIX image.
- [ ] Touchscreen mapping is configured only if the SD-booted hardware exposes one and is verified with the real input device.
- [ ] Hardcoded AYN input-device names are parameterized or bypassed for RK3566.
- [ ] RG353M button, d-pad, shoulder, trigger, analog stick, power, and volume event names are derived from captured SD-boot evidence.
- [ ] The guest exposes controls through the intended input path, with InputPlumber used only if it is actually required for RG353M.
- [ ] Hardware smoke results show the chosen guest UI appears correctly on the panel and controls generate expected events inside the guest while booted from removable SD.
- [ ] No display/input acceptance step requires replacing Android, modifying eMMC, or storing state on internal storage.
- [ ] SM8550 display and input configuration remain unchanged.

## Related

- `guest/modules/display.nix`
- `guest/modules/input.nix`
- `guest/modules/lid.nix`
- `packages/inputplumber/maps/`
- `guest/profiles/devices/rg353m.nix`
- `docs/brainstorms/evidence/`
- `docs/acceptance/`

## Notes

Logical work group: display/touch/control bring-up. Consolidates task-011 and task-012. Can still be split during promotion if captured SD-boot input evidence is unexpectedly complex.

### Session findings (2026-06-06) — D-pad / InputPlumber, runtime-only, needs persisting to code

The controls were made to work on the live guest but **only via runtime drop-ins under `/run/`** — none of this survives a reseed and none is in the repo yet. Persisting it is the remaining work.

Root cause (confirmed via `evtest`): the source pad `retrogame_joypad` emits the D-pad as **`BTN_DPAD_UP/DOWN/LEFT/RIGHT` (codes 544–547)**, not as `ABS_HAT0X/Y`. InputPlumber's default capability inference does **not** recognize those four codes, so D-pad presses were dropped before reaching the virtual `Microsoft X-Box 360 pad`. Face buttons (BTN_SOUTH/EAST) and Start worked; D-pad was dead.

Working runtime fix (to be turned into shipped config):
1. **InputPlumber capability_map** `rocknix_rg353m_dpad` (v2 CapabilityMap) mapping the four `BTN_DPAD_*` source events → gamepad `DPadUp/Down/Left/Right`. Lives at `/run/inputplumber-extra/inputplumber/capability_maps/rocknix-rg353m.yaml`.
2. **Device YAML** `/run/inputplumber-extra/inputplumber/devices/50-rg353m.yaml` matching `retrogame_joypad` with `auto_manage: true` and `capability_map_id: rocknix_rg353m_dpad`.
3. Had to replace the read-only `capability_maps` symlink in `/run/inputplumber-extra/...` with a real dir of symlinks mirroring the package contents (same pattern as `devices/`).
4. **RetroArch autoconfig** `/storage/.config/retroarch/autoconfig/Microsoft X-Box 360 pad.cfg` (+ `udev/` copy), standard XInput layout (BTN→0..10, sticks ±0/1/3/4, triggers +2/+5, hat h0).

Post-fix `evtest` on event6 confirmed: DPAD UP→`ABS_HAT0Y=-1`, DOWN→`+1`, LEFT→`ABS_HAT0X=-1`, RIGHT→`+1` — matching the autoconfig's `h0up/h0down/h0left/h0right`. Super Mario Advance was fully playable (A/B/Start/D-pad) via the virtual Xbox-360 pad in the direct-to-Wayland path.

Persistence work (the actual deferred task):
- Ship the `rocknix_rg353m_dpad` capability_map + `50-rg353m.yaml` device match in `guest/modules/rk3566.nix` (or a dedicated InputPlumber module), with a full package data-dir mirror rather than the `/run/` symlink trick.
- Ship the `Microsoft X-Box 360 pad.cfg` RetroArch autoconfig in the RG353M payload.
- Make `/sys` writable in the RG353M guest nspawn (required for the InputPlumber runtime fix).
- Fix the `rocknix-guest-hide-raw-gamepad-start` script to pass the actual wanted name(s) (e.g. `"Microsoft X-Box 360 pad"`).
- Replace `/run/inputplumber-extra/` mirror trick with a proper package layout (or pre-baked full mirror).

### Deploy / rebuild lane

**Fast (guest-promote) + payload re-render.** The InputPlumber capability_map/device YAML and the `/sys`-writable nspawn change live in `guest/modules/rk3566.nix` (guest module) → rebuild guest closure + `rocknix-guest-promote`, no reflash. The RetroArch `Microsoft X-Box 360 pad.cfg` autoconfig ships in the Korri product payload → `scripts/render-product-payload` + redeploy payload. Neither needs a **full image rebuild** unless the InputPlumber package itself (host ROCKNIX layer) must change to support multi-dir data search instead of the pre-baked mirror.
