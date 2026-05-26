# Repository Research Summary — Test/Check Boundary Refactor

Research date: 2026-05-26
Focus: align `nix-on-rocks` check architecture with the policy that declarative Nix/build contracts live under `nix/tests/*.nix`, TypeScript/Bun tests cover only TS runtime/domain contracts, and shell tests remain only for real shell/runtime/artifact smoke.

## Technology & Infrastructure

- **Primary languages:** Nix and Bash/Shell. No `package.json`, `tsconfig.json`, Bun lockfile, `*.ts`, or `*.tsx` files were found outside excluded generated/worktree paths, so there is currently no TypeScript/Bun runtime surface to test.
- **Nix stack:** root `flake.nix` pins `nixpkgs` to `github:NixOS/nixpkgs/nixos-25.11` and a narrow `nixpkgs-sdl2-classic` input to `nixos-24.11` for Cemu SDL2 compatibility. Host systems are `x86_64-linux` and `aarch64-linux`; target guest system is `aarch64-linux`.
- **Deployment/build model:** patch-product builder for SM8550 ROCKNIX. CI applies `patches/rocknix/series` into `work/rocknix`, builds a Docker/ROCKNIX image, builds toolchain/base/image stages, verifies payload artifacts, and uploads SM8550 artifacts.
- **API/data surface:** no HTTP/gRPC/GraphQL API or database layer detected. The primary contracts are flake outputs, NixOS module evaluation, package derivations, generated systemd/tmpfiles configuration, ROCKNIX patch application, and image/update artifact contents.
- **Module organization:**
  - `flake.nix` is the single public flake/composition root.
  - `packages/` contains reusable derivations (`cemu`, `steam`, `inputplumber`, `moonlight-embedded`).
  - `devices/sm8550/` contains SoC-bound data injected into packages by the flake.
  - `guest/modules/` contains reusable NixOS substrate modules.
  - `guest/profiles/` composes modules into substrate/dev/fallback profiles and per-device overrides.
  - `patches/rocknix/` owns the ROCKNIX patch queue.
  - `scripts/` owns CI/build/artifact helper entrypoints.
- **Monorepo shape:** single-flake monorepo after the 2026-05-22 merge. There are no language workspace manifests; the documented boundary is architectural rather than tool-workspace based: `flake → packages` and `flake → devices`, never `packages → devices`.

## Architecture & Structure

### Canonical architecture files

- `README.md` describes the project as an SM8550 ROCKNIX thin-host + NixOS guest patch-product builder and documents the top-level layout.
- `guest/README.md` describes the guest substrate surface: NixOS modules/profiles, package derivations, launch adapters, and the current `guest/scripts/static-checks.sh` structural suite.
- `devices/README.md` and `devices/sm8550/README.md` define the `devices/<soc>/` layer and the one-way dependency rule: packages receive device data by `callPackage` arguments from the flake.
- `docs/contracts/layer14-main-space-contract.md` is the durable host/guest/product boundary doc: ROCKNIX owns host boot/update/recovery and nspawn substrate; nix-on-rocks owns SM8550 substrate facts and package helpers; Korri owns downstream appliance composition/rootfs publication.
- `docs/migration/2026-05-22-monorepo-merge-notes.md` records the merge and confirms current top-level package/device shape.
- `docs/plans/2026-05-26-001-refactor-product-payload-contract-plan.md` shows current planning conventions and recent context for generic product-payload checks.

### Important design decisions for this refactor

- **Production boundaries are documented better than test boundaries.** Code/docs consistently distinguish `packages/`, `devices/`, guest modules/profiles, host patch substrate, and downstream Korri product ownership. Current checks do not respect the same boundaries.
- **`flake.nix` is doing too much.** It defines package sets, NixOS configurations, helper library outputs, rootfs packaging, and inline check logic (`guest-input-boundary-contract`). The refactor should keep it as a thin aggregator and move test bodies to `nix/tests/*.nix`.
- **`guest/scripts/static-checks.sh` is the main boundary violation.** It currently checks flake shape, package exposure, NixOS module semantics, systemd ordering, package internals, docs wording, shell syntax, and Steam tests in one shell script.
- **Existing good seam:** the inline `guest-input-boundary-contract` already evaluates `nixosSystem.config` and asserts real NixOS config values. It is the right style, but the wrong location; move that pattern into `nix/tests/guest-input-boundary-contract.nix`.
- **Shell remains appropriate for real artifacts/runtime:** `scripts/verify-sm8550-payloads` inspects real update/image artifacts and checksums; Steam smoke tests execute real shell helpers against temp fixture directories. These should not be rewritten into brittle Nix eval tests unless the contract is declarative/package-output owned.

