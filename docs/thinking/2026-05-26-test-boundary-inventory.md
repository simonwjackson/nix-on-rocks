# Code Context

## Files Retrieved
1. `flake.nix` (lines 180-248) - defines package outputs and flake `checks`.
2. `guest/scripts/static-checks.sh` (lines 1-120, 144-178, 181-280, 295-433, 435-615, 635-716) - large shell static/contract check, including package test invocations.
3. `packages/steam/tests/steam-package-contract.sh` (lines 1-79) - Steam package contract shell test.
4. `packages/steam/tests/steam-guest-runtime-prep-smoke.sh` (lines 1-70) - Steam runtime-prep shell smoke.
5. `packages/steam/tests/steam-guest-run-smoke.sh` (lines 1-74) - Steam run-capsule shell smoke.
6. `.github/workflows/preflight.yml` (lines 19-31) - PR/push preflight commands.
7. `.github/workflows/build-sm8550.yml` (lines 28-33, 70-75, 142-147, 235-240, 272-279) - manual full SM8550 build checks and payload verification.
8. `.github/workflows/build-image-only.yml` (lines 34-38, 76-80, 117-124) - image-only build checks and payload verification.
9. `.github/workflows/continue-sm8550-from-toolchain.yml` (lines 35-39, 77-81, 128-132) - continue-from-toolchain checks and payload verification.
10. `.github/workflows/prepare-sm8550-base.yml` (lines 35-39, 77-81, 108-112) - base artifact build checks.
11. `.github/workflows/build-rootfs-seed.yml` (lines 1-24) and `guest/.github/workflows/build-rootfs-seed.yml` (lines 1-24) - retired rootfs seed workflow stubs.
12. `scripts/verify-sm8550-contract` (lines 1-28) - patched ROCKNIX checkout contract check.
13. `scripts/verify-sm8550-locks` (lines 1-82) - guest lock/package alignment check.
14. `scripts/verify-sm8550-payloads` (lines 1-65) - SM8550 artifact/tarball payload verification.
15. `scripts/verify-korri-promotion-proof` (lines 1-80) - impure Korri promotion Nix evaluation proof.
16. `scripts/apply-rocknix-patches` (lines 1-38) - CI setup command before verify scripts.
17. `scripts/ci-build-stage` (lines 35-52, 55-138, 140-181) - CI build runner and duplicate payload verification logic.
18. `guest/justfile` (lines 4-11) - local helper commands.
19. `README.md` (lines 65-80), `guest/README.md` (lines 40-45, 107-120), `docs/acceptance/steam-runtime-capsule-refactor-sobo-2026-05-23.md` (lines 22-34) - documented manual verification commands.
20. `docs/contracts/layer14-soak-checklist.md` (lines 22-26, 38-50, 63-75) - manual on-device soak checklist; not an automated test file.

## Key Code

### TypeScript presence
No TypeScript or Node project files were found outside the excluded paths:

```text
find . ... -name '*.ts' -o -name '*.tsx' -o -name 'package.json' -o -name 'tsconfig*.json'
# no output
```

So there are currently no `*.test.ts` runtime behavior tests and no TS runtime surface to classify.

### Flake checks
`flake.nix` exposes three checks per host system:

```nix
# flake.nix lines 188-245
checks = forAllHostSystems (system: let pkgs = nixpkgs.legacyPackages.${system}; in {
  static = pkgs.runCommand "nix-on-rocks-guest-static-checks" { nativeBuildInputs = [ pkgs.shellcheck ]; } ''
    cd ${self}
    ${pkgs.bash}/bin/bash guest/scripts/static-checks.sh
    touch $out
  '';
  steam-package-contract = pkgs.runCommand "rocknix-steam-package-contract" { } ''
    cd ${self}
    PACKAGE_OUT=${self.packages.${system}.steam} \
      ${pkgs.bash}/bin/bash packages/steam/tests/steam-package-contract.sh
    touch $out
  '';
  guest-input-boundary-contract = ... builtins.toFile ... pkgs.runCommand ...;
});
```

The only Nix-evaluated invariant check is inline in `flake.nix` (`guest-input-boundary-contract`, lines 213-243). There is no `nix/tests/` directory.

### `guest/scripts/static-checks.sh`
This is the largest check surface. It:

- anchors `ROOT` at `guest/` and `REPO_ROOT` at repo root (lines 5-21);
- enforces flake/package exposure and Korri dependency inversion by grep (lines 23-120);
- verifies guest module/profile and package file presence (lines 144-178);
- asserts Nix module invariants for display/audio/input/session/network/steam via shell grep (lines 181-433);
- syntax-checks guest launchers with `bash -n` (lines 435-459);
- checks Cemu and Steam package contracts by grep (lines 521-599);
- runs ShellCheck for Steam scripts if available (lines 600-606);
- invokes all Steam package tests directly (lines 608-610);
- checks product contract docs text if docs are present (lines 635-716).

Key invocation block:

```bash
# guest/scripts/static-checks.sh lines 600-610
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck "$REPO_ROOT/packages/steam/scripts/steam-arm64-bootstrap" \
    "$REPO_ROOT/packages/steam/scripts/steam-arm64-seed" \
    "$REPO_ROOT/packages/steam/scripts/steam-guest-native" \
    "$REPO_ROOT/packages/steam/scripts/steam-guest-runtime-prep" \
    "$REPO_ROOT/packages/steam/scripts/steam-guest-run"
fi

bash "$REPO_ROOT/packages/steam/tests/steam-package-contract.sh"
bash "$REPO_ROOT/packages/steam/tests/steam-guest-runtime-prep-smoke.sh"
bash "$REPO_ROOT/packages/steam/tests/steam-guest-run-smoke.sh"
```

### `packages/*/tests`
Only one package has a `tests` directory:

```text
packages/steam/tests/steam-package-contract.sh
packages/steam/tests/steam-guest-run-smoke.sh
packages/steam/tests/steam-guest-runtime-prep-smoke.sh
```

`steam-package-contract.sh` checks script presence, README/manifest evidence, boundary greps against `systemctl|swaymsg|gamescope|services.korri`, required-env failures, and optionally built package contents when `PACKAGE_OUT` is set (lines 11-77).

`steam-guest-runtime-prep-smoke.sh` builds a temp Steam tree and verifies runtime mutation/repair behavior (`srt-bwrap`, font UUID, Proton shebang, Wine restore, python symlinks) against the real shell script (lines 17-68).

`steam-guest-run-smoke.sh` builds temp Steam client and runtime-prep hooks, verifies `--check` error paths and non-mutation, then verifies `--run` applies prep and execs the client with pressure-vessel input paths (lines 36-72).

### CI workflows
- `preflight.yml` runs on PR/push to main and does: `scripts/apply-rocknix-patches`, `scripts/verify-sm8550-contract`, `scripts/verify-sm8550-locks`, `bash -n scripts/*`, and `guest/scripts/static-checks.sh` (lines 19-31). It does **not** run `nix flake check` directly.
- Build workflows repeatedly run `apply-rocknix-patches`, `verify-sm8550-contract`, and `verify-sm8550-locks` before ROCKNIX build stages: `build-sm8550.yml` lines 28-33, 70-75, 142-147, 235-240; `build-image-only.yml` lines 34-38 and 76-80; `continue-sm8550-from-toolchain.yml` lines 35-39 and 77-81; `prepare-sm8550-base.yml` lines 35-39 and 77-81.
- Payload verification is shell-based after image/manifest stages: `build-sm8550.yml` lines 272-279, `build-image-only.yml` lines 117-124, `continue-sm8550-from-toolchain.yml` lines 128-132.
- Rootfs seed workflows at `.github/workflows/build-rootfs-seed.yml` and `guest/.github/workflows/build-rootfs-seed.yml` are intentionally retired and always `exit 1` after an explanatory message (lines 1-24 in both).

### Related verify scripts
- `scripts/verify-sm8550-contract` requires a patched `work/rocknix` checkout, checks expected patched files, runs ROCKNIX's `guest-substrate-static-checks.sh`, and `git diff --check` (lines 7-26).
- `scripts/verify-sm8550-locks` sources `guest.lock` and patched ROCKNIX `package.mk`, then asserts package/revision/seed alignment and retired URL absence (lines 8-82).
- `scripts/verify-sm8550-payloads` validates the generated target directory, tar contents (`SYSTEM`, `KERNEL`, seed), seed SHA256, gzip integrity, checksum files, and optional manifest evidence (lines 15-65).
- `scripts/verify-korri-promotion-proof` checks the patch does not hard-code a retired target, resolves Korri through `nix flake metadata`, and performs impure `nix eval` assertions for the selected compatible device (lines 7-80). It is documented in `README.md` lines 73-80 but not wired into CI or flake checks except for static greps in `guest/scripts/static-checks.sh` lines 117-120.

## Architecture

The current check architecture is shell-heavy:

1. `flake.nix` wraps `guest/scripts/static-checks.sh` as `checks.<system>.static` and wraps `packages/steam/tests/steam-package-contract.sh` as `checks.<system>.steam-package-contract`.
2. `guest/scripts/static-checks.sh` is both a static grep contract suite and a dispatcher for package shell tests.
3. CI preflight and build workflows rely on shell verify scripts plus the static check script; they do not use `nix flake check` as the primary entrypoint.
4. Real shell/runtime behavior tests exist for Steam package scripts and are correctly run directly and through `static`.
5. Nix module invariants are mostly asserted indirectly by grep in shell, with one inline Nix flake check for guest input boundary evaluation.

## Inventory Map

| Area | Files / commands | Classification today | Policy fit |
|---|---|---|---|
| Flake checks | `flake.nix` lines 188-245; build with `nix build .#checks.<system>.static`, `.#checks.<system>.steam-package-contract`, `.#checks.<system>.guest-input-boundary-contract` | Nix check wrappers around shell plus one inline Nix eval contract | Partial. Nix-owned invariant exists, but inline not `nix/tests/*.nix`; most invariants are shell grep. |
| Nix test files | none; no `nix/tests/` dir | Missing | Mismatch with proposed `nix/tests/*.nix` policy. |
| TS tests | none; no TS/Node files | Not applicable | No TS exists, so no `*.test.ts` inventory. |
| Guest static checks | `guest/scripts/static-checks.sh` lines 1-716; command `guest/scripts/static-checks.sh` | Monolithic shell contract/static suite | Mismatch for Nix-owned invariants; OK only for shell syntax/shell script smoke portions. |
| Steam package tests | `packages/steam/tests/*.sh` | Shell contract/smoke tests | Runtime-prep/run smokes fit. Package contract is mixed static/package invariant; consider moving package-output invariants to Nix check if policy is adopted. |
| CI preflight | `.github/workflows/preflight.yml` lines 19-31 | Patch contract, shell syntax, guest static checks | Does not run `nix flake check`; policy would likely prefer flake checks as canonical invariant gate. |
| CI image/build workflows | `.github/workflows/build-*.yml`, `continue-*`, `prepare-*` listed above | Real ROCKNIX build/payload verification | Payload shell checks are appropriate real artifact checks; repeated static/lock checks are shell invariant checks. |
| Manual docs | README/guest README/acceptance docs listed above | Manual command documentation | Documents direct checks/builds; acceptance doc includes flake check builds for Steam. |
| Soak checklist | `docs/contracts/layer14-soak-checklist.md` lines 22-75 | Manual hardware/guest runtime checklist | Fits shell/guest runtime behavior; not automated. |

## Possible Mismatches vs Proposed Policy

1. **Nix-owned invariants are mostly shell greps.** Examples: `guest/scripts/static-checks.sh` asserts flake shape, Nix module options, services, profiles, package derivation text, and docs by `grep` (lines 33-120, 181-433, 521-599, 635-716). Proposed policy would move many of these to `nix/tests/*.nix` and expose them through flake checks.
2. **No `nix/tests/*.nix` structure.** The only Nix-evaluated contract (`guest-input-boundary-contract`) is inline in `flake.nix` lines 213-243.
3. **CI does not make flake checks the main gate.** `preflight.yml` calls shell scripts directly (lines 19-31). If policy is adopted, CI probably needs `nix flake check` or explicit `nix build .#checks...` commands.
4. **`static-checks.sh` mixes layers.** It combines repo shape, Nix module contracts, shell syntax checks, package tests, and docs contract text in one shell file. This makes policy-aligned ownership hard to see.
5. **Steam tests are partly aligned.** `steam-guest-runtime-prep-smoke.sh` and `steam-guest-run-smoke.sh` are real shell behavior tests and fit the shell-smoke policy. `steam-package-contract.sh` mixes shell behavior with README/manifest/built-package contract checks.
6. **Payload verification is shell but likely justified.** `scripts/verify-sm8550-payloads` inspects real tar/gzip/checksum artifacts (lines 15-65), which is real CI artifact behavior rather than a Nix module invariant.
7. **Promotion proof is not in CI/flake checks.** `scripts/verify-korri-promotion-proof` performs meaningful Nix eval proof (lines 37-80), but current automation only greps for its presence/output string in static checks (static lines 117-120). It may need an explicit check, but it is impure/external and may need a separate policy decision.

## Start Here
Open `flake.nix` lines 188-245 first. It is the canonical flake check entrypoint and shows which shell checks are currently exposed as Nix checks. Then open `guest/scripts/static-checks.sh` lines 1-716 to decide which assertions should move into `nix/tests/*.nix` versus remain shell smoke.