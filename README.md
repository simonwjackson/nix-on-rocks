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
- Guest source: `guest/` (`.#rootfs-thor`, `.#rootfs-odin2portal`)
- Host-packaged guest source: pinned Nix-on-Rocks product tarball, extracting `guest/`
- Accepted guest seed pin: see `guest.lock`
- Patch queue: `patches/rocknix/series`
- Latest accepted Phase 5 CI/device proof: `docs/acceptance/sm8550-phase5-ci-and-device-acceptance-2026-05-20.md`

## Local quickstart

```sh
scripts/fetch-upstream
scripts/apply-rocknix-patches
scripts/verify-sm8550-contract
```

Guest rootfs builds run from the in-repo guest flake:

```sh
cd guest
./scripts/static-checks.sh
nix build .#rootfs-thor
nix build .#rootfs-odin2portal
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
4. run SM8550 contract checks;
5. build SM8550 with the patched ROCKNIX tree;
6. fetch the pinned Nix-on-Rocks product tarball inside `rocknix-guest-substrate` and package its `guest/` subtree;
7. upload artifacts and a manifest containing upstream SHA, product SHA, patch-series hash, guest seed, and payload checksums.

The product repo is public, but host packaging still pins the exact GitHub-generated tarball bytes by SHA256. If the fetch mode changes, verify the archive resolves to the same pinned commit before updating the checksum.

## Naming note

The initial patch queue was extracted from the accepted `Nix-on-ROCK` branch. Some patched ROCKNIX docs/workflows still use the transitional `Nix-on-ROCK` vocabulary. The product repo and future user-facing surface are named **Nix-on-Rocks**.
