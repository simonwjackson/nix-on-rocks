# Monorepo merge — operational notes

**Status:** in-progress
**Plan:** [`docs/plans/2026-05-22-001-refactor-monorepo-merge-layered-restructure-plan.md`](../plans/2026-05-22-001-refactor-monorepo-merge-layered-restructure-plan.md)
**Branch:** `refactor/monorepo-merge`
**Worktree:** `.worktrees/monorepo-merge`

---

## Source SHAs (baseline)

Both repos tagged `pre-merge-baseline-2026-05-22` immediately before structural work began.

| Repo | Commit | Tag |
|---|---|---|
| `nix-on-rocks` | `537b92f148629ba42c561f9e52a25dce6a90fad2` | `pre-merge-baseline-2026-05-22` (tag object `3f21229`) |
| `nix-sm8550` | `2fe90b14688e7f6a032e3621c302be6710c5e5f3` | `pre-merge-baseline-2026-05-22` (tag object `1e240f6`) |

---

## What changed (filled in as units complete)

- [ ] **U1 — Snapshot & branch** (in progress)
- [ ] U2 — Subtree import nix-sm8550 → `incoming-nix-sm8550/`
- [ ] U3 — Atomic flake-promote to root + package move (`guest/packages/` → `packages/`, `guest/flake.nix` → `flake.nix`)
- [ ] U4 — Absorb nix-sm8550 packages, carve `devices/sm8550/` slot, parameterize cemu via `socSettings`
- [ ] U5 — Sobo integration smoke
- [ ] U6 — Cleanup, README, merge to main

---

## Rollback procedure

If something goes sideways before U6 lands on main:

```bash
# From nix-on-rocks parent dir
git worktree remove .worktrees/monorepo-merge --force
git branch -D refactor/monorepo-merge

# Tags survive (intentional)
git tag -l 'pre-merge-baseline-2026-05-22'
```

main is untouched throughout. If U6 has already landed and a regression surfaces:

```bash
# Revert the merge commit
git checkout main
git revert -m 1 <merge-commit-sha>
# Or hard reset to the baseline tag (destructive; coordinate first):
# git reset --hard pre-merge-baseline-2026-05-22
```

If `nix-sm8550` has been archived (U7) and needs to be revived:

```bash
cd ../nix-sm8550
git reset --hard pre-merge-baseline-2026-05-22
git push --force-with-lease origin main
# (Then unarchive the GitHub repo via Settings → Archive)
```

---

## Coordination with parallel moonlight-embedded work

The moonlight-embedded worktree (separate session, separate branch) is staging files at:

- `packages/moonlight-embedded/` (top-level)
- `guest/launchers/start_moonlight_embedded_gamescope.sh`
- `guest/launchers/pair-moonlight.sh`
- `guest/modules/moonlight.nix`
- `scripts/moonlight-embedded-dev-checkout.sh`

Activation (profile import wiring) is deferred until this refactor lands. Coordination posture: **whoever lands second rebases.**

- If this refactor lands first: parallel branch rebases onto post-U6 main, wires moonlight into a profile import (since U4 will have added the flake output).
- If parallel branch lands first: U4 sees `packages/moonlight-embedded/` already exists; skip the move-from-quarantine for moonlight; verify the existing version is a superset of nix-sm8550's; drop `incoming-nix-sm8550/packages/moonlight-embedded/` outright.

---

## Out of scope (intentional non-goals; see plan Scope Boundaries for full list)

- Boundary lint
- `host-substrate/` rename of `patches/rocknix/`
- specialArgs injection mandate across modules
- Anything for Retroid Pocket Mini (sm8250) — slot exists, population is its own future work
- Moonlight-embedded patch / launcher / module work (handled in parallel)
- nix-sm8550 archive (deferred U7, not blocking)
