---
title: refactor: Move Steam runtime mechanics behind the package seam
type: refactor
status: completed
date: 2026-05-23
---

# refactor: Move Steam runtime mechanics behind the package seam

## Summary

Make `packages/steam/` the deep module for guest-native ARM64 Steam runtime mechanics, while reducing `guest/modules/steam.nix` to a thin SM8550 guest adapter that supplies paths, devices, and session integration. This preserves current behavior but moves reusable Steam/FEX/pressure-vessel knowledge out of the substrate module so Korri can later opt into Steam as a product app without inheriting nix-on-rocks internals.

---

## Problem Frame

The Korri dependency-direction inversion established that nix-on-rocks is the SM8550 substrate and Korri is the product/appliance layer. Steam was intentionally left in nix-on-rocks short-term because its current runtime wrapper straddles OS ABI, guest session, mutable `/storage` state, FEX, pressure-vessel, input, and product-app concerns.

The current code still reflects that temporary compromise: `packages/steam/` owns bootstrap/seed/preflight helpers, but `guest/modules/steam.nix` contains most of the runnable Steam runtime capsule. That makes Steam hard to reuse as a package capability and keeps product-independent Steam knowledge tied to one guest substrate module.

---

## Requirements

- R1. Preserve current guest-native Steam behavior and do not change default runtime paths, launch args, or substrate activation behavior during the refactor.
- R2. Move generic Steam runtime mechanics into `packages/steam/`, including runtime preparation, FEX/pressure-vessel repair, and package-owned launch/preflight helpers.
- R3. Keep SM8550 guest integration in `guest/modules/steam.nix`: path defaults, systemd wiring, device/session environment, and uinput service ownership.
- R4. Keep mutable Valve payloads and Steam state caller-provided and outside the Nix store; do not attempt immutable Nix-store Steam client/runtime artifacts in this plan.
- R5. Keep Korri/product exposure out of scope; the result should make later Korri app selection easier without moving selection into this repo.
- R6. Strengthen static/package contract checks so the package/substrate boundary stays reviewable after the refactor.
- R7. Add package-level tests or contract checks for the moved shell helpers rather than relying only on the full guest module build.

**Related prior context:** The Korri dependency-direction inversion docs define nix-on-rocks as SM8550 substrate and Korri as downstream product/appliance owner. This plan handles the deferred Steam ownership migration implied by that boundary: OS-coupled Steam runtime capability stays here, while later user-facing app selection belongs downstream.

---

## Scope Boundaries

- Do not move Steam product/app selection to Korri in this plan.
- Do not add a Korri dependency or any Korri product surface back into nix-on-rocks.
- Do not change the user-facing Steam launch behavior beyond preserving the existing default through a thinner module adapter.
- Do not make Valve's ARM64 Steam client/runtime immutable Nix-store artifacts.
- Do not redesign FEX rootfs provisioning, binfmt policy, or per-game Proton settings.
- Do not rework Cemu, Moonlight, or other package seams except as references for patterns.

### Deferred to Follow-Up Work

- Korri-side Steam product selection: separate Korri plan after this repo exposes a cleaner package/runtime capability.
- Immutable or cached Steam client/runtime seed artifacts: future research only if Valve payload licensing/update behavior makes this practical.
- User-facing launcher/menu integration changes: separate product or appliance work.

---

## Context & Research

### Relevant Code and Patterns

- `packages/steam/README.md` already defines the intended package boundary: package-owned helpers, downstream-owned mutable paths, FEX rootfs, binfmt, session launch, Gamescope geometry, and per-game settings.
- `packages/steam/manifest.nix` records the supported/downstream-owned/unsupported contract and should become the source of truth for any new helper entry points.
- `packages/steam/package.nix` installs current scripts and evidence under `$out/nix-support/rocknix-steam-bootstrap/`.
- `packages/steam/scripts/steam-arm64-bootstrap`, `packages/steam/scripts/steam-arm64-seed`, and `packages/steam/scripts/steam-guest-native` already use explicit env contracts and dry-run/apply or check/run modes.
- `guest/modules/steam.nix` currently contains the coupling to peel back: runtime prep, FEX wrapping, pressure-vessel fixes, FHS wrapper, launch script, default args, uinput prep, and systemd service wiring.
- `guest/scripts/static-checks.sh` already enforces Steam package boundaries and should be updated as responsibilities move.
- `packages/cemu/package.nix` and Cemu launchers provide the closest local precedent for package-owned runtime setup with guest-owned `/storage` and session adapters.

