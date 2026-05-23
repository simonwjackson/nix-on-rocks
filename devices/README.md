# devices/

SoC-bound data files and small derivations that wrap them.

## When to add a directory here

Add `devices/<soc>/` when introducing a new SoC. Example: `devices/sm8550/`
for Snapdragon 8 Gen 2 devices (Ayn Odin 2 family). The directory name is
the upstream SoC codename (`sm8550`, `sm8250`, etc.) — not the product
family name.

## What belongs here

- Audio UCM configurations (codec/DSP routing — SoC-specific)
- Engine-specific tuning files (e.g., cemu settings tuned for the SoC's GPU)
- Boot-time device tree fragments that aren't already part of ROCKNIX

## What does NOT belong here

- Per-product overrides (hostname, sway display topology) — those live in
  `guest/profiles/devices/<product>.nix`.
- Per-controller / per-MCU input maps — those live with the consuming
  package (`packages/inputplumber/maps/`), because inputplumber selects
  them at runtime based on hardware detection, not SoC.
- Anything `import`ed by a `packages/` derivation. Packages receive
  device-specific data via callPackage arguments from the flake (e.g.,
  cemu accepts `socSettings` and `socName`), never via
  `import ../devices/...`. Dependency direction is one-way:
  `flake → packages` and `flake → devices`, never `packages → devices`.

## Currently populated

- [`sm8550/`](sm8550/README.md) — Ayn Odin 2 family (Sobo, Thor, odin2portal)

## Future slots

- `devices/sm8250/` — when Retroid Pocket Mini (Snapdragon 865) work begins.
