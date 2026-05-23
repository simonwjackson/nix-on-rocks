# Guest-native Steam package

This package captures the reusable, package-owned pieces needed to make the
ROCKNIX Steam ARM64 flow run **inside the NixOS guest** on SM8550.

The target is guest-native Steam: the ARM64 Steam client/runtime live in
guest-owned mutable state and `steam-guest-native` executes that client from the
guest. Host Steam/FEX fallback, display bridging from host to guest, and
ROCKNIX-specific session control are intentionally not part of this package.

## Build

```sh
nix build .#steam --print-build-logs
```

This v1 package does not place Valve Steam client/runtime payloads in the Nix
store. Those mutable payloads are fetched into caller-provided guest state by
`steam-arm64-seed --apply`.

## Output

- `$out/bin/steam-arm64-bootstrap` — writes package-owned VDF/resource metadata
  into explicit mutable Steam paths.
- `$out/bin/steam-arm64-seed` — downloads and extracts the ARM64 Steam runtime
  and client into explicit guest-owned mutable paths.
- `$out/bin/steam-guest-native` — preflights and execs the ARM64 Steam client
  from inside the guest.
- `$out/share/steam-rocknix-bootstrap/resources/` — ROCKNIX-derived Steam VDF
  resources.
- `$out/nix-support/rocknix-steam-bootstrap/` — source provenance and contract
  evidence for downstream consumers.

## Guest-native quick shape

Downstream guest configuration chooses the real paths. For example:

```sh
export STEAM_HOME=/var/lib/steam
export STEAM_GAMES_ROOT=/var/lib/steam-library
export STEAM_DOT=/var/lib/steam-dot

steam-arm64-seed --apply
steam-guest-native --check
steam-guest-native -steamdeck
```

`steam-guest-native` refuses to run if the guest does not provide a generic Linux
dynamic-linker strategy for the ARM64 Steam ELF. In NixOS terms, the guest needs
something like `programs.nix-ld` with `NIX_LD` exported into the session, or an
FHS-compatible `/lib/ld-linux-aarch64.so.1`.

## Package boundary

This package owns:

- ROCKNIX Steam resource files
- ARM64 Steam bootstrap endpoint metadata
- guest-owned ARM64 Steam runtime/client seeding helper
- guest-native Steam launcher preflight and exec helper
- Steam ARM64 manifest repair helper logic
- source/evidence metadata under `$out/nix-support`

Downstream ROCKNIX or guest integrations own:

- selected mutable Steam home/library paths
- guest nix-ld/FHS dynamic-linker policy
- FEX rootfs and thunk configuration for x86 games
- binfmt state
- Sway, Gamescope, and display-session launch policy
- per-game Proton settings
- SM8550 power and affinity policy

## Unsupported in v1

- `nix run .#steam` as a complete desktop/session launcher
- guest-native Steam without a guest-provided nix-ld or FHS loader strategy
- immutable Nix-store Valve ARM64 client/runtime seed artifacts
- host Steam displayed into the guest as a fallback
- Balatro-specific launch behavior