### Institutional Learnings

- `docs/solutions/performance-issues/rocknix-layer14-cemu-performance-audit-2026-05-09.md`: peel runtime responsibilities to the narrowest owner; package behavior, launcher setup, guest session defaults, `/storage` compatibility layout, and device policy should be distinct.
- `docs/solutions/best-practices/manual-steam-game-launching-rocknix-arm64-2026-05-04.md`: Steam launching on ARM64 is not just Proton; keep Steam Runtime / pressure-vessel as a first-class seam.
- `docs/solutions/runtime-errors/steam-desktop-ui-arm64-manifest-spinner-rocknix-2026-05-04.md`: mutable Steam metadata under `/storage` can be incomplete and should be repaired deterministically from installed evidence.
- `docs/solutions/best-practices/rocknix-layer14-main-space-cold-boot-autostart-2026-05-08.md`: host, guest substrate, and product concerns must remain separate even when hardware validation happens on the same device.
- `docs/solutions/developer-experience/nix-layer-6-managed-user-environment-rocknix-2026-05-05.md`: `/storage` writes need explicit ownership, reversibility, and diagnostics.

### External References

- External research was not needed. This is a repo-local boundary refactor around existing package/module contracts and prior hardware learnings.

---

## Key Technical Decisions

- Package owns Steam runtime mechanics; guest module owns SM8550 adaptation. This follows the existing `packages/steam/README.md` boundary and the Cemu peelback pattern.
- Move behavior in slices, not all at once. Start with runtime-prep extraction because it is generic Steam/FEX/pressure-vessel logic and has the least systemd/session coupling.
- Keep `/storage` defaults in the guest adapter for now. The package helpers should accept explicit env values; the adapter may continue to provide today's SM8550 defaults.
- Keep uinput device creation/repair and service wiring in the guest/input substrate layer. Steam-specific pressure-vessel exposure of the already-provided device can move with the package runtime capsule.
- Keep FHS environment construction package-owned only after helper extraction is stable. It is the largest seam and should be moved after package tests/static checks protect the smaller pieces.
- Preserve `x86_64-linux` package buildability only where it helps run Steam on SM8550 devices: helper/resource generation, local checks, or CI. The real runnable Steam capsule is an aarch64 guest/device capability, not an x86 host runtime target, and x86 support must not preserve Korri-era product behavior.
- Have `guest/modules/steam.nix` consume the package through an explicit module option whose default is the in-repo package derivation, rather than assuming access to `self.packages` from exported modules.
- Treat static checks as public-contract tests. Update them to assert the new owner for each moved responsibility and to prevent regression back into the guest module.

---

## Open Questions

### Resolved During Planning

- Should Steam move fully to Korri now? No. Korri product exposure remains a follow-up; this plan only makes the nix-on-rocks package seam deeper.
- Should Valve's mutable Steam payload move into the Nix store? No. The current package contract explicitly keeps mutable client/runtime state caller-provided.
- Should default behavior change? No. This is a preservation refactor.

### Deferred to Implementation

- Exact FHS wrapper factoring: final shape depends on how cleanly `buildFHSEnv` can move into `packages/steam/package.nix` without making the package interface harder to consume. If x86 helper-only support stops helping the SM8550 Steam workflow, it can be narrowed in a separate explicit cleanup; it is not a Korri compatibility surface.

---

## High-Level Technical Design

> *This illustrates the intended approach and is directional guidance for review, not implementation specification. The implementing agent should treat it as context, not code to reproduce.*

```text
Before

packages/steam
  bootstrap / seed / guest-native preflight

guest/modules/steam.nix
  Steam runtime prep
  FEX / pressure-vessel repair
  FHS wrapper
  Steam launch script
  uinput device repair + systemd unit
  SM8550 path/session defaults

After

packages/steam
  bootstrap / seed / guest-native preflight
  runtime prep helper
  package-owned pressure-vessel device exposure
  package-owned FHS/launch runtime capsule
  package contract tests + evidence

guest/modules/steam.nix
  installs/uses package helpers
  supplies SM8550 defaults and environment
  wires systemd services
  owns device/session integration

Korri later
  opts into Steam as a product app
  does not learn FEX/pressure-vessel internals
```

Responsibility target:

| Concern | Target owner |
|---|---|
| ARM64 Steam bootstrap metadata/resources | `packages/steam/` |
| ARM64 Steam client/runtime seeding helper | `packages/steam/` |
| Steam Runtime / pressure-vessel repair | `packages/steam/` |
| FEX wrapping rules for Steam runtime helpers | `packages/steam/` |
| FHS Steam execution capsule | `packages/steam/` |
| `/storage` default path choices | `guest/modules/steam.nix` adapter |
| uinput device creation/repair and systemd wiring | `guest/modules/steam.nix` / guest input substrate |
| pressure-vessel exposure of `/dev/uinput` and `/dev/input` | `packages/steam/` runtime capsule, supplied by guest adapter env |
| session bus, Wayland/X11, SM8550 driver env defaults | `guest/modules/steam.nix` adapter |
| generic FHS `LD_LIBRARY_PATH` / `PATH` mechanics for Steam payloads | `packages/steam/` runtime capsule |
| product app exposure | Korri follow-up |

---

## Implementation Units

### U1. Map Steam responsibilities and update the package contract

**Goal:** Make the target ownership explicit before moving code so reviewers can tell whether each later diff deepens the package seam or simply relocates coupling.

**Requirements:** R1, R2, R3, R4, R5, R6

**Dependencies:** None

**Files:**
- Modify: `packages/steam/README.md`
- Modify: `packages/steam/manifest.nix`
- Modify: `guest/scripts/static-checks.sh`

**Approach:**
- Add a responsibility table to the package docs that separates package-owned runtime mechanics, guest/substrate adapters, mutable state, and downstream product selection.
- Extend the manifest contract with the planned helper classes before the implementation moves them.
- Update static checks to assert the contract text and preserve the existing ban on package-owned product/session policy.

**Patterns to follow:**
- `packages/steam/README.md` package boundary section.
- `packages/steam/manifest.nix` `packageContract.supported/downstreamOwned/unsupported` structure.
- Cemu package contract language in `packages/cemu/manifest.nix`.

**Test scenarios:**
- Test expectation: none beyond static contract assertions -- this unit changes documentation/manifest contract only.

**Verification:**
- Reviewers can identify which current `guest/modules/steam.nix` responsibilities are intended to move and which must remain substrate-owned.
- Static checks still reject package logic that owns host/session/product policy.

---

### U2. Move Steam runtime preparation into a package-owned helper

**Goal:** Extract generic Steam Runtime / pressure-vessel / FEX preparation logic from `guest/modules/steam.nix` into `packages/steam/`.

**Requirements:** R1, R2, R4, R6, R7

**Dependencies:** U1

**Files:**
- Create: `packages/steam/scripts/steam-guest-runtime-prep`
- Create: `packages/steam/tests/steam-guest-runtime-prep-smoke.sh`
- Modify: `packages/steam/package.nix`
- Modify: `packages/steam/README.md`
- Modify: `guest/modules/steam.nix`
- Modify: `guest/scripts/static-checks.sh`

**Approach:**
- Move the behavior currently embodied by `rocknix-steam-prepare-runtime` into a package script with explicit `STEAM_HOME` and related env inputs.
- Keep the same repairs: FEX wrapper restoration, pressure-vessel helper wrapping, font `.uuid` repair, Proton shebang repair, and Python symlink repair.
- Keep the guest module as the caller that supplies today's default paths.
- Add smoke tests over temporary fixture trees so the package helper can be checked without a real Steam install.

**Execution note:** Characterization-first. Capture expected fixture behavior for the existing runtime-prep logic before deleting it from the module.

**Patterns to follow:**
- `packages/steam/scripts/steam-arm64-bootstrap` explicit env and mode handling.
- `packages/steam/scripts/steam-arm64-seed` package-local helper style.
- Static shell checks already run by `guest/scripts/static-checks.sh`.

**Test scenarios:**
- Happy path: fixture with pressure-vessel executable helper -> runtime prep replaces/wraps only executable x86 helper files and leaves shared objects untouched.
- Happy path: fixture with Steam Runtime font directories -> runtime prep creates missing `.uuid` marker files.
- Happy path: fixture Proton script using `/usr/bin/env python3` -> runtime prep rewrites it to the FHS-visible interpreter path expected by current behavior.
- Edge case: missing `steamapps/common` -> runtime prep exits successfully without writes.
- Error path: required env such as `STEAM_HOME` is absent -> helper fails with a clear preflight error.
- Regression: Proton/Wine payload files that should be restored, not wrapped, remain executable and do not receive FEX wrapper text.

