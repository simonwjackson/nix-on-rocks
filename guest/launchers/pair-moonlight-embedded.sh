#!/usr/bin/env nix-shell
#! nix-shell -i bash --pure
#! nix-shell -p coreutils gawk gnugrep
#
# pair-moonlight-embedded.sh -- CLI pair the moonlight-embedded client
# (the SM8550 zero-copy build) with a Sunshine host.
#
# Why a separate script from guest/launchers/pair-moonlight.sh:
#
#   pair-moonlight.sh targets Moonlight-Qt (different binary, different
#   keystore at ~/.config/Moonlight\ Game\ Streaming\ Project/). The
#   embedded CLI client uses a separate keystore under
#   /storage/.cache/moonlight (the same path the streaming launcher reads
#   via guest/launchers/start_moonlight_embedded_gamescope.sh).
#
#   Pairing the wrong client leaves the operator with a confusing
#   half-paired setup -- the Qt pair script will not establish trust the
#   embedded CLI can use, and vice versa. Keep the scripts separate so
#   "which client am I pairing" is a script-name choice, not an env-var
#   conditional.
#
# Run from a regular SSH shell on the guest, NOT from inside the kiosk
# Sway session:
#
#   MOONLIGHT_BIN=/nix/store/...-moonlight-embedded-*/bin/moonlight \
#       /storage/.guest/pair-moonlight-embedded.sh <host> [pin]
#
# Examples:
#
#   MOONLIGHT_BIN=$(command -v moonlight) pair-moonlight-embedded.sh aka
#   pair-moonlight-embedded.sh 192.168.1.117 4242
#
# If MOONLIGHT_BIN is unset, the script falls back to `command -v moonlight`
# on PATH. Out-of-band deploys (plan 003 U6's `nix copy` flow) set
# MOONLIGHT_BIN to a specific store path. The same resolution rule lives in
# guest/launchers/start_moonlight_embedded_gamescope.sh so a single env
# export covers both pair and stream.
#
# On success, moonlight-embedded writes the host's pair cert under
# $MOONLIGHT_KEYDIR/<host>. Subsequent `moonlight stream <host> <app>`
# invocations (via the streaming launcher) reuse that cert without any
# further interaction.

set -eu

usage() {
  cat >&2 <<EOF
Usage: $(basename "$0") <host> [pin]

  host  Sunshine host name, IP, or UUID (e.g. aka, 192.168.1.117).
  pin   Optional 4-digit pairing PIN with a non-zero leading digit.
        Generated if omitted.

Env:

  MOONLIGHT_BIN     absolute path to the moonlight-embedded binary.
                    Defaults to \`command -v moonlight\`. Out-of-band
                    deploys (\`nix copy\` + ad-hoc store path) set this
                    explicitly.
  MOONLIGHT_KEYDIR  pair-state directory.
                    Defaults to /storage/.cache/moonlight.
EOF
  exit 64
}

host="${1:-}"
[ -z "$host" ] && usage

pin="${2:-}"
if [ -z "$pin" ]; then
  # 4 digits with a non-zero leading digit. Leading zeros render the PIN
  # as "0042" which can confuse operators entering it in Sunshine's PIN
  # field.
  pin=$(awk 'BEGIN{srand(); print int(rand()*9000) + 1000}')
fi

case "$pin" in
  [1-9][0-9][0-9][0-9]) ;;
  *)
    printf 'pair-moonlight-embedded: pin must be 4 digits with a non-zero leading digit, got "%s"\n' "$pin" >&2
    exit 64
    ;;
esac

# Resolve the moonlight binary. MOONLIGHT_BIN lets out-of-band deploys
# (nix copy + ad-hoc store path) point at a specific binary before the
# refactor wires the package into the guest profile. Falls back to PATH
# resolution once the profile-installed binary is available.
MOONLIGHT_BIN="${MOONLIGHT_BIN:-$(command -v moonlight 2>/dev/null || true)}"
if [ -z "$MOONLIGHT_BIN" ] || [ ! -x "$MOONLIGHT_BIN" ]; then
  cat >&2 <<EOF
pair-moonlight-embedded: moonlight binary not found.

Set MOONLIGHT_BIN to an absolute store path, or install the package via
\`rocknix.sm8550.moonlight.enable = true\` (post-refactor, plan 001 U9).

For out-of-band deploys (today's path, plan 003 U6) the flow is:

  # on the dev host (Fuji):
  nix-build -I nixpkgs=channel:nixos-25.11 -E \\
      'with import <nixpkgs> {}; callPackage ./packages/moonlight-embedded/package.nix {}'
  nix copy --to ssh-ng://root@sobo \$(readlink -f result)

  # on Sobo:
  export MOONLIGHT_BIN=/nix/store/<hash>-moonlight-embedded-2.7.1-sm8550-v4l2m2m/bin/moonlight
  pair-moonlight-embedded.sh <host> [pin]
EOF
  exit 127
fi

MOONLIGHT_KEYDIR="${MOONLIGHT_KEYDIR:-/storage/.cache/moonlight}"
if [ ! -d "$MOONLIGHT_KEYDIR" ]; then
  # The streaming launcher hard-fails here too. The
  # guest/modules/moonlight.nix `systemd.tmpfiles` rule is meant to create
  # this directory; if it's missing, the module is not yet active on the
  # target guest. Out-of-band deploys can mkdir it manually.
  printf 'pair-moonlight-embedded: keydir missing: %s\n' "$MOONLIGHT_KEYDIR" >&2
  printf '  create it (`mkdir -p %s && chmod 700 %s`) or enable\n' "$MOONLIGHT_KEYDIR" "$MOONLIGHT_KEYDIR" >&2
  printf '  rocknix.sm8550.moonlight on the guest.\n' >&2
  exit 1
fi

cat <<EOF

  ========================================
  Pairing host : $host
  PIN          : $pin
  Client       : moonlight-embedded (CLI, NOT moonlight-qt)
  Keystore     : $MOONLIGHT_KEYDIR
  Binary       : $MOONLIGHT_BIN
  ========================================

  1. Open Sunshine web UI :  https://$host:47990
  2. Type this PIN exactly :  $pin
  3. Submit                :  the page may also require a device name.

  Moonlight will block here for up to ~60s waiting for the PIN.

  Note: this script pairs the *embedded* CLI client only. If you also
  want to pair the Moonlight-Qt GUI client, run guest/launchers/
  pair-moonlight.sh separately -- it writes to a different keystore
  (~/.config/Moonlight\\ Game\\ Streaming\\ Project/).

  If Sunshine shows "Pairing Failed: Check if the PIN is typed
  correctly", the on-disk pair state on the Sunshine host probably has
  a stale entry for this client. Remove it from Sunshine's "Clients"
  page and re-run this script.

EOF

export LC_ALL=C.UTF-8

# Forward Moonlight's stdout/stderr so the operator sees Sunshine's
# verdict inline.
exec "$MOONLIGHT_BIN" -keydir "$MOONLIGHT_KEYDIR" pair "$host"
