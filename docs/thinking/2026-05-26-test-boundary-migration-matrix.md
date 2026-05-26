# Test Boundary Migration Matrix

Date: 2026-05-26

Purpose: track every current check block before moving it. A block may move only after its destination is recorded here so negative safety assertions are not lost during the split from `guest/scripts/static-checks.sh` into Nix-owned checks, shell smoke, boundary lint, docs contracts, and artifact gates.

## Destination Keys

- **Nix eval**: evaluated flake/NixOS/module truth under `nix/tests/*.nix`.
- **Nix package-output**: built derivation `$out` / package evidence checks under `nix/tests/*.nix` or an explicit non-default package lane when expensive.
- **Shell smoke**: real shell syntax/runtime behavior against actual scripts and fixture directories.
- **Boundary lint**: source-policy anti-pattern checks that are not representable as evaluated Nix facts.
- **Docs contract**: safety-critical packaged/operator documentation checks.
- **Patch/lock guard**: mutable patched ROCKNIX tree or sourceable lock verification that remains pre-build shell.
- **Artifact verifier**: post-build image/tar/checksum/payload verification.
- **Manual/impure proof**: intentionally explicit proof not suitable for the default pure flake gate.
- **Retire**: remove with rationale.

## Matrix

| Current surface | Current block | Destination | Notes / preservation rule |
|---|---|---|---|
| `flake.nix` | Inline `guest-input-boundary-contract` | Nix eval | Move unchanged to `nix/tests/guest-input-boundary-contract.nix`; keep check attr name. |
| `guest/scripts/static-checks.sh` | Repo shape prerequisites (`flake.nix`, modules/profiles/packages dirs) | Boundary lint / shell smoke | Keep cheap presence checks in compatibility smoke or boundary lint until docs move. |
| `guest/scripts/static-checks.sh` | Flake output/package exposure greps | Nix eval | Replace with assertions over `self.packages`, `self.nixosModules`, `self.lib`, and device profile table. |
| `guest/scripts/static-checks.sh` | No Korri flake input/product composition greps | Nix eval + Boundary lint | Evaluated absence belongs in Nix where possible; source anti-pattern greps stay in boundary lint. |
| `guest/scripts/static-checks.sh` | Rootfs packaging facts (`authorized_keys`, `/usr/bin/nix`) | Nix eval / Nix package-output | Assert against rootfs packaging helper output contract where practical. |
| `guest/scripts/static-checks.sh` | `patches/rocknix/0006-*` Korri package defaults | Patch/lock guard | Keep with patch/product-payload verifiers for this refactor; pure Nix patch check deferred. |
| `guest/scripts/static-checks.sh` | `scripts/verify-korri-promotion-proof` presence/content | Manual/impure proof | Do not run in default flake gate; document as explicit proof unless redesigned. |
| `guest/scripts/static-checks.sh` | Product payload lock/render/verify presence and Korri characterization | Patch/lock guard + Boundary lint | Preserve with `scripts/verify-product-payload` and `scripts/tests/product-payload-contract.sh`; classify before CI rewrites. |
| `guest/scripts/static-checks.sh` | Retired rootfs seed workflow checks | Docs contract / Boundary lint | Keep only safety-critical retired workflow contract; avoid broad README prose policing. |
| `guest/scripts/static-checks.sh` | Guest baseline container/OpenSSH profile greps | Nix eval | Assert evaluated NixOS config and imports. |
| `guest/scripts/static-checks.sh` | Guest module/profile/package file presence | Boundary lint | Presence checks can remain cheap source lint until replaced by evaluated imports/package attrs. |
| `guest/scripts/static-checks.sh` | Display/udev/audio/input/session/network/lid/Steam module greps | Nix eval | Replace with evaluated `config.services`, `config.systemd.services`, tmpfiles, env, options, and generated config assertions. |
| `guest/scripts/static-checks.sh` | Negative runtime-dir/session anti-pattern greps | Nix eval + Boundary lint | Preserve all known-bad patterns; evaluate env/orderings where possible, lint source-only anti-patterns otherwise. |
| `guest/scripts/static-checks.sh` | Launcher file presence and `bash -n` | Shell smoke | Keep as shell smoke. |
| `guest/scripts/static-checks.sh` | Launcher policy greps (`CEMU_BIN`, portal bootstrap, storage adapter) | Boundary lint / Shell smoke | Keep source-policy checks only where runtime smoke is not available. |
| `guest/scripts/static-checks.sh` | Cemu package source/evidence greps | Nix package-output | Do not refactor package internals in first pass; assert built output/evidence through package-aware check if not too expensive for default gate. |
| `guest/scripts/static-checks.sh` | Steam package source/evidence greps | Nix package-output + Boundary lint | Built output/evidence moves to Nix; source anti-patterns move to boundary lint. |
| `guest/scripts/static-checks.sh` | ShellCheck of Steam package scripts | Shell smoke | Keep under `scripts/check-shell-smoke`. |
| `guest/scripts/static-checks.sh` | Dispatch of `packages/steam/tests/*.sh` | Shell smoke | Keep runtime-prep/run smokes; split mixed package contract. |
| `guest/scripts/static-checks.sh` | Steam package anti-pattern grep (`systemctl`, `swaymsg`, `/storage`) | Boundary lint | Keep separate from shell smoke. |
| `guest/scripts/static-checks.sh` | README package/credential wording | Retire / Docs contract | Retain only if classified safety-critical; otherwise review-only. |
| `guest/scripts/static-checks.sh` | Layer 6-14 contract doc wording | Docs contract | Move to `scripts/check-docs-contract` if docs are packaged/operator safety artifacts. |
| `packages/steam/tests/steam-package-contract.sh` | Script presence | Shell smoke / Nix package-output | Source presence can stay smoke; installed executables belong to Nix package-output. |
| `packages/steam/tests/steam-package-contract.sh` | README/manifest wording | Docs contract / Nix eval | Manifest/package evidence moves to Nix; README prose only if safety-critical. |
| `packages/steam/tests/steam-package-contract.sh` | Package script anti-pattern greps | Boundary lint | Keep as source-policy lint. |
| `packages/steam/tests/steam-package-contract.sh` | Missing env failures | Shell smoke | Keep; it executes real scripts. |
| `packages/steam/tests/steam-package-contract.sh` | `$PACKAGE_OUT/bin` and `$out/nix-support` checks | Nix package-output | Move to `nix/tests/steam-package-output-contract.nix`; keep `steam-package-contract` attr as compatibility if practical. |
| `packages/steam/tests/steam-guest-runtime-prep-smoke.sh` | Runtime mutation/repair fixture behavior | Shell smoke | Keep. |
| `packages/steam/tests/steam-guest-run-smoke.sh` | `--check`/`--run` fixture behavior | Shell smoke | Keep. |
| `scripts/verify-sm8550-contract` | Patched ROCKNIX tree/source contract | Patch/lock guard | Keep in pre-build shell for this refactor. |
| `scripts/verify-sm8550-locks` | `guest.lock` vs patched `package.mk` | Patch/lock guard | Keep fail-closed before Docker work. |
| `scripts/verify-product-payload` | Generic payload lock vs patched `package.mk` | Patch/lock guard | Keep fail-closed before Docker work. |
| `scripts/tests/product-payload-contract.sh` | Product payload renderer/verifier behavior | Shell smoke + Patch/lock guard | Keep with early pre-build guards; classify as shell behavior around sourceable locks. |
| `scripts/verify-sm8550-payloads` | Update tar/checksum/seed/manifest artifacts | Artifact verifier | Keep post-build only. |
| CI workflows | Patch/contract/lock/product-payload pre-build block | Patch/lock guard | Preserve order before image work. |
| CI workflows | `guest/scripts/static-checks.sh` in preflight | Split | Replace with Nix eval/package checks, shell smoke, boundary lint, and docs contract. |
| CI workflows | `bash -n scripts/*` | Shell smoke | Keep or fold into `scripts/check-shell-smoke`. |

## Non-Retirement Rule

No check block above may be deleted unless its row is updated with one of:

1. a replacement check path,
2. a destination command that still runs in CI or local verification, or
3. a `Retire` rationale explaining why the assertion is no longer product/build safety.
