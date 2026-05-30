---
title: "refactor: Make the substrate fully product-blind (Phase 5)"
type: refactor
status: active
date: 2026-05-29
revisited: 2026-05-30
depends-on:
  - docs/acceptance/sm8550-product-payload-full-build-sobo-2026-05-27.md
  - docs/acceptance/sm8550-product-payload-thor-bandai-2026-05-29.md
---

# refactor: Make the substrate fully product-blind (Phase 5)

## Summary

Phases 1–4 inverted the dependency direction: Korri now publishes product payloads and `nix-on-rocks` consumes them per-product via `product-payload-<id>.lock`. Thor acceptance (2026-05-29) is the proof that the per-product selector is real, not Odin2Portal-shaped with a different name.

There are still Korri-shaped identifiers, legacy single-product lock files, and Korri-specific scripts in `nix-on-rocks` that survived the cutover. Phase 5 removes them so the substrate kit is fully product-blind and a third product would not need any substrate changes to onboard.

## Scope

Substrate-side cleanup only. No behavior change for either supported product. No Korri-side change required; if any Korri-side rename helps, it belongs in a Korri PR, not this plan.

## Non-goals

- Not introducing new substrate features.
- Not changing the per-product selector mechanism itself; it works and is now proven.
- Not removing developer-shaped Korri data from product payloads — that is product policy and lives in Korri.
- Not touching the SSH first-boot lifecycle (separate plan `docs/plans/2026-05-29-002-feat-guest-ssh-first-boot-access-lifecycle-plan.md`).
- Not touching the immutable-cleanup fix (separate plan `docs/plans/2026-05-29-001-fix-rocknix-guest-root-ensure-immutable-cleanup-plan.md`).

## Inventory (current as of 2026-05-29)

Three categories. Each unit below targets one.

### Category A — Duplicate / legacy single-product lock files

```text
guest.lock                  == guest-odin2portal.lock          duplicate
product-payload.lock        == product-payload-odin2portal.lock duplicate
```

Both have per-product equivalents. The legacy aliases were retained for compatibility during the cutover and are now dead.

### Category B — Korri-shaped identifiers in product-blind substrate files

Korri mentions by file (from `grep -ic`):

```text
6   guest/profiles/rocknix-guest-base.nix
4   guest/scripts/static-checks.sh
3   guest/profiles/main-space.nix
3   packages/steam/tests/steam-package-contract.sh
1   nix/tests/main-space-systemd-contract.nix
1   nix/tests/audio-input-systemd-contract.nix
1   packages/moonlight-embedded/manifest.nix
```

Triage rule:

- **`guest/`**: lives in the substrate kit and is product-blind. Korri mentions here are bugs to fix (rename to neutral terms).
- **`nix/tests/*`**: substrate tests. Same rule.
- **`packages/{moonlight-embedded,steam}/`**: substrate-owned packages. Korri mentions are also bugs.

Not in scope here:

- `docs/**` references to past Korri-only Phase 3/4 evidence. Those are historical, accurate, and should stay.
- `README.md` and `guest/README.md` mentions where the example shown is genuinely Korri. Renaming those would be misleading.

### Category C — Korri-specific scripts and assertions

```text
scripts/verify-korri-promotion-proof
  Hardcoded to expect korri-rocknix-kiosk-by-compatible; the active payload
  uses korri-rocknix-kiosk-{odin2portal,thor}. Stale before this plan;
  unused in CI today.

(any) Korri-named static-check assertions in
  work/rocknix/projects/ROCKNIX/packages/tools/rocknix-guest-substrate/tests/
  guest-substrate-static-checks.sh
```

## Approach

Five units. Ordered so that risk and build cost compound only at the end.

### U1 — Cheap renames in non-build-touching files

No CI cost. Pure rename + grep verification.

Files in scope:

- `guest/launchers/remote-cemu-*.sh` — comments and string literals only.
- `packages/moonlight-embedded/patches/README.md` and `packages/steam/README.md` — documentation.
- Any code comment that uses "Korri" where the surrounding code is product-blind.

