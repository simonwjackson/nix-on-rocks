# Testing/check placement audit

Scope: tracked files only; excluded `.worktrees/`, `github-artifacts/`, `work/rocknix/`, and `.git/`.

## Violations

1. **Shell static check is asserting flake outputs and package exposure**
   - Paths/lines: `flake.nix:194-202` wires `guest/scripts/static-checks.sh` as the `checks.*.static` flake check; `guest/scripts/static-checks.sh:34-105` greps `flake.nix` for target system, host systems, package attrs, aliases, rootfs wiring, and device-profile exports.
   - Why misplaced: these are flake-output/package-attr/derivation-existence contracts. Under the rule, those belong in Nix checks/eval, not shell grep. The current test couples to source spelling (`default = cemu`, `cemu = cemu;`) instead of the public flake outputs.
   - Recommended destination: replace with Nix assertions under `checks.<system>` (or `lib` eval tests) that evaluate `self.packages.${system}`, `self.nixosModules`, `self.lib.deviceProfileByCompatible`, and rootfs derivations directly.

2. **Shell static check is asserting NixOS module/systemd wiring by source text**
   - Paths/lines: `guest/scripts/static-checks.sh:181-281`, `guest/scripts/static-checks.sh:295-342`, `guest/scripts/static-checks.sh:390-433`, and `guest/scripts/static-checks.sh:475-488` grep module/profile source for `services.udev`, `systemd.services.*`, tmpfiles rules, session runtime-dir ordering, network capabilities, and portal units.
   - Why misplaced: these are NixOS module evaluation/generated systemd wiring contracts. Shell grep can pass while the evaluated configuration changes via `mkForce`, imports, option defaults, or refactors.
   - Recommended destination: move to Nix eval checks like the existing `flake.nix:213-249` `guest-input-boundary-contract`, asserting against `nixosSystem.config` (`config.systemd.services`, `config.systemd.tmpfiles.rules`, `config.environment.etc`, service env, `wantedBy/after/wants`, etc.).

3. **Shell static check is asserting Nix package/native build contracts by source text**
   - Paths/lines: `guest/scripts/static-checks.sh:520-594` greps `packages/cemu/package.nix`, `packages/steam/package.nix`, and package scripts for wrapper internals, build evidence strings, installed helpers, FHS capsule definitions, and Steam module/package boundaries.
   - Why misplaced: Cemu/Steam package exposure, build evidence, installed binaries, wrapper behavior, and native build contracts are Nix/package checks. Grepping `package.nix` verifies implementation spelling rather than the built output contract.
   - Recommended destination: Nix package checks/passthru tests that build the package and inspect `$out` (`bin/*`, `nix-support/*`, evidence files, wrapper env) plus Nix eval assertions for module options. Keep only true shell runtime smoke that executes package scripts with fixture directories.

4. **Patch/promotion proof is a shell script around Nix eval and patch text**
   - Paths/lines: `guest/scripts/static-checks.sh:107-120`; `scripts/verify-korri-promotion-proof:23-75` greps the ROCKNIX substrate patch, resolves an external flake, and runs `nix eval` on `nixosConfigurations.*.config.system.build.toplevel` plus evaluated service settings.
   - Why misplaced: patch application and NixOS build-graph/module-eval contracts are explicitly Nix-check territory. The shell script also source-greps the patch instead of proving the patched tree/evaluated output.
   - Recommended destination: a Nix flake check/derivation that applies the patch queue to a pinned source (or consumes the patched source), then evaluates the Korri target drv path and relevant `config.services`/`config.systemd` values.

5. **ROCKNIX patch contract verification is CI shell instead of a patch-application/build-graph check**
   - Paths/lines: `.github/workflows/preflight.yml:19-23` invokes `scripts/apply-rocknix-patches`, `scripts/verify-sm8550-contract`, and `scripts/verify-sm8550-locks`; `scripts/verify-sm8550-contract:14-25` requires patched files, runs a patched-tree static shell script, and `git diff --check`.
   - Why misplaced: applying the patch series and proving the patched substrate contract is a patch-application/native build/build-graph contract. CI shell orchestration is fine for invoking checks, but the check itself should not live only as ad-hoc shell over a mutable checkout.
   - Recommended destination: expose a Nix check that fetches/prepares the ROCKNIX source, applies `patches/rocknix/series`, and runs the patch/build contract in a derivation. CI should call `nix flake check` for that, leaving shell only for artifact/runtime smoke.

6. **Documentation wording checks are mixed into runtime/static shell checks**
   - Paths/lines: `guest/scripts/static-checks.sh:123-132`, `guest/scripts/static-checks.sh:617-622`, and `guest/scripts/static-checks.sh:636-711` grep README/workflow/contract markdown for specific phrases.
   - Why misplaced: these are neither Nix flake/module/package contracts nor TS runtime/domain tests nor shell packaging/runtime smoke. They add brittle textual assertions to a check that otherwise claims to verify source/runtime contracts.
   - Recommended destination: move to a dedicated docs-contract linter/check if these exact docs are product artifacts, preferably keyed off headings/anchors or generated contract data; otherwise remove from automated tests and cover through documentation review.

7. **Steam package contract script mixes valid shell smoke with misplaced static/package assertions**
   - Paths/lines: `packages/steam/tests/steam-package-contract.sh:20-37` greps README/manifest and scans scripts for forbidden strings; `packages/steam/tests/steam-package-contract.sh:55-66` checks built package executable/evidence paths when `PACKAGE_OUT` is set; `flake.nix:204-212` runs this whole script as a flake check.
   - Why misplaced: the env/error checks and `steam-guest-run --check` execution are reasonable shell packaging/runtime smoke, but README/manifest wording, forbidden-string architecture checks, and built-output path existence are not shell runtime smoke. The built-output assertions are Nix package contracts; the README assertions are docs checks.
   - Recommended destination: split the script. Keep shell smoke for executing Steam helpers with fixture directories. Move `$out`/manifest/bin existence to a Nix package check/passthru test. Move README/manifest wording and architecture-boundary greps to a dedicated docs or boundary lint check.

## Not flagged

- `packages/steam/tests/steam-guest-runtime-prep-smoke.sh` and `packages/steam/tests/steam-guest-run-smoke.sh` are shell tests, but they exercise real package scripts against temporary fixture directories and assert observable runtime effects, so they fit the allowed shell packaging/runtime-smoke bucket.
- `scripts/verify-sm8550-payloads` inspects built image/update artifacts, checks checksums, and validates payload contents; this is packaging/artifact smoke outside TS/Nix runtime behavior.
