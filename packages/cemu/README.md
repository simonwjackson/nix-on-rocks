# Cemu package

This package is a direct Nix translation of the ROCKNIX `cemu-sa` package
contract used for SM8550 Layer 14 validation.

It intentionally does **not** inherit from `nixpkgs#cemu`: the goal is to keep
ROCKNIX's known-good Cemu source, patches, bundled Cubeb behavior, runtime data,
and launch shape while moving generic runtime setup into the Nix package.

## Build

```sh
nix build .#cemu --print-build-logs
```

Use Fuji or another aarch64 builder for production aarch64 closures; Thor should
consume imported closures rather than building heavy packages locally.

## Entry points

- `$out/bin/cemu` — package-owned wrapper; use this for normal launch.
- `$out/bin/Cemu` — real Cemu binary; kept for compatibility/fingerprinting.

The wrapper owns the Nix Vulkan loader path and SDL screensaver guard so ROCKNIX
launcher glue does not need to mutate those generic runtime details.