## Issue Conventions

- GitHub API returned **no issues** for `simonwjackson/nix-on-rocks` at research time, so there are no observed issue-body patterns or bot interactions to copy.
- Repository labels are only GitHub defaults: `bug`, `documentation`, `duplicate`, `enhancement`, `good first issue`, `help wanted`, `invalid`, `question`, `wontfix`.
- No `.github/ISSUE_TEMPLATE/` directory was found.

## Documentation Insights

- No `CONTRIBUTING.md`, `ARCHITECTURE.md`, `AGENTS.md`, or `CLAUDE.md` is present in the tracked repo. `AGENTS.local.md` is untracked/local and only says not to use traditional Git branching; use worktrees.
- Planning docs use date-prefixed files under `docs/plans/` with YAML front matter (`title`, `type`, `status`, `date`) and sections such as Summary, Problem Frame, Requirements, Scope Boundaries, Context & Research, Technical Decisions, Open Questions, High-Level Technical Design, Implementation Units, and Verification.
- Migration/acceptance docs capture durable evidence and commands. Recent docs are dated 2026-05-20 through 2026-05-26, so the documentation is active and current.
- Validation docs still point users at `guest/scripts/static-checks.sh`, explicit `nix build` commands, and shell verifiers. The refactor should update docs after moving check ownership.
- There is no formal contribution/review checklist; use existing plan format and acceptance docs as the project convention.

## Templates Found

- No issue templates, pull request template, RFC template, or `.github` templates were found.
- `.github/` currently contains only workflow YAML files.

## Implementation Patterns

### Nix patterns

- `flake.nix` exposes outputs for `packages`, `nixosModules`, `lib`, `nixosConfigurations`, `checks`, and `formatter`.
- Current checks use `pkgs.runCommand` and, for the inline NixOS evaluation check, Nix-time assertions via `builtins.throw` and `builtins.toFile` before a trivial derivation copies/touches output.
- NixOS modules use `options.rocknix.*` namespaces, `lib.mkOption`, typed options, profile composition via `imports`, and generated systemd services/tmpfiles as the main contract surface.
- Package manifests (`packages/cemu/manifest.nix`, `packages/steam/manifest.nix`) are data-only and used to keep source/provenance/resource expectations close to packages.
- Device-specific data is injected from `flake.nix` into packages (`socSettings`, `socName`) rather than imported from package derivations.

### Bash patterns

- Scripts consistently use `#!/usr/bin/env bash` and `set -euo pipefail`.
- Scripts derive `repo_root` from `dirname "$0"` and allow `NIX_ON_ROCKS_WORKDIR` for the ROCKNIX worktree.
- Sourceable shell lock files (`guest.lock`, `upstream.lock`) are used for pins.
- Verifiers use small `fail`, `require_equal`, and `require_nonempty` helpers with explicit error messages.
- CI entrypoints are direct shell commands rather than `nix flake check` as the canonical preflight.

## Current Test/Check Inventory and Destinations

