---
title: "fix: rocknix-guest-root-ensure must clear helper-owned immutable bits before deleting stale previous root"
type: fix
status: draft
date: 2026-05-29
related-acceptance: docs/acceptance/sm8550-product-payload-thor-bandai-2026-05-29.md
related-ops: docs/ops/sm8550-full-install-safety-audit-2026-05-20.md
---

# fix: rocknix-guest-root-ensure must clear helper-owned immutable bits before deleting stale previous root

## Summary

On the first Thor cutover (2026-05-29) `rocknix-guest-root-ensure` aborted while trying to delete the retained `previous/` guest root because some helper-managed paths under `previous/var/empty` had the immutable bit (`chattr +i`) set. The current deletion path is a plain `rm -rf`, which cannot remove immutable inodes, and the operator had to manually `chattr -R -i` and re-run the unit.

The same trap will fire on every device the first time a seed revision changes after a helper-owned `previous/` exists. It is a hard blocker for hands-off reseed in the field.

## Background

From the Thor acceptance evidence:

```text
rocknix-guest-root-ensure: packaged seed revision 120b8d0d857e... replaces current seed revision d5d00fe4b588...; reseeding before guest start
rm: can't remove '/storage/nix-on-rock/rootfs/previous/var/empty': Operation not permitted
rocknix-guest-root-ensure: FAIL: failed to remove previous guest root: /storage/nix-on-rock/rootfs/previous
```

The relevant code is in
`work/rocknix/projects/ROCKNIX/packages/tools/rocknix-guest-substrate/scripts/rocknix-guest-root-ensure`
at the `rotate_previous_root` / pre-rotate cleanup section, around line 479:

```sh
if [ -e "${previous_root}" ]; then
  if ! ( validate_rootfs "${previous_root}" no ) && [ ! -f "${previous_root}/${SEED_COMPLETE_MARKER}" ]; then
    fail "previous guest root exists and is neither valid nor helper-owned: ${previous_root}"
  fi
  rm -rf "${previous_root}" || fail "failed to remove previous guest root: ${previous_root}"
fi
```

Two important properties this fix must preserve:

- the existing **helper-ownership guard**: we still must not blindly `rm -rf` a directory that does not look helper-owned. The check uses `validate_rootfs` and the `SEED_COMPLETE_MARKER` sentinel and must not be weakened.
- the **fail-closed posture**: if we cannot delete after best-effort cleanup, we must still `fail` and leave the device in a recoverable state, not silently continue.

## Goal

When `rocknix-guest-root-ensure` decides it is allowed to delete a helper-owned `previous/` (or a failed `current.tmp.*`), it must succeed on filesystems where helper-owned files have the immutable bit set, without requiring operator intervention.

## Non-goals

- Not adding immutable bits anywhere new. We are not changing the policy of why `chattr +i` exists upstream; we are just ensuring the helper that owns the data can delete it.
- Not loosening the helper-ownership guard.
- Not touching ABL, firmware, or any Layer 1–13 substrate concerns.
- Not changing the SSH-key reseed behavior. That is a separate plan.

## Approach

A single substrate patch unit plus a static-check guard. Lives entirely inside `patches/rocknix/0006-rocknix-guest-substrate.patch` and `guest/scripts/static-checks.sh`.

### U1 — `clear_helper_immutable` helper + use sites

Add a tiny POSIX-sh helper at the top of `rocknix-guest-root-ensure`:

```sh
# Recursively clear the immutable bit under $1 when the path looks helper-owned.
# Best-effort: chattr may be missing on minimal initramfs reuse, in which case
# this is a no-op and the caller will still attempt rm -rf and fail closed.
clear_helper_immutable() {
  target="$1"
  [ -e "$target" ] || return 0
  command -v chattr >/dev/null 2>&1 || return 0
  chattr -R -i "$target" >/dev/null 2>&1 || true
}
```

Call it from the two deletion sites that own helper data:

1. Stale-previous rotation (line ~479):

   ```sh
   clear_helper_immutable "${previous_root}"
   rm -rf "${previous_root}" || fail "..."
   ```

2. Failed-candidate cleanup (`tmp_root` rollback near line 231, plus any other helper-owned cleanup that already passes the ownership guard).

**Do not** call `clear_helper_immutable` against `${GUEST_ROOT}` while it is still the live root, and **do not** call it before the ownership guard runs. Wrap calls so the static call graph reads "guard, then clear, then rm".

### U2 — Static-check assertions

Add to `guest/scripts/static-checks.sh` (mirrored into the substrate's bundled `tests/guest-substrate-static-checks.sh`) under the existing `rocknix-guest-root-ensure` block:

- `grep -q 'clear_helper_immutable()' rocknix-guest-root-ensure` — helper defined
- `grep -B1 'rm -rf "${previous_root}"' rocknix-guest-root-ensure | grep -q 'clear_helper_immutable "${previous_root}"'` — called immediately before the previous-root delete
- Same pattern for the failed-candidate cleanup site
- `! grep -q 'chattr.*${GUEST_ROOT}"$' rocknix-guest-root-ensure` — never targets the live root
- The existing helper-ownership guard lines must still be present (regression guard so a later refactor cannot move the chattr above the guard)

### U3 — Optional one-shot recovery hook (defer decision)

There may be devices in the field that already have stale immutable `previous/` from before this fix. Decision required at review time: do we

- (a) rely on U1 to fix them automatically on their next reseed (recommended, simpler), or
- (b) ship a one-shot `rocknix-guest-previous-cleanup.service` that runs once on Layer 14 boot, clears helper-owned immutable bits under any retained `previous/`, and disables itself?

Default to (a). Only adopt (b) if there is real fleet exposure.

## Validation

Local (no CI):

- `bash work/rocknix/projects/ROCKNIX/packages/tools/rocknix-guest-substrate/tests/guest-substrate-static-checks.sh`
- `shellcheck -s sh work/rocknix/projects/ROCKNIX/packages/tools/rocknix-guest-substrate/scripts/rocknix-guest-root-ensure`
- `scripts/apply-rocknix-patches --product odin2portal`
- `scripts/apply-rocknix-patches --product thor`
- Synthetic test in a scratch dir:

  ```sh
  d=$(mktemp -d)
  mkdir -p "$d/previous/var/empty"
  touch "$d/previous/.rocknix-guest-rootfs-seed-complete"
  sudo chattr +i "$d/previous/var/empty"  # simulate the trap
  ROCKNIX_GUEST_ROOTFS_DIR="$d" rocknix-guest-root-ensure --reseed-only ...
  ```

  Expect: success, `previous/` removed, no operator action.

CI:

- `build-image-only.yml` against `odin2portal` (one image, ~10 min)

Device:

- One sobo reseed cycle (`/flash/rocknix.reseed-guest`) after the image lands. Expect clean reseed with no manual intervention. Capture evidence under `docs/acceptance/`.
- Thor re-acceptance is **not required**: the Thor fleet of one already has its `previous/` problem cleared from this session. Future Thor reseeds will validate U1 transparently.

## Risks

- `chattr` is missing on the reuse path. Mitigated by `command -v chattr || return 0`; falls back to existing `fail`-closed behavior.
- A future refactor moves the `chattr` above the ownership guard and weakens safety. Mitigated by static-check assertion that the guard must still run first.
- A path outside `previous/` accidentally inherits an `i` flag. Out of scope; helper only touches `previous/` and `current.tmp.*`.

## Lifecycle

`status: draft` → `status: active` after PR review → `status: completed` on first device acceptance.
