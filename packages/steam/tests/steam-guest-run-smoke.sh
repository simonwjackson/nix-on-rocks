#!/usr/bin/env bash
set -euo pipefail

PACKAGE_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$PACKAGE_DIR/scripts/steam-guest-run"

fail() { echo "FAIL: $*" >&2; exit 1; }
[ -f "$SCRIPT" ] || fail "missing run capsule script: $SCRIPT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

steam_home="$tmp/Steam"
mkdir -p "$steam_home/steamrtarm64"
bash_path="${BASH:-$(command -v bash)}"
cat > "$steam_home/steamrtarm64/steam" <<EOS
#!$bash_path
set -euo pipefail
printf 'client-args=%s\\n' "\$*" >> "\$STEAM_CLIENT_LOG"
printf 'client-pv=%s\\n' "\$PRESSURE_VESSEL_FILESYSTEMS_RW" >> "\$STEAM_CLIENT_LOG"
EOS
chmod 755 "$steam_home/steamrtarm64/steam"

prep_log="$tmp/prep.log"
prep_hook="$tmp/runtime-prep"
cat > "$prep_hook" <<EOS
#!$bash_path
set -euo pipefail
printf '%s\\n' "\$1" >> "\$PREP_LOG"
if [ "\$1" = --apply ]; then
  : > "\$STEAM_HOME/prep-applied"
fi
EOS
chmod 755 "$prep_hook"

set +e
out=$(STEAM_HOME="$steam_home" STEAM_RUNTIME_PREP="$prep_hook" PREP_LOG="$prep_log" bash "$SCRIPT" --check 2>&1)
status=$?
set -e
[ "$status" -ne 0 ] || fail "--check should fail when FEX_ROOTFS is absent"
printf '%s\n' "$out" | grep -q 'FEX_ROOTFS' || fail "missing FEX_ROOTFS error should name FEX_ROOTFS"

out=$(STEAM_HOME="$steam_home" FEX_ROOTFS="$tmp/fex" STEAM_RUNTIME_PREP="$prep_hook" PREP_LOG="$prep_log" PRESSURE_VESSEL_FILESYSTEMS_RW="/already" bash "$SCRIPT" --check)
printf '%s\n' "$out" | grep -q 'PRESSURE_VESSEL_FILESYSTEMS_RW=/dev/uinput:/dev/input:/already' \
  || fail "--check should report merged pressure-vessel paths"
grep -q -- '--check' "$prep_log" || fail "--check should call runtime prep in check mode"
[ ! -e "$steam_home/prep-applied" ] || fail "--check must not apply mutable runtime prep"

missing_home="$tmp/MissingSteam"
mkdir -p "$missing_home"
set +e
out=$(STEAM_HOME="$missing_home" FEX_ROOTFS="$tmp/fex" STEAM_RUNTIME_PREP="$prep_hook" PREP_LOG="$prep_log" bash "$SCRIPT" --check 2>&1)
status=$?
set -e
[ "$status" -ne 0 ] || fail "--check should fail when the Steam client is missing"
printf '%s\n' "$out" | grep -q 'guest-native Steam client is missing' \
  || fail "missing client error should preserve the existing clear hint"

client_log="$tmp/client.log"
STEAM_HOME="$steam_home" \
FEX_ROOTFS="$tmp/fex" \
STEAM_RUNTIME_PREP="$prep_hook" \
PREP_LOG="$prep_log" \
STEAM_CLIENT_LOG="$client_log" \
bash "$SCRIPT" --run -steamdeck -gamepadui

grep -q -- '--apply' "$prep_log" || fail "--run should apply runtime prep"
[ -e "$steam_home/prep-applied" ] || fail "--run should allow runtime prep mutation"
grep -q 'client-args=-steamdeck -gamepadui' "$client_log" \
  || fail "--run should exec the Steam client with caller-provided args"
grep -q 'client-pv=/dev/uinput:/dev/input' "$client_log" \
  || fail "--run should expose input devices to pressure-vessel by default"

echo "steam-guest-run-smoke: ok"
