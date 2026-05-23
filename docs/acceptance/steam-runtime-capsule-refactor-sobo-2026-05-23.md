---
title: Steam runtime capsule refactor Sobo acceptance
type: acceptance
status: completed
date: 2026-05-23
---

# Steam runtime capsule refactor Sobo acceptance

## Decision

The Steam runtime capsule refactor preserves the supported SM8550/Sobo shape:
`guest/modules/steam.nix` remains the substrate adapter for `/storage`, session,
driver, uinput, and systemd defaults, while `packages/steam/` now owns reusable
Steam Runtime / pressure-vessel / FEX prep helpers and the aarch64 FHS run
capsule.

## Build and check evidence

From branch `refactor/steam-runtime-capsule`:

```sh
packages/steam/tests/steam-package-contract.sh
packages/steam/tests/steam-guest-runtime-prep-smoke.sh
packages/steam/tests/steam-guest-run-smoke.sh
guest/scripts/static-checks.sh
nix build .#steam --no-link --print-out-paths --print-build-logs
PACKAGE_OUT=$(nix build .#steam --no-link --print-out-paths) \
  packages/steam/tests/steam-package-contract.sh
nix eval .#nixosConfigurations.rocknix-guest.config.system.build.toplevel.name
nix build .#checks.x86_64-linux.static --no-link --print-build-logs
nix build .#checks.x86_64-linux.steam-package-contract --no-link --print-build-logs
nix build .#packages.aarch64-linux.steam --no-link --print-build-logs \
  --builders 'ssh://simonwjackson@fuji aarch64-linux'
```

Results:

- package contract tests passed
- runtime-prep fixture tests passed
- run-capsule fixture tests passed, including `--check` non-mutation coverage
- static checks passed locally and through the flake check
- x86 package build remained helper/check-only
- aarch64 Steam package built successfully on Fuji
- guest NixOS toplevel evaluated successfully

Aarch64 package built and copied to Sobo:

```text
/nix/store/scwngal6dx4pdj3hybzjp2f4rgr56sw2-steam-rocknix-guest-native-1.0.0.85-rocknix-guest-native
```

Copy command:

```sh
NIX_SSHOPTS='-p 2222 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no' \
  nix copy --no-check-sigs --to 'ssh://root@sobo' \
  /nix/store/scwngal6dx4pdj3hybzjp2f4rgr56sw2-steam-rocknix-guest-native-1.0.0.85-rocknix-guest-native
```

## Sobo smoke

Sobo was reachable as aarch64 over guest SSH port 2222. The mutable Steam client
was not currently seeded:

```text
steam-client-missing
```

Because no seeded client was present, validation used non-mutating package
checks and expected preflight failure for the missing client:

```sh
pkg=/nix/store/scwngal6dx4pdj3hybzjp2f4rgr56sw2-steam-rocknix-guest-native-1.0.0.85-rocknix-guest-native
export STEAM_HOME=/tmp/rocknix-steam-check/Steam
export STEAM_GAMES_ROOT=/tmp/rocknix-steam-check/games
export STEAM_DOT=/tmp/rocknix-steam-check/dot
$pkg/bin/steam-arm64-bootstrap --dry-run
$pkg/bin/steam-arm64-seed --dry-run
$pkg/bin/steam-guest-runtime-prep --check
FEX_ROOTFS=/tmp/fex-rootfs $pkg/bin/steam-guest-run --check
```

Result:

```text
sobo steam package checks ok
```

`steam-guest-run --check` failed with the expected clear missing-client hint when
`STEAM_HOME/steamrtarm64/steam` was absent. No real `/storage` Steam state was
rewritten during this acceptance pass.

## Follow-up

Run a bounded `rocknix-steam-guest` launch smoke after a real Sobo Steam home is
seeded. This refactor intentionally did not expand scope into Steam client
seeding or game launch behavior changes.