| Current check area | Evidence | Policy-aligned destination |
|---|---|---|
| Flake output shape, host systems, package attrs, aliases, `nixosModules`, `lib.deviceProfileByCompatible` | `guest/scripts/static-checks.sh` greps `flake.nix`; `flake.nix` exposes outputs | `nix/tests/flake-surface-contract.nix` evaluating `self.packages.${system}`, `self.nixosModules`, `self.lib`, and package drv paths directly |
| Existing evaluated input boundary | inline `flake.nix` `guest-input-boundary-contract` | Move body to `nix/tests/guest-input-boundary-contract.nix`; keep `flake.nix` as wiring only |
| NixOS module/systemd/tmpfiles/session/audio/input/network/lid invariants | `guest/scripts/static-checks.sh` greps `guest/modules/*.nix` and profiles | `nix/tests/guest-module-contract.nix`, `nix/tests/session-systemd-contract.nix`, `nix/tests/audio-input-contract.nix`, etc., asserting against evaluated `config.systemd.services`, `config.systemd.tmpfiles.rules`, `config.services.*`, `config.environment.*` |
| Generated Sway/systemd config strings | `guest/scripts/static-checks.sh` greps profile source | Nix tests over evaluated config values such as `programs.sway.config`, service scripts/env/orderings, and generated unit attrs |
| Package derivation existence and output paths | shell greps and `steam-package-contract.sh` with `PACKAGE_OUT` | Nix package-output checks under `nix/tests/*-package-contract.nix` or package `passthru.tests`, inspecting built `$out/bin`, `$out/share`, and `$out/nix-support` |
| Cemu build evidence/native build characterization | `packages/cemu/package.nix` install-phase assertions and static greps | Keep minimal install correctness in derivation; move reusable characterization to `installCheckPhase`, `passthru.tests.cemu-contract`, or `nix/tests/cemu-package-contract.nix` |
| Steam built package executable/evidence assertions | `packages/steam/tests/steam-package-contract.sh` when `PACKAGE_OUT` is set | `nix/tests/steam-package-output-contract.nix` or `passthru.tests.steam-package-contract` |
| Steam helper missing-env and real script behavior | `packages/steam/tests/steam-guest-runtime-prep-smoke.sh`, `steam-guest-run-smoke.sh`, part of `steam-package-contract.sh` | Keep as shell smoke tests, but split static/docs/package-output parts out of `steam-package-contract.sh` |
| Shell syntax/ShellCheck | `.github/workflows/preflight.yml`, `guest/scripts/static-checks.sh` | Keep shell-oriented check, e.g. `scripts/check-shell-syntax` or `nix/tests/shell-smoke.nix` wrapper that runs only Bash syntax/ShellCheck and real shell smokes |
| ROCKNIX patch application and patched-tree contract | `scripts/apply-rocknix-patches`, `scripts/verify-sm8550-contract`, CI direct calls | Nix check/derivation such as `nix/tests/rocknix-patch-contract.nix` that fetches/prepares pinned upstream, applies `patches/rocknix/series`, and runs patched-tree contract checks in the store. Shell can remain orchestration for local mutable worktrees. |
| `guest.lock`/patched `package.mk` alignment | `scripts/verify-sm8550-locks` | Eventually a Nix check for lock/package identity if the source data can be read by Nix; short-term acceptable as pre-build shell guard only while patch tree is mutable. Do not put new broad contracts here. |
| Korri promotion proof | `scripts/verify-korri-promotion-proof` does shell + impure `nix eval` | Separate policy decision: if kept automated, make it an explicit Nix/eval check or a named impure/manual proof, not a grep inside guest static checks |
| Docs wording assertions | `guest/scripts/static-checks.sh` docs block | Dedicated docs-contract checker only if these exact docs are product artifacts; otherwise remove from automated tests and cover by review |
| SM8550 payload/image artifact verification | `scripts/verify-sm8550-payloads`, `scripts/ci-build-stage` duplicate verifier | Keep shell artifact smoke. It checks real tar/gzip/checksum/manifest/image payload behavior after image build. |
| TypeScript/Bun runtime/domain tests | none | No destination needed until a TS runtime exists; do not add TS/Bun test tooling for this refactor. |

## Recommended Refactor Approach

