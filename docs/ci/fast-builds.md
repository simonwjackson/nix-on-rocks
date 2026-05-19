# CI fast-build lanes

Nix-on-Rocks keeps ROCKNIX source out of the product repo, so every CI job first fetches the pinned upstream tree and applies `patches/rocknix/series`. The expensive part is not patch replay; it is rebuilding the SM8550 toolchain/base packages and packaging the update tar.

## Lanes

### Full build

Workflow: `.github/workflows/build-sm8550.yml`

Builds from the product repo only:

1. build/push the ROCKNIX Docker build image;
2. build the aarch64 toolchain;
3. build the SM8550 base/image artifacts;
4. verify and upload payloads.

Use this for authoritative release proof from scratch.

### Continue from toolchain

Workflow: `.github/workflows/continue-sm8550-from-toolchain.yml`

Input:

- `toolchain_run_id`: a previous run that uploaded `aarch64-toolchain (SM8550)`.

This skips the multi-hour toolchain build and rebuilds base/image using the saved toolchain. This is the current fast lane for product iteration.

Known-good toolchain source:

- run `26037562850`

## Cache strategy

The workflows now have hooks for ccache restore/save:

- toolchain cache: `ccache-aarch64-SM8550-toolchain.tar`
- base cache: `ccache-aarch64-SM8550.tar`

Restore order:

1. this repo's `ccache` release assets;
2. upstream `ROCKNIX/distribution-cache` release assets.

Saving is best-effort and writes to this repo's `ccache` release tag using `GITHUB_TOKEN`. Cache failures must not fail a build.

## Current speed expectations

- Cold full build: many hours.
- Continue from existing toolchain: roughly 2.5–3 hours until base ccache warms.
- Warm ccache builds: expected to improve after successful runs have populated this repo's cache assets.

## Next fast lane

A future image-only lane should consume a known-good base artifact and only rerun image/update packaging and manifest verification. That will be the right lane for changes limited to packaging, manifest logic, docs, or seed validation.