Out of scope in U1: any rename that would change a Nix attribute name, a systemd unit name, a script invocation, or a lock-file field name. Those are U3.

Validation: local greps; CI not required.

### U2 — Retire `scripts/verify-korri-promotion-proof`

It is stale (asserts a build target that no longer exists) and unused.

Steps:

- Confirm no CI workflow, no `justfile`, no other script, and no doc currently invokes it.
- Delete the script.
- Add a one-line note to `docs/solutions/` if needed to record that promotion proof is now covered by `scripts/tests/product-payload-contract.sh --product <id>`.

Validation: `grep -rln verify-korri-promotion-proof` returns nothing. Substrate static checks pass.

### U3 — Drop legacy single-product lock duplicates

- Delete `guest.lock` and `product-payload.lock`.
- Update every reader (`scripts/apply-rocknix-patches`, `scripts/verify-sm8550-locks`, `scripts/verify-product-payload`, `scripts/tests/product-payload-contract.sh`, preflight workflow) to require `--product <id>` and refuse to fall back to the legacy filenames.
- Update `.github/workflows/*` to pass `--product` everywhere (preflight already does; double-check the rest).

Compatibility note:

- These files are not consumed by any external dependency. The only callers are inside this repo and the now-merged Korri PR.
- Static-check assertion: `! ls guest.lock 2>/dev/null` and `! ls product-payload.lock 2>/dev/null`.

Validation: local apply/verify against both products; preflight CI cycle (cheap).

### U4 — Neutralize Korri identifiers in product-blind code

For each Category-B file:

1. Read the file.
2. Decide whether the Korri mention is:
   - (a) a comment that should just use neutral language → rename
   - (b) a string literal or identifier that affects behavior → rename + update any tests pinning it
   - (c) genuinely Korri-specific (probably means the file is in the wrong layer) → flag for re-homing
3. Apply rename or open a follow-up note.

Specifically expect:

- `guest/profiles/rocknix-guest-base.nix` and `guest/profiles/main-space.nix`: substitute Korri-named role/policy bindings with payload-driven values; the values themselves get supplied by `product-payload-<id>.lock`.
- `guest/scripts/static-checks.sh`: existing Korri-named assertions become product-id-agnostic checks; the rendered manifest is verified to contain the *expected* product id, not Korri specifically.
- `nix/tests/*-systemd-contract.nix`: same.
- `packages/{moonlight-embedded,steam}`: substrate-owned packages with Korri-named hooks become payload-named hooks; the actual hook payload still comes from Korri.

Validation:

- `scripts/apply-rocknix-patches --product odin2portal` passes
- `scripts/apply-rocknix-patches --product thor` passes
- All static checks pass for both products
- Image-only CI green for both products

### U5 — Final proof image-only round

One image-only run per product. Confirm the rendered manifest no longer contains stray Korri identifiers in any field that the substrate owns. Compare against the last accepted Thor manifest to verify the user-visible payload identity is unchanged.

Validation:

- Manifest diff: substrate-owned fields are byte-stable except for the renamed strings (which should now be neutral).
- Payload-derived fields are byte-stable.

## Validation summary

- 4 substrate-only edits with progressively wider blast radius (U1 → U4).
- 1 cheap workflow change (U3).
- 2 image-only CI runs in U5 (no full builds).
- No device acceptance required: the device contract did not change.

## Risks

- **Renames that look cosmetic but actually change a behavior key**. Mitigated by U4's "(b) requires test update" rule and by an image-only CI gate at the end of U4.
- **Hidden external consumers of `guest.lock` / `product-payload.lock`**. Mitigated by deleting them and observing CI; if anything breaks, the failure is loud and the fix is to pass `--product`.
- **Misclassifying a Korri-specific identifier as substrate-blind**. Mitigated by reading each file before renaming and explicitly tagging anything ambiguous as "leave alone, follow up."
- **Build cost creep**. Mitigated by saving image-only CI for U5; U1–U4 are local-only.

