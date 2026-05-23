# devices/sm8550/

SoC-bound data for Qualcomm Snapdragon 8 Gen 2 (codename `sm8550`).

## In-tree consumers

- Ayn Odin 2 (Sobo runtime, internal & SD variants)
- Ayn Thor (acceptance device)
- odin2portal (kiosk product)

All current consumers share the same SoC, same Adreno 740 GPU, same audio
codec topology. Per-product overrides (sway display topology, hostname,
deviceId) live in `guest/profiles/devices/<product>.nix`, not here.

## Contents

| Path | Purpose | Consumed by |
|---|---|---|
| `audio/ayn-odin2-ucm/` | ALSA UCM2 configuration for the Odin 2 audio codec | `packages.sm8550-ayn-odin2-ucm` flake output; activated by `guest/modules/audio.nix` |
| `cemu/settings.xml` | Cemu engine defaults tuned for sm8550 GPU/RAM topology | Injected into `packages.cemu` via the flake's `socSettings` callPackage arg |

## Adding more sm8550-bound data

Add files here when a piece of SoC-tuned data needs versioning alongside the
packages but cannot be folded into the upstream/canonical package itself
(e.g., engine settings tuned for the SoC's compute/memory profile, codec
topology files).

For per-product variation within sm8550 (e.g., a hypothetical Thor-only
display profile), prefer adding it as a per-product override under
`guest/profiles/devices/<product>.nix` rather than a sub-directory here.

## Future siblings

When the Retroid Pocket Mini (Snapdragon 865, codename `sm8250`) work
starts, create `devices/sm8250/` with the same shape:
`audio/<codec>-ucm/`, `cemu/settings.xml`, etc. Flake callsites pass the
sm8250 paths to the same package derivations — no fork needed.
