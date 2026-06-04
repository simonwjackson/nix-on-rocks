# Device identity selection contract

## Purpose

nix-on-rocks selects a guest device profile from Linux device-tree identity. The common case is a direct match from `/proc/device-tree/compatible` to `flake.nix`'s `deviceProfileByCompatible` table. Some device families can reuse a compatible string for multiple products and distinguish the physical product through a runtime model fixup. RG353-family U-Boot is expected to be one of those cases: RG353M may boot with the RG353P DTB while exposing an RG353M model.

This contract keeps the direct-compatible path as the default while reserving model-aware fallback for documented ambiguous device families.

## Selection order

1. If a documented model alias exists and points to a registered compatible key, select that profile.
2. Otherwise, select the first compatible string that appears in `deviceProfileByCompatible`.
3. If neither source matches, fail with a clear error that includes the model and compatible strings.

## Current registered devices

The current production table includes the validated SM8550 identities and the captured RK3566/RG353M identity:

- `ayn,thor`
- `ayn,odin2portal`
- `rockchip,rk3566-rk817-tablet`

## Captured RG353M identity

The 2026-06-04 Android ADB probe in `docs/brainstorms/evidence/2026-06-04-rg353m-android-adb-identity.md` captured this physical-device identity:

- Android/USB product model: `RG353P`
- device-tree model: `Rockchip RK3566 RK817 TABLET LP4X Board`
- ordered compatible strings:
  1. `rockchip,rk3566-rk817-tablet`
  2. `rockchip,rk3566`

The device did not expose an `anbernic,rg353m` or `anbernic,rg353p` compatible string in Android. Production profile selection therefore uses the first captured compatible string, `rockchip,rk3566-rk817-tablet`, as an explicit RG353M support-lane key. This is intentionally narrower than matching generic `rockchip,rk3566` and should be revisited if a later ROCKNIX SD boot exposes a more specific Anbernic compatible.

## Seed compatibility consequence

The host seed/promotion substrate compares a seed manifest's `seed_compatible` values against the device's normalized compatible-string list. For RG353M seeds, the intended seed identity is therefore `rockchip,rk3566-rk817-tablet`; a seed that only declares an unrelated compatible, such as an SM8550 `ayn,*` compatible, must fail closed with the existing wrong-device seed error. Do not use the generic fallback `rockchip,rk3566` for RG353M seed publication unless later hardware evidence proves the board-specific compatible is unavailable in the target boot path.

## RG353-family model-alias seam

Tests still keep a fixture for the pre-arrival ambiguous shape where a model alias maps `Anbernic RG353M` to an `anbernic,rg353m` profile while a plain RG353P-shaped identity uses direct compatible selection. That fixture documents the supported extension seam, but production currently does not use a model alias because the captured device-tree model is generic.

## Hardware evidence requirement

Do not add further RG353-family aliases from speculation. First capture device evidence with the RG353M arrival probe protocol in `docs/plans/2026-06-04-001-feat-rg353m-rk3566-support-plan.md`, then wire exact observed model/compatible strings.