**Verification:**
- `guest/modules/steam.nix` no longer embeds the runtime-prep implementation.
- Package smoke tests and static checks prove the helper exists and preserves the known Steam Runtime repairs.

---

### U3. Keep uinput device repair substrate-owned and move only Steam runtime exposure

**Goal:** Avoid moving generic device-node policy into the Steam package while still making the Steam-specific pressure-vessel device exposure part of the package runtime capsule.

**Requirements:** R1, R2, R3, R6, R7

**Dependencies:** U1, U2

**Files:**
- Modify: `guest/modules/steam.nix`
- Modify: `guest/modules/input.nix` if ownership comments or service ordering need clarification
- Modify: `packages/steam/README.md`
- Modify: `guest/scripts/static-checks.sh`

**Approach:**
- Keep `/dev/uinput` creation/repair in the guest substrate, where input device policy already lives.
- Keep the Steam uinput systemd service or migrate it toward the existing guest input substrate only if that preserves current behavior.
- Move only the Steam-specific use of the device, such as pressure-vessel filesystem exposure, into the package-owned run capsule in U4.
- Update docs/static checks so future readers do not infer that all uinput handling belongs to Steam.

**Patterns to follow:**
- Existing uinput substrate assertions in `guest/modules/input.nix` and `guest/scripts/static-checks.sh`.
- Current Steam pressure-vessel environment setup in `guest/modules/steam.nix`.

**Test scenarios:**
- Happy path: default guest still prepares `/dev/uinput` before Steam can use Steam Input.
- Happy path: package runtime receives or constructs the pressure-vessel exposure for `/dev/uinput` and `/dev/input` without owning device-node creation.
- Regression: package scripts do not perform privileged `mknod` device repair.
- Regression: static checks still forbid hardcoded live uinput device numbers in substrate logic.

**Verification:**
- Device creation/repair remains in the substrate layer.
- Steam package owns only how Steam Runtime/pressure-vessel consumes the already-provided input devices.

---

### U4. Move the FHS Steam run capsule into the package output

**Goal:** Make `packages/steam/` provide the runnable Steam capsule while the guest module supplies adapter environment and installs the wrapper.

**Requirements:** R1, R2, R3, R4, R6

**Dependencies:** U2, U3

**Files:**
- Create: `packages/steam/scripts/steam-guest-run`
- Modify: `packages/steam/package.nix`
- Modify: `packages/steam/manifest.nix`
- Modify: `packages/steam/README.md`
- Modify: `packages/steam/scripts/steam-guest-native`
- Modify: `guest/modules/steam.nix`
- Modify: `guest/scripts/static-checks.sh`

**Approach:**
- Package the current FHS/run-script behavior as the Steam package's execution capsule for aarch64, where Steam actually runs on these devices.
- Preserve x86 package behavior only for helper/check surfaces that still support the SM8550 Steam workflow. Do not design or maintain an x86 runnable capsule unless a concrete device workflow needs it.
- Keep the wrapper env-driven: caller supplies mutable paths, FEX rootfs, and session env rather than the package hardcoding product policy.
- Keep current default Steam args owned by the guest adapter; the package run capsule consumes args supplied by the caller and must not define SM8550/product defaults.
- Keep SM8550/session/driver defaults in the guest adapter. Move only generic FHS `LD_LIBRARY_PATH` / `PATH` mechanics for Valve's mutable payloads into the package capsule.
- Include pressure-vessel filesystem exposure for input devices in the runtime capsule, using devices supplied by the guest substrate rather than creating those devices itself.

**Patterns to follow:**
- Current `steamFhs` and `steamRunScript` structure in `guest/modules/steam.nix`.
- `packages/steam/scripts/steam-guest-native` preflight/exec contract.
- Cemu package wrapper model in `packages/cemu/package.nix`.

**Test scenarios:**
- Happy path: aarch64 package build includes a Steam run entry point and evidence lists it as package-owned.
- Happy path: any retained x86 package build remains helper/check-only and is justified by SM8550 Steam workflow needs, not Korri compatibility.
- Happy path: guest module invokes the package-owned aarch64 run capsule while preserving current default args from the adapter.
- Edge case: caller overrides `STEAM_HOME`, `STEAM_GAMES_ROOT`, or `FEX_ROOTFS` -> wrapper uses the provided values rather than module literals.
- Error path: Steam client missing -> wrapper fails with the existing clear hint to seed the ARM64 payload first.
- Regression: package scripts do not call `systemctl`, `swaymsg`, or `gamescope` and do not own product launch orchestration.

