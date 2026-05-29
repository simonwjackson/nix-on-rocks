# Nix-on-Rocks

Nix-on-Rocks is a patch-product builder for the SM8550 ROCKNIX thin-host + NixOS guest architecture.

The repo does **not** vendor ROCKNIX source. It pins upstream ROCKNIX, applies the Nix-on-Rocks patch queue, verifies the SM8550 storage/seed/recovery contract, and builds artifacts in GitHub Actions.

## Current status

- Repo visibility: public.
- Accepted checkpoint: Phase 4 full-build release-path proof, sobo / Odin2Portal (`ayn,odin2portal`), 2026-05-27.
- Authoritative full-build run: `build-sm8550.yml` run `26539625977` on product SHA `ea836506446619b805acc7954a190fdee95be446`.
- Confidence gate: `continue-sm8550-from-toolchain.yml` run `26534216483` (same product SHA, same payload).
- Prior accepted Phase 5 checkpoint (image-only refresh, retained as historical): preflight `26148417386`, prepare-base `26148449934`, image-only `26152901081`.
- `HandsOnAcceptance`: `NotRun/Deferred`. `ReleasePublication`: `NotPublished/Deferred`.
- Accepted device deployment: `sobo` / Odin2Portal (`ayn,odin2portal`). Thor acceptance remains separate.
- Known follow-up: `docs/plans/2026-05-27-002-fix-main-space-post-update-boot-hint-plan.md` (stale `/storage/.boot.hint=UPDATE` on Layer 14 main-space boot; not a Phase 4 blocker).
- Legacy guest repo: `simonwjackson/rocknix-nix-guest` archived after source/docs migration.
- Upstream strategy: Nix-on-Rocks remains a patch-product queue; these changes are not planned as ROCKNIX upstream PRs.

## Current proof target

- Device lane: `SM8550`
- Accepted device: `sobo` / Odin2Portal (`ayn,odin2portal`)
- Upstream source pin: see `upstream.lock`
- Korri consumes nix-on-rocks as the SM8550 substrate; nix-on-rocks no longer imports Korri.
- Canonical guest product source: Korri branch `feat/korri-rocknix-inversion` (`.#korri-rocknix-rootfs-odin2portal`), verified on Fuji/native arm64.
- Host-packaged guest source: pinned Korri product tarball, extracting the flake root.
- Active product payload: see `product-payload.lock`; `scripts/apply-rocknix-patches` renders it into the patched ROCKNIX package-local `product-payload.env`, and `package.mk` consumes that staged env during Docker builds.
- Accepted guest seed pin: see `guest.lock`; old nix-on-rocks seeds are archived fallback evidence only.
- Patch queue: `patches/rocknix/series`
- Latest accepted Phase 4 release-path proof: `docs/acceptance/sm8550-product-payload-full-build-sobo-2026-05-27.md`
- Prior accepted Phase 5 CI/device proof: `docs/acceptance/sm8550-phase5-ci-and-device-acceptance-2026-05-20.md`

## Repository layout

After the monorepo merge (2026-05-22), the previously-separate `nix-sm8550`
package repo is absorbed into this one. See
[`docs/migration/2026-05-22-monorepo-merge-notes.md`](docs/migration/2026-05-22-monorepo-merge-notes.md)
for the migration story.

```
flake.nix              # single top-level flake (was guest/flake.nix)
packages/              # all reusable derivations (was guest/packages/)
  cemu/
  steam/
  inputplumber/
  moonlight-embedded/  # absorbed from nix-sm8550
devices/               # SoC-bound data (new layer; slot for sm8250/Retroid)
  sm8550/
    audio/ayn-odin2-ucm/
    cemu/settings.xml  # injected into packages/cemu via socSettings arg
guest/                 # NixOS integration (modules, profiles, launchers)
  modules/
  profiles/
  launchers/
  scripts/static-checks.sh
patches/rocknix/       # ROCKNIX patch queue (unchanged)
scripts/               # build/CI helpers (unchanged location)
```

Dependency direction is one-way: `flake → packages` and `flake → devices`.
Packages never `import` from `devices/`; SoC-bound data is injected via
callPackage arguments (e.g., cemu accepts `socSettings` and `socName`).

## Local quickstart

```sh
scripts/fetch-upstream
scripts/apply-rocknix-patches
scripts/verify-sm8550-contract
scripts/verify-sm8550-locks
scripts/verify-product-payload
scripts/tests/product-payload-contract.sh
```

Source and check-boundary validation runs from the repo root:

```sh
nix flake check --no-write-lock-file --print-build-logs
scripts/check-shell-smoke
scripts/check-boundary-lint
scripts/check-docs-contract
```

`nix/tests/*.nix` owns declarative Nix/build invariants: flake outputs,
package attributes, NixOS module evaluation, generated systemd/tmpfiles config,
and package-output contracts. Shell smoke owns real shell/runtime/artifact
behavior only. Source-policy and docs checks use explicit lint/docs commands;
they do not live in shell smoke. There is no TypeScript/Bun runtime surface in
this repo today, so there are no `*.test.ts` checks to run.

Retained manual/targeted builds and proofs:

```sh
# Per-product payload contract proof (replaces verify-korri-promotion-proof):
scripts/tests/product-payload-contract.sh --product odin2portal
scripts/tests/product-payload-contract.sh --product thor

nix build .#nixosConfigurations.rocknix-guest.config.system.build.toplevel
nix build .#nixosConfigurations.rocknix-guest-dev-env.config.system.build.toplevel
nix build .#cemu
nix build .#moonlight-embedded
nix build .#sm8550-ayn-odin2-ucm
```

A full local host build needs Docker and enough disk for a ROCKNIX build:

```sh
scripts/build-sm8550
```

## CI shape

`.github/workflows/build-sm8550.yml` performs the product flow:

1. checkout this repo;
2. clone pinned ROCKNIX into `work/rocknix`;
3. apply `patches/rocknix/series`;
4. run SM8550 contract checks, lock checks, `scripts/verify-product-payload`, and network-capable `scripts/verify-product-payload-fetches` in image-producing lanes;
5. build SM8550 with the patched ROCKNIX tree;
6. fetch the pinned Korri product tarball inside `rocknix-guest-substrate` and package its flake root for `korri-rocknix-kiosk-by-compatible` promotion;
7. keep `.github/workflows/build-rootfs-seed.yml` as a Retired legacy rootfs seed fallback notice; canonical rootfs artifacts are built by Korri;
8. upload artifacts and a manifest containing upstream SHA, product SHA, patch-series hash, product payload facts, guest seed, and payload checksums.

`product-payload.lock` is the image-build input for product/source/seed facts. `scripts/render-product-payload` maps the product-neutral `PRODUCT_*` fields to `PKG_NIX_GUEST_*`; `scripts/apply-rocknix-patches` stages that rendered environment into `work/rocknix/.../rocknix-guest-substrate/product-payload.env`; and patched `package.mk` sources only that package-local file. Direct edits under `work/rocknix` are generated scratch changes; update `patches/rocknix/0006-rocknix-guest-substrate.patch`, `guest.lock`, and/or `product-payload.lock` instead.

The product repo is public, but host packaging still pins the exact GitHub-generated tarball bytes by SHA256. If the fetch mode changes, verify the archive resolves to the same pinned commit before updating the checksum.

## Naming note

The initial patch queue was extracted from the accepted `Nix-on-ROCK` branch. Some patched ROCKNIX docs/workflows still use the transitional `Nix-on-ROCK` vocabulary. The product repo and future user-facing surface are named **Nix-on-Rocks**.
