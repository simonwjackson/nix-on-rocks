# Nix-on-Rocks guest

NixOS guest substrate modules, SM8550 emulator packages, and guest-side launch adapters for Nix-on-Rocks. Downstream product/appliance flakes consume nix-on-rocks; nix-on-rocks imports no product flake.

This `guest/` tree owns the reviewed Nix surface for the SM8550 substrate path:

- product-blind NixOS container guest profiles and modules;
- package derivations for guest Cemu, Moonlight, InputPlumber, and UCM;
- ROCKNIX `/storage` compatibility adapters and validation launchers;
- device-profile helpers used by downstream flakes for Thor and Odin 2 Portal.

ROCKNIX remains the base OS, boot/recovery plane, and host-side nspawn importer/launcher.

## Layout

- `flake.nix` exposes substrate NixOS configurations, emulator package outputs, `nixosModules.rocknix-guest-base`, device profile modules, device-selection helpers, and the rootfs packaging helper library.
- `rocknix-guest.nix` is the stable default Layer 10b/12 SSH-capable guest import.
- `modules/` contains reusable NixOS modules for the container baseline, SM8550 device policy, SSH, display, audio, network, tooling, and lid policy.
- `profiles/rocknix-guest-base.nix` is the product-blind SM8550 substrate contract for downstream product flakes.
- `profiles/` composes modules into `minimal`, `ssh`, `rocknix-guest-base`, `main-space` fallback, and `dev-env` profiles; `profiles/devices/` holds small SM8550 per-device overrides.
- `packages/cemu/` contains the ROCKNIX-informed Cemu derivation.
- `packages/` also contains InputPlumber, Moonlight, and UCM derivations.
- `launchers/` contains helper scripts used by the Layer 14 Cemu validation path.
- `scripts/static-checks.sh` is the packaged compatibility smoke entry point; repo-local source contracts live in `nix/tests/*.nix` and repo-root `scripts/check-*` commands.

## Flake outputs

Expected public substrate surfaces:

- `nixosModules.rocknix-guest-base` — downstream substrate contract; imports SM8550 guest plumbing without configuring product services.
- `nixosModules.thor` and `nixosModules.odin2portal` — device profile modules.
- `lib.deviceProfileByCompatible` and `lib.selectDeviceProfileFromCompatible` — downstream device-profile helpers for explicit device targets and impure by-compatible selection.
- `lib.mkGuestRootfs` — rootfs packaging helper for downstream product-owned NixOS configurations.
- `nixosConfigurations.rocknix-guest`
- `nixosConfigurations.rocknix-guest-dev-env`

Emulator package outputs are exposed for both systems:

```sh
nix build .#cemu --print-build-logs
nix build .#moonlight-embedded --print-build-logs
nix build .#default
nix build .#cemu-rocknix-package
```

Current package outputs:

| Package | Purpose |
| --- | --- |
| `cemu` | Direct Cemu package replica of ROCKNIX `cemu-sa`, with package-owned `bin/cemu` wrapper. |
| `moonlight-embedded` | SM8550-oriented Moonlight Embedded package. |
| `inputplumber` | Guest input daemon package. |
| `ayn-odin2-ucm` / `sm8550-ayn-odin2-ucm` | SM8550 AYN Odin audio UCM package. |
| `default` | Alias to `cemu`. |
| `cemu-rocknix-package` | Transitional compatibility alias for existing ROCKNIX Layer 14 consumers. |

## Retired legacy rootfs seed fallback

nix-on-rocks no longer publishes product/appliance rootfs artifacts. The old `.github/workflows/build-rootfs-seed.yml` workflow is retained only as a fail-closed retirement notice.

Canonical appliance rootfs artifacts are built from the product authority pinned in the per-product `product-payload-<product>.lock` files. The ROCKNIX host substrate still carries seed-fetch/verification plumbing, but product authority and provenance come from the downstream product flake.

## Runtime boundaries

The guest artifact must remain:

- container-style (`boot.isContainer = true`), built for `aarch64-linux`;
- free of default passwords, shipped authorized keys, or password login;
- explicit about host binds and `/storage` compatibility state;
- independent from ROCKNIX `/usr`, `/flash`, `/boot`, and host `/etc` mutation;
- free of broad `/storage/.cache` binds.

Layer 14 main-space fallback remains substrate-local for validation and manual recovery, but product/appliance composition should import `nixosModules.rocknix-guest-base` plus an explicit device profile and configure its own product services downstream. The minimal/SSH profile remains the small lifecycle/SSH validation baseline.

## Package boundary

Packages own app-generic setup:

- Nix Vulkan loader visibility in `packages/cemu`'s `bin/cemu` wrapper;
- SDL screensaver guard in `packages/cemu`'s `bin/cemu` wrapper;
- Cemu runtime data and SM8550 default settings under `$out/share/Cemu`;
- build evidence under `$out/nix-support/rocknix-cemu-build`.

Guest modules and launch adapters own device/session policy:

- ROCKNIX `/storage` compatibility layout;
- shared SM8550 defaults plus per-device overrides for display, input, audio UCM, and Cemu affinity;
- SM8550 host CPU/GPU tuning helpers;
- guest profile promotion/deploy scripts;
- BOTW/live validation orchestration;
- downstream product launch/session policy.

`launchers/start_cemu_guest.sh` defaults to `/run/current-system/sw/bin/cemu` and may fall back to a promoted profile for live rollback. It delegates ROCKNIX `/storage` layout compatibility to `cemu-storage-adapter.sh`; Vulkan loader setup stays in the Cemu package wrapper.

## Validation

Run local source and smoke checks from the repo root:

```sh
nix flake check --no-write-lock-file --print-build-logs
scripts/check-shell-smoke
scripts/check-boundary-lint
scripts/check-docs-contract
```

`guest/scripts/static-checks.sh` remains as a compatibility entry point for the
packaged ROCKNIX substrate and delegates to the split checks when the full repo
is present. New Nix/build invariants belong in `nix/tests/*.nix`; new shell
checks should exercise real shell/runtime behavior rather than grepping Nix
source spelling.

Evaluate and dry-run retained substrate closures:

```sh
nix flake show --all-systems --no-write-lock-file .
nix build --dry-run --no-write-lock-file .#nixosConfigurations.rocknix-guest.config.system.build.toplevel
nix build --dry-run --no-write-lock-file .#nixosConfigurations.rocknix-guest-dev-env.config.system.build.toplevel
```

Build package surfaces when package changes are in scope:

```sh
nix build .#cemu --print-build-logs
```

## Relationship to ROCKNIX and downstream products

Nix-on-Rocks owns SM8550 substrate facts, packages, and host patch plumbing. ROCKNIX remains the upstream substrate for boot, update, recovery, kernel/device integration, and host-side nspawn supervision. The downstream product flake owns appliance composition and rootfs artifacts by importing nix-on-rocks substrate surfaces.