## Ordering with other plans

- **Plan 001 (immutable cleanup)**: independent. Can land before or after.
- **Plan 002 (SSH first-boot lifecycle)**: independent. Can land before or after. Note that Plan 002 may want to add a `payload.guest-ssh` field to the lock files, which is easier with the cleaner Phase 5 lock layout, so landing Phase 5 first is mildly preferred. Not a hard dependency.
- **Future Phase 6 (product customizations)**: depends on Phase 5 being done so customizations have a clean schema to extend.

## Lifecycle

`status: draft` → `status: active` after PR review on each unit batch → `status: completed` after U5 manifest stability is observed for both products.

## Execution outcome (2026-05-29)

U1 (cheap renames in non-build-touching files): **no change required**. The README/launcher mentions of Korri that survived Phase 4 turned out to be accurate architecture documentation describing how nix-on-rocks composes with Korri downstream, not stray identifier leakage.

U2 (retire `scripts/verify-korri-promotion-proof`): **done** in commit retiring the stale script and pointing the README at `scripts/tests/product-payload-contract.sh --product <id>`.

U3 (drop legacy single-product lock duplicates): **done**. `guest.lock` and `product-payload.lock` were symlinks to the odin2portal per-product locks; both removed. The vestigial `check-boundary-lint` guard for `product-payload.lock` was removed and the `product-payload-contract.sh` shellcheck source hints were updated to point at the odin2portal per-product locks.

U4 (neutralize Korri identifiers in product-blind code): **no change required** after audit. The remaining mentions in `guest/profiles/*.nix`, `guest/scripts/static-checks.sh`, `packages/{steam,moonlight-embedded}/**`, and `nix/tests/*-systemd-contract.nix` are all one of:

- accurate architecture documentation describing the downstream composition pattern
- soft systemd unit references (`before`/`after`/`partOf` against `korri-kiosk.service`) that the substrate maintains for ordering relationships; systemd treats unknown unit names as no-ops, so these are non-load-bearing today
- negative-assertion lint guards (`! grep -q 'services\.korri\|korri\.nixosModules'`) that protect substrate code from Korri-into-substrate leakage

None of those categories are bugs. The substrate is already product-blind in the places that matter, which is what Thor acceptance proved end-to-end.

U5 (final proof image-only round): **deferred** — U2+U3 changes are bound to no derivation-level outputs (script deletion, lock duplicates, lint guard removal, shellcheck source hint update). The image-only CI run that lands this PR is the proof, not a separate cycle.

## Known open follow-ups (not Phase 5)

- Substrate soft references to `korri-kiosk.service` are technically a product name baked into substrate config. They would only matter if a non-Korri product authority wanted to slot in with a different kiosk unit name. If that day comes, the right fix is to parameterize the kiosk-unit name via `payload.kioskUnit` in the product-payload contract and feed it into the rendered substrate config. Tracked here as a future enhancement, not as Phase 5 work.

## Scope retro revisited (2026-05-30)

A deep substrate-leak audit on 2026-05-30, run while consolidating the substrate-followups PR, found that the 2026-05-29 execution outcome above **misclassified the surviving Korri references**. Specifically:

- **U1 "no change required"** held up. Cheap doc/README mentions were accurate architecture documentation, as claimed.
- **U2 "done"** held up. `scripts/verify-korri-promotion-proof` was retired.
- **U3 "done"** held up. Legacy single-product locks were dropped.
- **U4 "no change required" was wrong.** The retro classified the remaining Korri references as "soft systemd unit refs (no-op when absent)" or "negative-assertion lint guards." That classification was inaccurate for at least four load-bearing couplings still on `origin/main`.

### What U4's audit missed

1. **`guest/modules/lid.nix:115`** hardcodes `/sys/fs/cgroup/system.slice/korri-kiosk.service` as the *primary* cgroup probe candidate. This is not a no-op when absent: a non-Korri product with a differently-named kiosk silently falls back to the substrate's `main-space-sway-kiosk.service` fallback profile, which is not the real kiosk. Lid-close PID-stopping breaks silently.

