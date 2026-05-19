# First slice: external patch-product proof

Goal: reproduce the accepted SM8550 build from a repo that does not vendor ROCKNIX source.

Acceptance for this slice:

- `scripts/fetch-upstream` checks out the pinned upstream SHA from `upstream.lock`.
- `scripts/apply-rocknix-patches` applies the patch queue from `patches/rocknix/series` to a clean upstream tree.
- `scripts/verify-sm8550-contract` passes in the patched tree.
- GitHub Actions can run `scripts/build-sm8550` and upload SM8550 artifacts plus `nix-on-rocks-build-manifest.md`.

The initial patch queue is split into reviewable topics: developer environment, CI/product lane, SM8550 host config, network/recovery services, initramfs seed staging, guest substrate, and product docs/acceptance evidence.