**Verification:**
- The package, not the guest module, owns the Steam FHS run capsule.
- The guest module remains the only place where SM8550 session/service integration is wired.

---

### U5. Reduce `guest/modules/steam.nix` to a thin adapter with options

**Goal:** Make the NixOS module read as substrate integration rather than Steam runtime implementation.

**Requirements:** R1, R3, R5, R6

**Dependencies:** U2, U3, U4

**Files:**
- Modify: `guest/modules/steam.nix`
- Modify: `guest/profiles/rocknix-guest-base.nix`
- Modify: `guest/README.md`
- Modify: `docs/contracts/layer14-main-space-contract.md`
- Modify: `guest/scripts/static-checks.sh`

**Approach:**
- Replace embedded script bodies with calls to package-provided helpers.
- Add or clarify module options for Steam home, games root, dot dir, FEX rootfs, and default args.
- Add a package option only if required for clean wiring; its default should call the in-repo `packages/steam/package.nix` through `pkgs.callPackage` so exported modules do not rely on `self.packages`.
- Keep the module responsible for environment values that are specific to the root Sway/session/SM8550 guest.
- Keep `rocknix-guest-base` behavior unchanged while making the dependency on the package seam explicit.

**Patterns to follow:**
- `guest/modules/device.nix` option style for SM8550 defaults.
- Existing guest module pattern of substrate-owned service wiring with product-blind behavior.
- Layer 14 contract language around guest-owned runtime plumbing and downstream product consumption.

**Test scenarios:**
- Happy path: default `rocknix-guest-base` still includes Steam runtime support and resolves package helper paths.
- Happy path: overriding Steam path options changes the adapter environment without modifying package scripts.
- Edge case: if a package option is introduced, an alternative package value can be supplied by downstream evaluation without changing module internals.
- Regression: no Korri product options or app-selection behavior appears in `guest/modules/steam.nix`.

**Verification:**
- Reading `guest/modules/steam.nix` shows substrate adaptation only: options, packages, env, service wiring, and no large Steam Runtime implementation blocks.

---

### U6. Strengthen package contract tests and static ownership checks

**Goal:** Prevent future drift where Steam runtime mechanics leak back into the guest module or product/session policy leaks into the package.

**Requirements:** R6, R7

**Dependencies:** U2, U3, U4, U5

**Files:**
- Create: `packages/steam/tests/steam-package-contract.sh`
- Modify: `guest/scripts/static-checks.sh`
- Modify: `flake.nix` if a package check output is needed
- Modify: `packages/steam/package.nix`

**Approach:**
- Add a package-level contract test that checks helper presence, dry-run/check modes, required env failures, and evidence metadata.
- Wire the test into the existing static check path or flake checks without requiring live Steam downloads or Sobo hardware.
- Update grep-based boundary checks to assert moved implementation no longer lives in `guest/modules/steam.nix`.
- Keep hardware/device behavior validation separate from package contract tests.

**Patterns to follow:**
- Existing `guest/scripts/static-checks.sh` as the repo's public-contract test surface.
- Current optional `shellcheck` handling for package scripts.
- `$out/nix-support/...` evidence pattern in package derivations.

**Test scenarios:**
- Happy path: all package helpers are installed and listed in package evidence.
- Happy path: dry-run/check helpers can run against temporary fixture paths without network or root privileges.
- Error path: missing required env produces non-zero exit and a clear error for each helper that requires env.
- Regression: static checks fail if `guest/modules/steam.nix` reintroduces moved runtime-prep/FHS implementation blocks.
- Regression: static checks fail if package scripts gain `systemctl`, `swaymsg`, `gamescope`, Korri references, or host Steam fallback behavior.

**Verification:**
- Local static checks provide fast confidence in the package/substrate seam before any hardware run.

---

### U7. Validate unchanged behavior on build hosts and Sobo

**Goal:** Prove the refactor preserved runtime behavior while improving ownership locality.

**Requirements:** R1, R3, R6, R7

**Dependencies:** U6

**Files:**
- Create: `docs/acceptance/steam-runtime-capsule-refactor-sobo-2026-05-23.md`
- Modify: `packages/steam/README.md` if validation reveals needed operator notes

