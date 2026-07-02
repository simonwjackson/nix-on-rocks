#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$ROOT/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }

# Compatibility entry point retained for packaged ROCKNIX substrate and
# existing operator docs. The full source-contract suite now lives in
# Nix checks plus repo-level shell/lint/docs commands; this wrapper remains
# host-shell-safe and delegates when those repo-level commands are present.
if [ -x "$REPO_ROOT/scripts/check-shell-smoke" ] \
  && [ -x "$REPO_ROOT/scripts/check-boundary-lint" ] \
  && [ -x "$REPO_ROOT/scripts/check-docs-contract" ]; then
  bash "$REPO_ROOT/scripts/check-shell-smoke"
  bash "$REPO_ROOT/scripts/check-boundary-lint"
  bash "$REPO_ROOT/scripts/check-docs-contract"
  echo "guest-static-checks: ok"
  exit 0
fi

# Packaged-source fallback: keep this path useful even when only the guest
# subtree is staged under /usr/lib/rocknix-guest-substrate/guest. Do not call
# Nix here; on-device substrate checks run in the host shell environment.
[ -f "$ROOT/rocknix-guest.nix" ] || fail "missing default guest config"
[ -f "$ROOT/justfile" ] || fail "missing guest justfile"
[ -d "$ROOT/modules" ] || fail "missing guest modules directory"
[ -d "$ROOT/profiles" ] || fail "missing guest profiles directory"
[ -d "$ROOT/launchers" ] || fail "missing guest launchers directory"
[ -f "$ROOT/profiles/rocknix-guest-base.nix" ] || fail "missing rocknix-guest-base substrate profile"
[ -f "$ROOT/profiles/main-space.nix" ] || fail "missing main-space fallback profile"

! grep -q 'services\.korri\|korri\.nixosModules\|korri\.packages' "$ROOT/profiles/rocknix-guest-base.nix" \
  || fail "rocknix-guest-base must not write or import Korri product surfaces"
! grep -q 'services\.korri\|korri\.nixosModules\|korri\.packages' "$ROOT/profiles/main-space.nix" \
  || fail "main-space fallback profile must not compose Korri product surfaces"
! grep -R -q 'services\.tailscale\|tailscale\.enable\|extraSetFlags.*accept-dns\|--accept-dns\|--hostname=.*networking\.hostName' \
  "$ROOT/modules" "$ROOT/profiles" \
  || fail "guest substrate must not configure Tailscale; downstream products own tailnet policy"
! grep -qE 'systemd\.tmpfiles\.rules.*"d /run/user' "$ROOT/modules/session.nix" "$ROOT/profiles/rocknix-guest-base.nix" \
  || fail "runtime-dir ownership must stay with logind/user-runtime-dir, not tmpfiles"
! grep -qE 'KillUserProcesses|RemoveIPC' "$ROOT"/modules/*.nix "$ROOT"/profiles/*.nix \
  || fail "runtime-dir fix must not introduce KillUserProcesses/RemoveIPC logind knobs"

while IFS= read -r launcher; do
  bash -n "$launcher" || fail "launcher has syntax errors: ${launcher#$ROOT/}"
done < <(find "$ROOT/launchers" -maxdepth 1 -type f -name '*.sh' | sort)

echo "guest-static-checks: ok"
