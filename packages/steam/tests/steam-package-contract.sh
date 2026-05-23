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
grep -q 'not a Korri compatibility surface' "$README" \
  || fail "README must state x86 support is not a Korri compatibility surface"

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

if [ -n "${PACKAGE_OUT:-}" ]; then
  [ -x "$PACKAGE_OUT/bin/steam-arm64-bootstrap" ] || fail "built package missing steam-arm64-bootstrap"
  [ -x "$PACKAGE_OUT/bin/steam-arm64-seed" ] || fail "built package missing steam-arm64-seed"
  [ -x "$PACKAGE_OUT/bin/steam-guest-native" ] || fail "built package missing steam-guest-native"
  [ -x "$PACKAGE_OUT/bin/steam-guest-runtime-prep" ] || fail "built package missing steam-guest-runtime-prep"
  [ -x "$PACKAGE_OUT/bin/steam-guest-run" ] || fail "built package missing steam-guest-run"
  grep -q 'steam-runtime-prep-helper=bin/steam-guest-runtime-prep' "$PACKAGE_OUT/nix-support/rocknix-steam-bootstrap/manifest.txt" \
    || fail "built package evidence missing runtime prep helper"
  grep -q 'steam-run-capsule=' "$PACKAGE_OUT/nix-support/rocknix-steam-bootstrap/manifest.txt" \
    || fail "built package evidence missing run capsule entry"
  if grep -q 'steam-run-capsule=bin/steam-arm64-fhs' "$PACKAGE_OUT/nix-support/rocknix-steam-bootstrap/manifest.txt"; then
    [ -x "$PACKAGE_OUT/bin/steam-arm64-fhs" ] || fail "aarch64 package evidence claims missing steam-arm64-fhs"
  fi

  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  mkdir -p "$tmp/Steam/steamrtarm64"
  : > "$tmp/Steam/steamrtarm64/steam"
  chmod 755 "$tmp/Steam/steamrtarm64/steam"
  STEAM_HOME="$tmp/Steam" FEX_ROOTFS="$tmp/fex" \
    "$PACKAGE_OUT/bin/steam-guest-run" --check >/tmp/steam-guest-run-built-check.out
  [ ! -e "$tmp/Steam/prep-applied" ] || fail "built steam-guest-run --check must not apply mutable prep"
fi

echo "steam-package-contract: ok"