**Approach:**
- Build the package and guest configuration through the existing flake surfaces.
- On Fuji/aarch64, verify `.#steam` builds and guest system evaluation/build dry-run still includes Steam support.
- On Sobo, run the safest available Steam preflight first, then a bounded launch smoke if the device state has a seeded Steam client.
- Record whether the refactor is behavior-preserving; do not expand scope into fixing unrelated Steam runtime issues.

**Patterns to follow:**
- Moonlight/Cemu acceptance docs under `docs/acceptance/` for build path, device, evidence root, and decision format.
- Existing Steam best-practice docs for what a healthy desktop/session launch should look like.

**Test scenarios:**
- Integration: `steam-arm64-bootstrap --dry-run` against explicit temporary paths reports intended writes without touching real Steam state.
- Integration: `steam-arm64-seed --dry-run` reports ARM64 runtime/client source endpoints and intended layout without downloading in the test path.
- Integration: `steam-guest-native --check` fails clearly when mutable client or loader prerequisites are absent, matching current preflight semantics.
- Hardware smoke: with a seeded Sobo Steam home, the guest adapter reaches the same launch/preflight state as before the refactor.
- Regression: current `/storage` Steam state is not rewritten unexpectedly during dry-run/check validation.

**Verification:**
- Acceptance doc records build, package preflight, and any Sobo smoke evidence.
- No product behavior change is required to consume the refactored package seam.

---

## System-Wide Impact

- **Interaction graph:** `flake.nix` exposes `packages.steam`; `guest/modules/steam.nix` consumes the package through an explicit default/package option; `rocknix-guest-base` imports the guest module; Korri later consumes the substrate without needing package internals.
- **Error propagation:** Package helpers should fail early for missing explicit env or missing mutable Steam payloads; the guest/input substrate should continue to tolerate non-fatal uinput prep issues as it does today.
- **State lifecycle risks:** Helpers touch mutable `/storage` Steam state only when explicitly invoked in apply/run modes. Tests should prefer temporary fixtures and dry-run/check modes.
- **API surface parity:** Existing helper entry points remain; new entry points should be listed in package evidence and README contract.
- **Integration coverage:** Static checks prove ownership; package tests prove helper behavior; Sobo acceptance proves the adapter still works against real guest/session constraints.
- **Unchanged invariants:** No Korri dependency returns to nix-on-rocks; x86 package support is not a Korri compatibility surface; Steam client/runtime payloads remain mutable; host Steam fallback remains unsupported; default guest path behavior remains unchanged.

---

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| Moving FHS wrapper into the package makes the package depend on too much guest policy | Move runtime prep first, keep env explicit, and leave session/path defaults in the guest adapter. |
| Shell refactor changes Steam runtime behavior subtly | Add characterization fixture tests before deleting module logic and run a Sobo smoke only after static/package tests pass. |
| Static checks become brittle grep assertions against implementation details | Assert ownership-level sentinels and installed entry points, not exact script bodies. |
| `/storage` state is accidentally mutated during tests | Use dry-run/check modes and temporary fixture paths for package tests; reserve real state for explicit Sobo acceptance. |
| Korri/product concerns creep into this refactor | Keep product app exposure deferred and enforce no Korri references in package/module surfaces. |

---

## Documentation / Operational Notes

- Update `packages/steam/README.md` as the main package contract.
- Update `guest/README.md` or Layer 14 contract only where the substrate adapter responsibility changes materially.
- Add an acceptance doc after hardware/build validation.
- If implementation reveals a reusable Steam/FEX/pressure-vessel lesson, capture a `docs/solutions/` entry after the fix rather than expanding this plan.

---

## Sources & References

- Related requirements draft: `docs/brainstorms/2026-05-22-001-korri-dependency-direction-inversion-requirements.md`
- Related plan draft: `docs/plans/2026-05-22-002-refactor-korri-dependency-inversion-plan.md`
- Package contract: `packages/steam/README.md`
- Package manifest: `packages/steam/manifest.nix`
- Current guest adapter: `guest/modules/steam.nix`
- Static checks: `guest/scripts/static-checks.sh`
- Cemu runtime peelback learning: `docs/solutions/performance-issues/rocknix-layer14-cemu-performance-audit-2026-05-09.md`
- Steam manual launch learning: `docs/solutions/best-practices/manual-steam-game-launching-rocknix-arm64-2026-05-04.md`
- Steam manifest repair learning: `docs/solutions/runtime-errors/steam-desktop-ui-arm64-manifest-spinner-rocknix-2026-05-04.md`
