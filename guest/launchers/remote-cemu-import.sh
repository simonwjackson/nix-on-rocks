#!/bin/sh
# remote-cemu-import.sh -- copy a built Cemu candidate closure into Thor's guest store.
#
# Runs on the machine that has the candidate /nix/store path (for example fuji
# or a local builder). It does not promote the package; it only imports and
# optionally GC-roots the closure inside the Layer 14 guest so validation can
# launch it with CEMU_BIN=/nix/store/.../bin/cemu.
set -eu

PATH=/run/current-system/sw/bin:/usr/bin:/bin:/nix/var/nix/profiles/default/bin:$PATH
export PATH

STORE_PATH="${1:-${CEMU_STORE_PATH:-}}"
GUEST_SSH_HOST="${2:-${CEMU_IMPORT_GUEST_SSH_HOST:-root@bandai}}"
GUEST_SSH_PORT="${3:-${CEMU_IMPORT_GUEST_SSH_PORT:-2222}}"
REMOTE_NIX_STORE="${CEMU_IMPORT_REMOTE_NIX_STORE:-/run/current-system/sw/bin/nix-store}"
REMOTE_GCROOT_DIR="${CEMU_IMPORT_REMOTE_GCROOT_DIR:-/nix/var/nix/gcroots/cemu-candidates}"
KEEP_ROOT="${CEMU_IMPORT_KEEP_ROOT:-1}"

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }

usage() {
  cat >&2 <<EOF
usage: remote-cemu-import.sh /nix/store/...-cemu-rocknix-package... [root@bandai] [2222]

Environment overrides:
  CEMU_IMPORT_GUEST_SSH_HOST=$GUEST_SSH_HOST
  CEMU_IMPORT_GUEST_SSH_PORT=$GUEST_SSH_PORT
  CEMU_IMPORT_KEEP_ROOT=$KEEP_ROOT

After import, validate with:
  CEMU_BIN=${STORE_PATH:-/nix/store/...}/bin/cemu /storage/.guest/start_cemu_guest.sh <rom>
EOF
}

quote_sh() {
  printf "%s" "$1" | sed "s/'/'\\''/g; 1s/^/'/; \$s/\$/'/"
}

[ -n "$STORE_PATH" ] || { usage; exit 2; }
case "$STORE_PATH" in /nix/store/*) ;; *) echo "store path must be under /nix/store: $STORE_PATH" >&2; exit 2 ;; esac
[ -e "$STORE_PATH" ] || { echo "store path does not exist locally: $STORE_PATH" >&2; exit 1; }
[ -d "$STORE_PATH/nix-support/rocknix-cemu-build" ] || { echo "refusing to import non-direct Cemu package output: $STORE_PATH" >&2; exit 3; }
[ -x "$STORE_PATH/bin/cemu" ] || { echo "candidate lacks package entry point: $STORE_PATH/bin/cemu" >&2; exit 3; }
[ -f "$STORE_PATH/nix-support/rocknix-cemu-build/cubeb-backend-evidence.txt" ] || { echo "candidate lacks Cubeb backend evidence: $STORE_PATH" >&2; exit 3; }

log "exporting closure for $STORE_PATH"
closure_paths="$(nix-store -qR "$STORE_PATH")"
remote_path_q="$(quote_sh "$STORE_PATH")"
remote_gcroot_dir_q="$(quote_sh "$REMOTE_GCROOT_DIR")"
remote_nix_store_q="$(quote_sh "$REMOTE_NIX_STORE")"

# shellcheck disable=SC2086
nix-store --export $closure_paths | ssh -p "$GUEST_SSH_PORT" "$GUEST_SSH_HOST" \
  "set -eu; nix_store=$remote_nix_store_q; [ -x \"\$nix_store\" ] || nix_store=\$(command -v nix-store); \"\$nix_store\" --import >/dev/null"

log "verifying guest store path"
ssh -p "$GUEST_SSH_PORT" "$GUEST_SSH_HOST" \
  "set -eu; candidate=$remote_path_q; nix_store=$remote_nix_store_q; [ -x \"\$nix_store\" ] || nix_store=\$(command -v nix-store); \"\$nix_store\" -q --references \"\$candidate\" >/dev/null; [ -x \"\$candidate/bin/cemu\" ]; [ -f \"\$candidate/nix-support/rocknix-cemu-build/cubeb-backend-evidence.txt\" ]"

if [ "$KEEP_ROOT" = "1" ]; then
  base="$(basename "$STORE_PATH")"
  base_q="$(quote_sh "$base")"
  log "adding guest GC root for candidate"
  ssh -p "$GUEST_SSH_PORT" "$GUEST_SSH_HOST" \
    "set -eu; candidate=$remote_path_q; root_dir=$remote_gcroot_dir_q; base=$base_q; nix_store=$remote_nix_store_q; [ -x \"\$nix_store\" ] || nix_store=\$(command -v nix-store); mkdir -p \"\$root_dir\"; \"\$nix_store\" --add-root \"\$root_dir/\$base\" --indirect -r \"\$candidate\" >/dev/null"
fi

log "import complete: $STORE_PATH"
printf '%s\n' "$STORE_PATH"
