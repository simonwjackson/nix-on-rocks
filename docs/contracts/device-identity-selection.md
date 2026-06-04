# Device identity selection contract

## Purpose

nix-on-rocks selects a guest device profile from Linux device-tree identity. The common case is a direct match from `/proc/device-tree/compatible` to `flake.nix`'s `deviceProfileByCompatible` table. Some device families can reuse a compatible string for multiple products and distinguish the physical product through a runtime model fixup. RG353-family U-Boot is expected to be one of those cases: RG353M may boot with the RG353P DTB while exposing an RG353M model.

This contract keeps the direct-compatible path as the default while reserving model-aware fallback for documented ambiguous device families.

## Selection order

1. If a documented model alias exists and points to a registered compatible key, select that profile.
2. Otherwise, select the first compatible string that appears in `deviceProfileByCompatible`.
3. If neither source matches, fail with a clear error that includes the model and compatible strings.

## Current registered devices

The current production table remains SM8550-only:

- `ayn,thor`
- `ayn,odin2portal`

No RG353M profile is registered yet. The RG353-family contract is covered with fixture tables until the physical device arrives and the real `/proc/device-tree/model` plus `/proc/device-tree/compatible` values are captured.

## RG353-family expectation before hardware evidence

Before the RG353M arrives, tests model the expected ambiguous shape:

- model: `Anbernic RG353M`
- compatible strings include `anbernic,rg353p`
- model alias fixture maps `Anbernic RG353M` to `anbernic,rg353m`

The contract expects the model alias to win only when the alias exists and its target profile is registered. A RG353P-shaped identity without that alias continues to use direct compatible-string selection.

## Hardware evidence requirement

Do not register a real RG353M model alias from this contract alone. First capture device evidence with the RG353M arrival probe protocol in `docs/plans/2026-06-04-001-feat-rg353m-rk3566-support-plan.md`, then wire the exact observed model/compatible strings.
