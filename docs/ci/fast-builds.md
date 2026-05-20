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

This skips the multi-hour toolchain build and rebuilds base/image using the saved toolchain. The workflow defaults to the known-good toolchain run so routine product iteration can be started without retyping it.

Known-good toolchain source:

- run `26037562850`

### Prepare base artifacts

Workflow: `.github/workflows/prepare-sm8550-base.yml`

Input:

- `toolchain_run_id`: a previous run that uploaded `aarch64-toolchain (SM8550)`; defaults to `26037562850`.

This builds the SM8550 base from an existing toolchain and uploads reusable `aarch64 (SM8550)` and `aarch64 build (SM8550)` artifacts. Use it to create a base checkpoint for the image-only lane without running the full toolchain workflow again.

### Image only

Workflow: `.github/workflows/build-image-only.yml`

Input:

- `base_run_id`: a previous full-build or prepare-base run that uploaded both `aarch64 (SM8550)` and `aarch64 build (SM8550)`.

This is the fastest lane for packaging-only changes: manifest verification, update tar/image packaging checks, seed layout checks, docs-adjacent CI guardrails, and other changes that should not require rebuilding the SM8550 base. It downloads the base/build artifacts, reruns the image/update packaging stage, generates a manifest, verifies payload integrity, and uploads `nix-on-rocks-sm8550-image-only-<run_id>`.

Do not use image-only for changes that alter packages, toolchain, kernel, guest source, rootfs seed pins, or host substrate scripts that must be rebuilt into `SYSTEM`; use continue-from-toolchain or prepare-base followed by image-only instead.

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

## Guardrails

Preflight and build lanes now run explicit lock/payload checks:

- `scripts/verify-sm8550-locks` confirms `guest.lock` and patched `package.mk` agree on guest rev, device, compatible string, seed archive, SHA256, and authenticated Nix-on-Rocks fetch URLs.
- `scripts/verify-sm8550-payloads` confirms the produced update tar carries `target/SYSTEM`, `target/KERNEL`, the expected `target/seed/<archive>`, matching seed SHA256, valid `.sha256` files, gzip integrity, and manifest seed records.

These checks are intentionally separate from the ROCKNIX build so artifacts downloaded after CI can be reverified locally before device install.
