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

The device did not expose an `anbernic,rg353m` or `anbernic,rg353p` compatible string in Android. Production profile selection therefore keeps the first captured compatible string, `rockchip,rk3566-rk817-tablet`, as an explicit RG353M support-lane key. This is intentionally narrower than matching generic `rockchip,rk3566`.

The 2026-06-04 official ROCKNIX SD baseline probe in `docs/brainstorms/evidence/2026-06-04-rg353m-official-rocknix-sd-baseline.md` captured the removable-SD boot identity:

- device-tree model: `Anbernic RG353M`
- ordered compatible strings:
  1. `anbernic,rg353p`
  2. `rockchip,rk3566`

The SD-boot compatible string is ambiguous with real RG353P-family hardware, so production does **not** register `anbernic,rg353p` directly as an RG353M profile key. Instead, `deviceProfileByModel` maps `Anbernic RG353M` to the registered RG353M support-lane key `rockchip,rk3566-rk817-tablet`. A device that reports `Anbernic RG353P` plus `anbernic,rg353p` must remain unclaimed by the RG353M profile unless a dedicated RG353P profile is added later.

## Seed compatibility consequence

The host seed/promotion substrate currently compares a seed manifest's `seed_compatible` values against the device's normalized compatible-string list. That is separate from this flake-level model alias. For Android-like RG353M evidence the board-specific compatible is `rockchip,rk3566-rk817-tablet`; for SD-boot evidence the runtime compatible list is `anbernic,rg353p rockchip,rk3566`, while flake profile selection uses the `Anbernic RG353M` model alias.

Do not use the generic fallback `rockchip,rk3566` for RG353M seed publication. The RK3566 host seed gate is model-aware for the documented SD-only RG353M lane: a seed that declares `rockchip,rk3566-rk817-tablet` may be accepted on SD boot only when the device model is exactly `Anbernic RG353M` and the runtime compatible list contains both `anbernic,rg353p` and `rockchip,rk3566`. A real `Anbernic RG353P` model with the same ambiguous compatible shape must fail closed unless a dedicated RG353P profile/seed is added later. A seed that only declares an unrelated compatible, such as an SM8550 `ayn,*` compatible, must fail closed with the existing wrong-device seed error.

## RG353-family model-alias seam

Tests keep both fixture and production cases for the ambiguous RG353-family shape. The fixture documents how a future `anbernic,rg353m` key would work if hardware exposed one; the production case uses the captured `Anbernic RG353M` model alias because official ROCKNIX SD boot exposes `anbernic,rg353p` as the first compatible string.

## Hardware evidence requirement

Do not add further RG353-family aliases from speculation. First capture device evidence with the RG353M arrival probe protocol in `docs/plans/2026-06-04-001-feat-rg353m-rk3566-support-plan.md`, then wire exact observed model/compatible strings.
