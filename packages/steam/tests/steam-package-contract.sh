#!/usr/bin/env bash
set -euo pipefail

PACKAGE_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT_DIR="$PACKAGE_DIR/scripts"
MANIFEST="$PACKAGE_DIR/manifest.nix"
README="$PACKAGE_DIR/README.md"

fail() { echo "FAIL: $*" >&2; exit 1; }

for script in \
  steam-arm64-bootstrap \
  steam-arm64-seed \
  steam-guest-native \
  steam-guest-runtime-prep \
  steam-guest-run; do
  [ -f "$SCRIPT_DIR/$script" ] || fail "missing package script: $script"
done

grep -q 'Steam Runtime / pressure-vessel repair' "$README" \
  || fail "README must describe package-owned Steam Runtime / pressure-vessel repair"
grep -q 'FHS Steam execution capsule' "$README" \
  || fail "README must describe the package-owned FHS Steam execution capsule"
grep -q 'not a product compatibility surface' "$README" \
  || fail "README must state x86 support is not a product compatibility surface"

grep -q 'steam-guest-runtime-prep' "$MANIFEST" \
  || fail "manifest must list steam-guest-runtime-prep in the package contract"
grep -q 'steam-guest-run' "$MANIFEST" \
  || fail "manifest must list steam-guest-run in the package contract"

if grep -R -nE '\b(systemctl|swaymsg|gamescope)\b|services\.korri|korri\.' "$SCRIPT_DIR"; then
  fail "Steam package scripts must not own system/session/product orchestration"
fi

if grep -R -n '/storage' "$SCRIPT_DIR"; then
  fail "Steam package scripts must not hardcode guest /storage defaults"
fi

expect_missing_env_failure() {
  local script="$1" env_name="$2"
  local out status
  set +e
  out=$(env -i PATH="$PATH" bash "$SCRIPT_DIR/$script" --check 2>&1)
  status=$?
  set -e
  [ "$status" -ne 0 ] || fail "$script --check should fail without $env_name"
  printf '%s\n' "$out" | grep -q "$env_name" \
    || fail "$script missing-env error should mention $env_name"
}

expect_missing_env_failure steam-guest-runtime-prep STEAM_HOME
expect_missing_env_failure steam-guest-run STEAM_HOME

echo "steam-package-contract: ok"
