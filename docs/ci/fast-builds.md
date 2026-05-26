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

Latest accepted Phase 5 checkpoints:

- prepare-base run `26148449934` rebuilt reusable SM8550 base artifacts from toolchain run `26037562850`.
- image-only run `26152901081` consumed base run `26148449934`, verified payloads, and produced the update installed on `sobo`.

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

Do not use image-only for changes that alter packages, toolchain, kernel, guest source, `product-payload.lock`, rootfs seed pins, or host substrate scripts that must be rebuilt into `SYSTEM`; use continue-from-toolchain or prepare-base followed by image-only instead.

Current accepted image-only proof:

- base run: `26148449934`
- image-only run: `26152901081`
- artifact: `nix-on-rocks-sm8550-image-only-26152901081`
- update tar: `ROCKNIX-SM8550.aarch64-20260520.tar`
- update tar SHA256: `c470e6b403a50be8dc469a7df8ee9a1221e7222578e1fc21834b55f6170e181f`
- device deployment: accepted on `sobo` / `ayn,odin2portal`

If the product tarball fetch mode changes (for example private/authenticated API tarball to public API tarball), expect the GitHub-generated tarball checksum to change and update `PKG_NIX_GUEST_SHA256` only after verifying the fetched archive is still the pinned revision.

## Cheap product-payload contract verification

`product-payload.lock` is a Phase 1 characterization seam, not an active image-build input. It describes the current locked Korri product source, promotion target, and rootfs seed with sourceable `PRODUCT_*` shell assignments. `scripts/render-product-payload` maps those fields to the current `PKG_NIX_GUEST_*` package variables, and `scripts/verify-product-payload` compares the rendered values to the patched ROCKNIX `package.mk` after `scripts/apply-rocknix-patches`.

Phase 1 validation is intentionally cheap: patch application, `scripts/verify-sm8550-contract`, `scripts/verify-sm8550-locks`, `scripts/verify-product-payload`, `scripts/tests/product-payload-contract.sh`, `nix flake check --no-write-lock-file --print-build-logs`, `scripts/check-shell-smoke`, `scripts/check-boundary-lint`, and `scripts/check-docs-contract`. Do not dispatch full/image-only SM8550 workflows just to prove the generic mirror; later phases own image-build validation after the generic seam becomes a build input.

Check ownership is split by where the truth lives. `nix/tests/*.nix` covers flake outputs, package attributes, NixOS module evaluation, generated systemd/tmpfiles config, and package-output contracts. Shell smoke covers real shell/runtime behavior and mutable artifacts. Source-policy and safety-doc assertions live in named lint/docs commands instead of the guest smoke path.

`work/rocknix` is generated scratch state. Direct edits there are not durable; update this repo's lock files and patch queue instead.

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
- `scripts/verify-product-payload` confirms `product-payload.lock` renders to every current top-level `PKG_NIX_GUEST_*` assignment in patched `package.mk`, including derived authority/name URL values, the blank single seed URL, and the ordered split seed URL list.
- `scripts/verify-sm8550-payloads` confirms the produced update tar carries `target/SYSTEM`, `target/KERNEL`, the expected `target/seed/<archive>`, matching seed SHA256, valid `.sha256` files, gzip integrity, and manifest seed records.

These checks are intentionally separate from the ROCKNIX build so artifacts downloaded after CI can be reverified locally before device install.