2. **`guest/modules/input.nix:17`** defines `hasKorriKiosk = options.services ? korri && options.services.korri ? kiosk;`. The substrate **reads the downstream product's NixOS option tree** to branch its own behavior. That is the textbook product-knowledge leak — not a soft reference.

3. **`guest/modules/input.nix:44-45` and `guest/modules/session.nix:77`** put `"korri-compositor.service"`, `"korri-inputd.service"`, and `"korri-kiosk.service"` directly in substrate `before` arrays. A non-Korri product whose units are named differently inherits no ordering — raw gamepads are not hidden before its compositor starts.

4. **`nix/tests/main-space-systemd-contract.nix:31`** and **`nix/tests/audio-input-systemd-contract.nix:43,61`** call `assertContract` on the literal string `"korri-kiosk.service"`. The substrate's CI **requires** Korri's unit name to appear in its own ordering arrays. A non-Korri product cannot pass substrate CI without naming its kiosk `korri-kiosk.service`.

### What U4's audit also missed

Beyond the four load-bearing leaks, the audit found:

5. **`patches/rocknix/0003-sm8550-device-and-host-config.patch`** ships the Korri SVG path data and the Korri green/white color palette directly inside the `rocknix-splash` patch (boot logo). The substrate boots to Korri branding regardless of which payload is selected.
6. **`packages/steam/`, `packages/cemu/`, `packages/moonlight-embedded/`, and `packages/inputplumber/`'s product-specific controller maps** are all product-stack choices, not SM8550 substrate capabilities.
7. **`guest/launchers/`** ships ~13 product-shaped shell launchers (Cemu, BOTW, Moonlight pairing, the Korri games-launcher, etc.), two of which literally `systemctl start korri-kiosk.service`.
8. **`scripts/check-boundary-lint`** is itself product-aware — it asserts on Cemu, Steam, and BOTW package internals.
9. **No `docs/contracts/product-blind-invariants.md`** existed to give Plan 003's retro something concrete to test against. The unwritten invariant is what let the retro re-derive "what counts as a leak" and land on a wrong answer.
10. **No second product** has ever consumed the substrate, so the product-blind claim has never been validated by an existence proof.

### Why the plan flips to `active`

The original Phase 5 intent was "substrate fully product-blind so a third product would not need any substrate changes to onboard." That intent is not met today. U2 and U3 shipped, but U4's no-op conclusion was the wrong call, and the audit revealed substantial scope U1-U4 did not consider.

The remaining work is captured in the Korri backlog with PR-shaped grouping ("swings"), not re-scoped under this plan. Sequencing and design questions live with the tasks.

Referenced Korri backlog items (in `simonwjackson/korri` repository, `backlog/`):

- **Swing 1 — task-032** parameterize substrate kiosk coupling and write `docs/contracts/product-blind-invariants.md` (closes leaks 1–4 and 9)
- **Swing 2 — task-022, task-023, task-024, task-025** move `packages/{steam,cemu,moonlight-embedded,inputplumber}` out of the substrate (closes leak 6)
- **Swing 3 — task-026** move product-shaped launchers out of `guest/launchers/` (closes leak 7)
- **Swing 4 — task-029** strip product-specific positive assertions from `scripts/check-boundary-lint` (closes leak 8)
- **Swing 5 — task-031** stand up a stub second product to dogfood the inversion (closes leak 10)
- **task-021** move boot-logo ownership from substrate to Korri (closes leak 5)
- **task-001** delete `guest/modules/moonlight.nix` from the substrate (the U4 follow-up surfaced before this audit; subsumed into task-024 when Swing 2 picks it up)

This plan stays `active` until either (a) Swings 1–5 land and a substrate-only build with no Korri payload proves product-blindness end-to-end, or (b) the plan is explicitly retired in favor of a fresh "Phase 6" plan that owns the swing-shaped work as its own scope. As of this revisit, neither has happened.
