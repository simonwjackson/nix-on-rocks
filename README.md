# Nix-on-Rocks

Nix-on-Rocks is a patch-product builder for the SM8550 ROCKNIX thin-host + NixOS guest architecture.

The repo does **not** vendor ROCKNIX source. It pins upstream ROCKNIX, applies the Nix-on-Rocks patch queue, verifies the SM8550 storage/seed/recovery contract, and builds artifacts in GitHub Actions.

## Current status

- Repo visibility: public.
- Accepted checkpoint: `sm8550-phase5-accepted-20260520`.
- Release: `SM8550 Phase 5 Accepted (2026-05-20)`.
- Accepted CI lanes:
  - preflight `26148417386`;
  - prepare-base `26148449934`;
  - image-only `26152901081`.
- Accepted device deployment: `sobo` / Odin2Portal (`ayn,odin2portal`).
- Legacy guest repo: `simonwjackson/rocknix-nix-guest` archived after source/docs migration.
- Upstream strategy: Nix-on-Rocks remains a patch-product queue; these changes are not planned as ROCKNIX upstream PRs.

## Current proof target

- Device lane: `SM8550`
- Accepted device: `sobo` / Odin2Portal (`ayn,odin2portal`)
- Upstream source pin: see `upstream.lock`
- Korri consumes nix-on-rocks as the SM8550 substrate; nix-on-rocks no longer imports Korri.
- Canonical guest product source: Korri branch `feat/korri-rocknix-inversion` (`.#korri-rocknix-rootfs-odin2portal`), verified on Fuji/native arm64.
- Host-packaged guest source: pinned Korri product tarball, extracting the flake root.
- Product payload mirror: see `product-payload.lock`; Phase 1 characterizes the same Korri tarball, build target, and rootfs seed that patched `package.mk` still consumes.
- Accepted guest seed pin: see `guest.lock`; old nix-on-rocks seeds are archived fallback evidence only.
- Patch queue: `patches/rocknix/series`
- Latest accepted Phase 5 CI/device proof: `docs/acceptance/sm8550-phase5-ci-and-device-acceptance-2026-05-20.md`

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
scripts/verify-korri-promotion-proof
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
4. run SM8550 contract checks, lock checks, and `scripts/verify-product-payload`;
5. build SM8550 with the patched ROCKNIX tree;
6. fetch the pinned Korri product tarball inside `rocknix-guest-substrate` and package its flake root for `korri-rocknix-kiosk-by-compatible` promotion;
7. keep `.github/workflows/build-rootfs-seed.yml` as a Retired legacy rootfs seed fallback notice; canonical rootfs artifacts are built by Korri;
8. upload artifacts and a manifest containing upstream SHA, product SHA, patch-series hash, guest seed, and payload checksums.

`product-payload.lock` is not an image-build input yet. It is a pre-build characterization contract: `scripts/render-product-payload` maps the product-neutral `PRODUCT_*` fields to the current `PKG_NIX_GUEST_*` package variables, and `scripts/verify-product-payload` compares that rendered environment to the patched `work/rocknix/.../package.mk`. Direct edits under `work/rocknix` are generated scratch changes; update `patches/rocknix/0006-rocknix-guest-substrate.patch`, `guest.lock`, and/or `product-payload.lock` instead.

The product repo is public, but host packaging still pins the exact GitHub-generated tarball bytes by SHA256. If the fetch mode changes, verify the archive resolves to the same pinned commit before updating the checksum.

## Naming note

The initial patch queue was extracted from the accepted `Nix-on-ROCK` branch. Some patched ROCKNIX docs/workflows still use the transitional `Nix-on-ROCK` vocabulary. The product repo and future user-facing surface are named **Nix-on-Rocks**.
