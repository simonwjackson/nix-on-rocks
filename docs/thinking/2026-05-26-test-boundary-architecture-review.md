# Architecture/test boundary review

Scope: read-only audit of `flake.nix`, `guest/` modules/profiles/scripts, `packages/`, `devices/`, and `scripts/`, excluding `.worktrees/`, `github-artifacts/`, `work/rocknix/`, and `.git/`.

## Architecture overview

The documented architecture is a root flake composition surface over reusable packages, SoC-bound device data, and guest NixOS modules/profiles. The README states the dependency direction as `flake -> packages` and `flake -> devices`, with packages kept device-generic by injection from the flake (`README.md:39-61`). `guest/README.md` describes `guest/modules` and `guest/profiles` as the NixOS substrate contract, `packages/` as package/runtime helpers, and `guest/scripts/static-checks.sh` as the repo-local structural check suite (`guest/README.md:14-25`).

I found no TypeScript/Bun runtime surface in the audited tree, so the TS/Bun test-placement rule is not currently exercised.

## Findings

### HIGH — Flake contains an inline NixOS contract test instead of delegating to `nix/tests/*.nix`

- `flake.nix:213-243` defines `guest-input-boundary-contract` directly in the flake output using inline `assertContract`/`builtins.throw` assertions over evaluated NixOS configs.
- `flake.nix:98-107` also defines `baseConfiguration`/`devEnvConfiguration` primarily to feed that check.

This is a declarative Nix/build invariant, but the test logic lives inside the flake composition root. That makes `flake.nix` both the public API/composition surface and the test implementation, which is a boundary violation under the requested placement rule.

Recommendation: move the assertion body to a dedicated Nix test such as `nix/tests/guest-input-boundary-contract.nix`; keep `flake.nix` to wiring `checks.${system}.guest-input-boundary-contract = import ./nix/tests/... { ... };`.

### HIGH — `guest/scripts/static-checks.sh` impersonates Nix evaluator and package-contract tests

- `flake.nix:194-202` exposes `checks.static` by running `guest/scripts/static-checks.sh`.
- The script performs string-grep assertions over flake shape and public outputs (`guest/scripts/static-checks.sh:34-120`).
- It greps NixOS module semantics instead of evaluating module configs (`guest/scripts/static-checks.sh:181-260`, `295-343`, `362-417`).
- It greps package derivation internals and scripts for package contracts (`guest/scripts/static-checks.sh:519-615`).

These checks are mostly declarative Nix/module/package invariants, but they are implemented as shell text matching. That is brittle across refactors and lets a guest-local shell script enforce invariants owned by the flake, NixOS module system, package derivations, and package tests.

Recommendation: split the script by ownership:

- keep shell syntax/lint checks for shell launchers/scripts in a shell-oriented check;
- move NixOS config assertions to `nix/tests/*.nix` that evaluate `config` attrs;
- move package output/derivation contracts to package-level Nix tests or `passthru.tests`;
- keep `flake.nix` as a thin check aggregator.

### MEDIUM — Cemu package embeds characterization/build-contract checks in `installPhase`

- `packages/cemu/package.nix:213-228` validates installed runtime data and SoC settings while installing.
- `packages/cemu/package.nix:230-275` writes evidence and asserts Cubeb/Pulse/ALSA linkage/strings inside `installPhase`.

Some fail-fast file existence checks are defensible as install correctness, but the Cubeb/audio evidence checks are build characterization tests. Keeping them inside `installPhase` couples package construction to test policy and makes the test hard to reuse or scope independently.

Recommendation: keep only minimum install correctness guards in `installPhase`; move characterization checks to `installCheckPhase`, `passthru.tests.cemu-contract`, or `nix/tests/cemu-package-contract.nix`.

### MEDIUM — Steam package tests mix runtime shell contract, docs boundary checks, and built-output Nix package assertions

- `flake.nix:204-211` wires a flake check that runs `packages/steam/tests/steam-package-contract.sh` with `PACKAGE_OUT` set to the built package.
- `packages/steam/tests/steam-package-contract.sh:20-37` performs README/manifest/boundary grep checks.
- `packages/steam/tests/steam-package-contract.sh:55-76` asserts built package output and manifest contents.
- `guest/scripts/static-checks.sh:600-610` separately shells over the same Steam package scripts/tests, duplicating orchestration from the guest structural checker.

The runtime smoke tests under `packages/steam/tests/` are reasonable for shell helper behavior, but built derivation/output invariants belong in Nix tests or package `passthru.tests`. The current setup lets both flake checks and guest static checks orchestrate package tests, blurring layer ownership.

Recommendation: keep `steam-guest-*-smoke.sh` as package-local shell behavior tests; move built-output assertions to a Nix package contract test; remove package-test orchestration from `guest/scripts/static-checks.sh`.

### LOW — Guest static checks own host/product documentation contract assertions

- `guest/scripts/static-checks.sh:625-700` checks `docs/contracts/*` and host/Layer 14 wording, with comments noting those assertions were moved from a ROCKNIX host repo test.

Even though this block is gated by `DOCS_ROOT`, it makes the guest structural suite enforce host/product documentation contracts. That is a layering smell: guest validation becomes dependent on docs and host-layer policy outside the guest module/package boundary.

Recommendation: move these documentation contract checks to a docs/contract verification script or host-substrate check, then have CI call it separately from guest/module/package checks.

## Overall assessment

The production code boundaries are broadly documented, but the test architecture is not yet aligned with those boundaries. The main issue is concentration of heterogeneous assertions in `flake.nix` and `guest/scripts/static-checks.sh`. Establishing `nix/tests/*.nix` as the home for declarative Nix/build invariants would make the flake a thin public surface, keep guest shell checks focused on shell behavior, and reduce brittle text-grep coupling across layers.