1. **Create the Nix test home first.** Add `nix/tests/` with a tiny shared helper file only if it reduces repetition. Avoid a large generic test framework; the project’s existing `assertContract` pattern is sufficient.
2. **Move the inline check before broad rewrites.** Extract `guest-input-boundary-contract` from `flake.nix` into `nix/tests/guest-input-boundary-contract.nix`. Wire it back through `checks.${system}` with the same name. This proves the new destination without changing behavior.
3. **Split `static-checks.sh` by ownership.** Move flake/package/module assertions in small groups to Nix tests. Leave behind only shell syntax, ShellCheck, and real shell smokes.
4. **Prefer evaluated contracts over source spelling.** Assert public values (`self.packages.${system}.cemu.drvPath`, `config.systemd.services.inputplumber.environment.HIDE_DEVICES_FROM_ROOT`, tmpfiles rule membership) rather than grepping for `cemu = cemu;` or exact source fragments.
5. **Move package-output contracts to package-aware Nix checks.** For Steam, Nix should build/inspect the package output; shell tests should execute the real helpers with temp dirs. For Cemu, keep necessary build fail-fast checks but expose characterization/evidence checks independently.
6. **Make CI call the canonical check surface.** Preflight should move toward `nix flake check --no-write-lock-file --print-build-logs` plus a clearly named shell smoke command. Build workflows can still run shell orchestration for Docker/ROCKNIX stages and artifact verification.
7. **Keep artifact smoke in shell.** Do not force tar/gzip/checksum/image inspection into Nix if it depends on real CI artifacts from Docker/ROCKNIX builds.
8. **Update docs last.** Once check names settle, update `README.md`, `guest/README.md`, and any active plan/acceptance docs that still direct contributors to the old monolithic static check.

## Suggested `nix/tests/` File Map

- `nix/tests/flake-surface-contract.nix` — host systems, package attrs/aliases, `nixosModules`, `lib` helper exposure, device-compatible table.
- `nix/tests/guest-input-boundary-contract.nix` — extracted current inline evaluated contract.
- `nix/tests/guest-profile-contract.nix` — container baseline, profile imports, rootfs package wiring, no Korri product imports.
- `nix/tests/main-space-systemd-contract.nix` — generated service ordering, runtime-dir anchor, session D-Bus, portal bootstrap, Sway service.
- `nix/tests/audio-input-systemd-contract.nix` — PipeWire/WirePlumber/InputPlumber/udev/tmpfiles ordering and env.
- `nix/tests/network-lid-steam-module-contract.nix` — NetworkManager/iwd/Tailscale capability settings, hardware button service, Steam module boundaries.
- `nix/tests/cemu-package-contract.nix` — package output files, wrapper evidence, SM8550 settings injection, Cemu build evidence files.
- `nix/tests/steam-package-output-contract.nix` — built Steam package executables/resources/manifest/evidence.
- `nix/tests/rocknix-patch-contract.nix` — patch series applies to pinned upstream and patched substrate files/contracts exist.
- `nix/tests/shell-smoke.nix` (optional wrapper) — runs only real shell syntax/smoke scripts; alternatively CI can call a plain shell script directly.

## Shell Tests That Should Remain Shell

- `packages/steam/tests/steam-guest-runtime-prep-smoke.sh` — real mutation/repair behavior in temp fixture directories.
- `packages/steam/tests/steam-guest-run-smoke.sh` — real `--check`/`--run` behavior and pressure-vessel env handling.
- A split Steam helper smoke from `steam-package-contract.sh` for missing-env failures and real helper execution.
- Shell syntax and ShellCheck for `scripts/*`, `guest/launchers/*`, and package shell helpers.
- `scripts/verify-sm8550-payloads` and artifact verification in image-producing workflows.
- Local/CI orchestration scripts such as `scripts/build-sm8550` and `scripts/ci-build-stage`; these may invoke Nix checks but should not be the source of Nix contract truth.

## Recommendations

- Treat `nix/tests/*.nix` as the new source of truth for flake outputs, NixOS module evaluation, package output contracts, and patch/build graph invariants.
- Rename or shrink `guest/scripts/static-checks.sh`; after the refactor, a name like `guest/scripts/shell-smoke.sh` would better match its remaining role.
- Do not introduce TypeScript/Bun tooling unless a TS runtime/domain surface is added later.
- Keep the current project terminology: SM8550 substrate, ROCKNIX host, NixOS guest, product-blind `rocknix-guest-base`, downstream Korri product/appliance composition, SoC-bound `devices/` data.
- Avoid replacing one monolith with another. Prefer several focused Nix tests whose names match contracts and CI output.
- Flag the `scripts/verify-korri-promotion-proof` impurity explicitly in the plan: either make it a named manual/impure proof or redesign it as a pure Nix check with pinned inputs.
