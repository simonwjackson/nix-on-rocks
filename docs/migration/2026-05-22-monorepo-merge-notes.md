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

- [x] **U1** — Snapshot & branch (`e076ed0`)
- [x] **U2** — Subtree import nix-sm8550 → `incoming-nix-sm8550/` (`119524e` + `2c33fe6`)
- [x] **U3** — Atomic flake-promote to root + package move (`5a517c3`)
  - `guest/flake.nix` → `flake.nix`
  - `guest/flake.lock` → `flake.lock`
  - `guest/packages/` → `packages/`
  - 37 files reorganized; static-checks re-anchored with `REPO_ROOT`; CI workflow `build-rootfs-seed.yml` updated
- [x] **U4** — Absorb nix-sm8550 packages, carve `devices/sm8550/` slot, parameterize cemu (`1ab41de`)
  - `devices/{,sm8550/}README.md` (new slot, documented for sm8250/Retroid)
  - `devices/sm8550/audio/ayn-odin2-ucm/` (moved from `packages/audio/`)
  - `devices/sm8550/cemu/settings.xml` (moved from `packages/cemu/settings.SM8550.xml`)
  - `packages/cemu/package.nix` parameterized with `socSettings ? null, socName ? null`
  - `packages/moonlight-embedded/` absorbed (with PR #932 patches); `opus` → `libopus` for nixos-25.11
  - `packages/inputplumber/sm8550/` → `packages/inputplumber/maps/` (per-MCU naming honesty)
  - Flake outputs: `+moonlight-embedded`, `+sm8550-ayn-odin2-ucm` (alias)
  - Quarantine packages/ emptied (cemu/steam superseded, moonlight-embedded migrated)
- [x] **U5a** — Build smoke (eval + x86_64 native)
  - `nix build .#sm8550-ayn-odin2-ucm` succeeded on zao
  - drvPaths evaluate clean for: cemu, steam, moonlight-embedded, inputplumber, rootfs-{thor,odin2portal}, and 5 pure nixosConfigurations
  - Full builds (especially cemu source compile) deferred to fuji aarch64 in U5b
- [x] **U5b** — aarch64 build smoke on fuji (Tailscale-reachable Linux aarch64 NixOS, 4 cores / 23 GiB RAM)
  - **13m26s total** (02:56:27 → 03:09:53 UTC) to build all 6 targets, +2 GB store growth
  - All 5 refactored packages built natively on aarch64:
    - `cemu-rocknix-package-2.999.0-rocknix-package` (full source compile, 542 cmake steps)
    - `steam-rocknix-guest-native-1.0.0.85-rocknix-guest-native`
    - `moonlight-embedded-2.7.1-sm8550-v4l2m2m` (vendored ffmpeg + PR #932 patches)
    - `rocknix-inputplumber-0.75.2`
    - `ayn-odin2-ucm-2026-05-11`
  - Plus base `nixos-system-rocknix-guest-25.11.20260505.0c88e1f` (korri-free guest toplevel)
  - **Refactor-specific artifact verification** (all green):
    - cemu output bundles `share/Cemu/config/SM8550/settings.xml` — proves `socSettings`/`socName` callPackage parameterization injects data from `devices/sm8550/cemu/settings.xml` end-to-end
    - sm8550-ayn-odin2-ucm output contains `share/alsa/ucm2/AYN/Odin2/HiFi.conf` + `conf.d/sm8550/{AYN-Odin2,AYN-Thor,AYNThor,ayn-AYNOdin2-,SM8550-HDK}.conf` symlinks — proves the `packages/audio/` → `devices/sm8550/audio/` move preserved the alias topology
    - inputplumber output contains `share/inputplumber/{devices,capability_maps,profiles,schema}/` — proves the `packages/inputplumber/sm8550/` → `packages/inputplumber/maps/` rename + `${./maps}` source path works
    - moonlight-embedded binary runs (`Moonlight Embedded 2.7.1`) — proves the `opus → libopus` nixpkgs rename works on aarch64
  - Korri-composing variants (`rocknix-guest-main-space-*`) NOT built; korri-bun-deps fixed-output hash drift on aarch64 is a pre-existing orthogonal issue documented separately in `docs/migration/2026-05-22-korri-dependency-direction-violation.md`
- [ ] **U6 merge** — Merge `refactor/monorepo-merge` → `main`, tag `monorepo-merge-complete-2026-05-22`
  - **No longer gated on Sobo deploy.** Sobo's currently-running production rootfs predates the merge and continues to work; redeploy is appropriately decoupled (see Sobo deploy strategy in korri-dependency doc).
  - Now gated only on user's go/no-go for the merge itself.

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
