# First slice: external patch-product proof

Goal: reproduce the accepted SM8550 build from a repo that does not vendor ROCKNIX source.

Acceptance for this slice:

- `scripts/fetch-upstream` checks out the pinned upstream SHA from `upstream.lock`.
- `scripts/apply-rocknix-patches` applies the patch queue from `patches/rocknix/series` to a clean upstream tree.
- `scripts/verify-sm8550-contract` passes in the patched tree.
- GitHub Actions can run `scripts/build-sm8550` and upload SM8550 artifacts plus `nix-on-rocks-build-manifest.md`.

The initial patch is intentionally monolithic. After the external builder proves itself, split it into reviewable topics: host substrate, guest seed staging, storage contract, CI/build lane, product docs.
