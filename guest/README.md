# Nix-on-Rocks guest

NixOS guest flake, emulator packages, and guest-side launch adapters for Nix-on-Rocks SM8550 main-space devices, with Thor and Odin 2 Portal kept as first-class device-profile targets.

This `guest/` tree owns the reviewed Nix surface for the SM8550 guest path:

- NixOS container guest profiles, modules, and rootfs outputs;
- package derivations for guest Cemu and guest-native Steam helpers;
- Korri frontend consumption via Korri's exported NixOS module and package;
- ROCKNIX `/storage` compatibility adapters and validation launchers.

ROCKNIX remains the base OS, boot/recovery plane, and host-side nspawn importer/launcher.

## Layout

- `flake.nix` exposes aarch64 NixOS guest configurations, rootfs packages, emulator package outputs, and the consumed Korri flake input.
- `rocknix-guest.nix` is the stable default Layer 10b/12 SSH-capable guest import.
- `modules/` contains reusable NixOS modules for the container baseline, SM8550 device policy, SSH, display, audio, network, tooling, Steam, and lid policy.
- `profiles/` composes modules into `minimal`, `ssh`, `main-space`, and `dev-env` profiles; `profiles/devices/` holds small SM8550 per-device overrides.
- `packages/cemu/` contains the direct ROCKNIX-informed Cemu derivation, manifest, patches, and SM8550 default settings.
- `packages/steam/` contains guest-native Steam ARM64 bootstrap/seed/launch helpers, resources, and source manifest.
- `launchers/` contains guest/host helper scripts used by the Layer 14 main-space Cemu validation path.
- `scripts/static-checks.sh` is the repo-local structural check suite.
- `justfile` provides local development shortcuts that preserve committed flake inputs by default.

## Flake outputs

Configurations:

```sh
nix flake show --all-systems .
```

Expected NixOS configurations:

- `nixosConfigurations.rocknix-guest`
- `nixosConfigurations.rocknix-guest-main-space` (backward-compatible alias to Thor)
- `nixosConfigurations.rocknix-guest-main-space-thor`
- `nixosConfigurations.rocknix-guest-main-space-odin2portal`
- `nixosConfigurations.rocknix-guest-stage10-proof-thor`
- `nixosConfigurations.rocknix-guest-stage10-proof-odin2portal`
- `nixosConfigurations.rocknix-guest-dev-env`

Rootfs package outputs are exposed for `x86_64-linux` and `aarch64-linux` hosts:

```sh
nix build .#rootfs          # alias to Thor for current ROCKNIX packaging
nix build .#rootfs-thor
nix build .#rootfs-odin2portal
sha256sum result/tarball/*.tar.*
```

Emulator package outputs are also exposed for both systems:

```sh
nix build .#cemu --print-build-logs
nix build .#steam --print-build-logs
# equivalent Cemu compatibility surfaces:
nix build .#default
nix build .#cemu-rocknix-package
```

Current package outputs:

| Package | Purpose |
| --- | --- |
| `cemu` | Direct Cemu package replica of ROCKNIX `cemu-sa`, with package-owned `bin/cemu` wrapper. |
| `steam` | ROCKNIX-informed guest-native Steam ARM64 package helpers. |
| `default` | Alias to `cemu`. |
| `cemu-rocknix-package` | Transitional compatibility alias for existing ROCKNIX Layer 14 consumers. |
| `rootfs` | Layer 10b guest rootfs tarball imported by current ROCKNIX host tooling; aliases Thor. |
| `rootfs-thor` | Thor main-space rootfs tarball. |
| `rootfs-odin2portal` | Odin 2 Portal main-space rootfs tarball using the shared SM8550 defaults plus Odin 2 Portal profile overrides. |

The rootfs tarball is imported by ROCKNIX host tooling under the configured Layer 10 guest root, normally `/storage/machines/rocknix-guest`.

## Publishing first-boot rootfs seed artifacts

The ROCKNIX host first-boot path consumes a pinned, immutable rootfs seed tarball rather than the guest source tree. The product repo workflow `.github/workflows/build-rootfs-seed.yml` runs from this `guest/` flake; `guest/.github/workflows/build-rootfs-seed.yml` is kept only for the guest tree's standalone structural checks.

- `workflow_dispatch` builds `.#rootfs-thor` or `.#rootfs-odin2portal` and always uploads a short-lived workflow artifact for inspection.
- When run from a `rootfs-seed-*` tag, or when `publish_release=true` is selected manually, it publishes GitHub Release assets. Oversized seeds are split into `.part-*` assets so each release upload stays below GitHub's single-asset limit.
- The release notes print the exact `PKG_NIX_GUEST_ROOTFS_SEED_REV`, `PKG_NIX_GUEST_ROOTFS_SEED_URLS`, and `PKG_NIX_GUEST_ROOTFS_SEED_SHA256` values for the ROCKNIX host `rocknix-guest-substrate/package.mk` pin.

ROCKNIX host images do **not** embed this multi-GB seed in `/flash/SYSTEM`. The host ships only a manifest and expects the matching seed to be staged offline under `/storage/nix-on-rock/images/seeds/`:

```sh
mkdir -p /storage/nix-on-rock/images/seeds
cp rocknix-guest-rootfs-<device>-<short-sha>.tar.zst /storage/nix-on-rock/images/seeds/
```

SM8550 update tarballs may carry the seed under `target/seed/` and hoist it to `/storage/nix-on-rock/images/seeds/` before writing the new `SYSTEM`. Full-image installs require copying the matching seed to `/storage/nix-on-rock/images/seeds/` after flashing, before a fresh `/storage` can boot the guest. `/storage/.guest` is only the guest-visible compatibility exchange path during the migration window.

Prefer release assets over workflow artifacts for host consumption: workflow artifacts expire and are API-oriented, while release URLs are stable enough for the host package fetch/verify step. Do not stage an Odin2Portal seed on Thor/Bandai or a Thor seed on Odin2Portal/sobo; the host manifest verifies the device compatible string before extraction.

## Local Korri development

The committed `korri` flake input in `flake.nix` is the source of truth. Do not replace it with a local path for development. The main-space profile imports `korri.nixosModules.korri-frontend`, enables `services.korri`, and selects Korri's `korri-desktop-odin` package variant until Korri publishes a stable device alias.

When iterating against a local Korri checkout, set `KORRI_INPUT` and use a recipe or pass the override to Nix directly:

```sh
KORRI_INPUT=path:../../korri just build rootfs-odin2portal
nix build .#rootfs-odin2portal --override-input korri path:../../korri
```

If `KORRI_INPUT` is unset, recipes use the committed, locked flake input.

## Runtime boundaries

The guest artifact must remain:

- container-style (`boot.isContainer = true`), built for `aarch64-linux`;
- free of default passwords, shipped authorized keys, or password login;
- explicit about host binds and `/storage` compatibility state;
- independent from ROCKNIX `/usr`, `/flash`, `/boot`, and host `/etc` mutation;
- free of broad `/storage/.cache` binds.

Layer 14 main-space intentionally adds Sway, Mesa/Freedreno, PipeWire, NetworkManager, Cemu, Steam helpers, Korri, and launch adapters. The minimal/SSH profile remains the small lifecycle/SSH validation baseline.

## Package boundary

Packages own app-generic setup:

- Nix Vulkan loader visibility in `packages/cemu`'s `bin/cemu` wrapper;
- SDL screensaver guard in `packages/cemu`'s `bin/cemu` wrapper;
- Cemu runtime data and SM8550 default settings under `$out/share/Cemu`;
- Steam ARM64 guest-native seed/launch helpers, bootstrap resources, and source evidence under `$out/share/steam-rocknix-bootstrap` and `$out/nix-support/rocknix-steam-bootstrap`;
- Korri's frontend package, Electrobun launch wrapper, and build-time native bridge URL in the Korri flake;
- build evidence under `$out/nix-support/rocknix-cemu-build`.

Guest modules and launch adapters own device/session policy:

- ROCKNIX `/storage` compatibility layout;
- shared SM8550 defaults plus per-device overrides for display, input, audio UCM, and Cemu affinity;
- SM8550 host CPU/GPU tuning helpers;
- guest profile promotion/deploy scripts;
- Korri module import, `services.korri.package` selection, and Home then `k` Sway launch binding;
- BOTW/live validation orchestration;
- guest FHS/nix-ld loader policy, FEX rootfs management, Sway/Gamescope launch policy, and per-game Proton settings.

`rocknix-guest-main-space` installs the in-repo package outputs directly:

```nix
services.korri = {
  enable = true;
  package = korri.packages.${targetSystem}.korri-desktop-odin;
};

systemd.services.rocknix-sway-kiosk.path = [ config.services.korri.package ];

environment.systemPackages = [
  (packageSetFor targetSystem).cemu
  (packageSetFor targetSystem).steam
];
```

`launchers/start_cemu_guest.sh` defaults to `/run/current-system/sw/bin/cemu` and may fall back to a promoted profile for live rollback. It delegates ROCKNIX `/storage` layout compatibility to `cemu-storage-adapter.sh`; Vulkan loader setup stays in the Cemu package wrapper.

Korri launches from the main-space Sway Home chord: press Home, then `k`. The guest owns the Sway binding and session environment (`HOME=/storage`, `XDG_RUNTIME_DIR=/run/user/0`, root session D-Bus, PipeWire Pulse socket); Korri owns its package/module logic and build-time frontend configuration.

## Validation

Run local structural checks:

```sh
./scripts/static-checks.sh
```

Evaluate and dry-run the main-space closure:

```sh
nix flake show --all-systems --no-write-lock-file .
nix build --dry-run --no-write-lock-file .#nixosConfigurations.rocknix-guest-main-space.config.system.build.toplevel
```

Build package surfaces when package changes are in scope:

```sh
nix build .#cemu --print-build-logs
nix build .#steam --print-build-logs
```

## Relationship to ROCKNIX and Nix-on-Rocks

Nix-on-Rocks owns this guest tree and the SM8550 seed lifecycle. ROCKNIX remains the upstream substrate for boot, update, recovery, kernel/device integration, and host-side nspawn supervision. Host-side changes are carried as patches under `../patches/rocknix/`; this guest tree is the source of truth for Thor and Odin2Portal rootfs builds.
