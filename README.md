# Nix-on-Rocks

Nix-on-Rocks is a patch-product builder for the SM8550 ROCKNIX thin-host + NixOS guest architecture.

The repo does **not** vendor ROCKNIX source. It pins upstream ROCKNIX, applies the Nix-on-Rocks patch queue, verifies the SM8550 storage/seed/recovery contract, and builds artifacts in GitHub Actions.

## Current proof target

- Device lane: `SM8550`
- Accepted device: `sobo` / Odin2Portal (`ayn,odin2portal`)
- Upstream source pin: see `upstream.lock`
- Guest seed pin: see `guest.lock`
- Patch queue: `patches/rocknix/series`

## Local quickstart

```sh
scripts/fetch-upstream
scripts/apply-rocknix-patches
scripts/verify-sm8550-contract
```

A full local build needs Docker and enough disk for a ROCKNIX build:

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
6. upload artifacts and a manifest containing upstream SHA, product SHA, patch-series hash, guest seed, and payload checksums.

## Naming note

The initial patch queue was extracted from the accepted `Nix-on-ROCK` branch. Some patched ROCKNIX docs/workflows still use the transitional `Nix-on-ROCK` vocabulary. The product repo and future user-facing surface are named **Nix-on-Rocks**.
