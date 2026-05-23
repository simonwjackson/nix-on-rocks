#!/usr/bin/env bash
# remote-moonlight-build-fingerprint.sh
#
# Capture the moonlight-embedded closure's identity into a reviewable
# evidence directory under ${MOONLIGHT_RUNS_DIR}. Mirrors the shape of
# guest/launchers/remote-cemu-build-fingerprint.sh; narrower scope because
# moonlight does not own per-game state, shader caches, or candidate-vs-current
# parity. Reuses the same evidence layout so reviewers can apply the same eye.
#
# Inputs (env):
#
#   MOONLIGHT_BIN          Required. Absolute path to a moonlight binary
#                          inside a /nix/store/...-moonlight-embedded-*/bin/
#                          tree. The closure is resolved as `dirname dirname`
#                          of this path.
#   MOONLIGHT_RUNS_DIR     Where to write evidence. Default
#                          /storage/.guest/runs. Created if missing.
#
# Output: a single evidence directory printed on stdout.
#
# Exit codes:
#
#   0   evidence written
#   64  MOONLIGHT_BIN unset or missing (sysexits EX_USAGE)
#   65  closure shape unexpected (no nix-support/moonlight-embedded-build/
#       manifest.txt)
set -eu

MOONLIGHT_BIN="${MOONLIGHT_BIN:-}"
MOONLIGHT_RUNS_DIR="${MOONLIGHT_RUNS_DIR:-/storage/.guest/runs}"

if [ -z "$MOONLIGHT_BIN" ] || [ ! -x "$MOONLIGHT_BIN" ]; then
  printf 'remote-moonlight-build-fingerprint: MOONLIGHT_BIN unset or not executable\n' >&2
  exit 64
fi

CLOSURE_BIN_DIR="$(dirname -- "$MOONLIGHT_BIN")"
CLOSURE_ROOT="$(dirname -- "$CLOSURE_BIN_DIR")"
MANIFEST="$CLOSURE_ROOT/nix-support/moonlight-embedded-build/manifest.txt"

if [ ! -f "$MANIFEST" ]; then
  printf 'remote-moonlight-build-fingerprint: missing build manifest at %s\n' "$MANIFEST" >&2
  printf '  closure does not look like a moonlight-embedded package output\n' >&2
  exit 65
fi

TS="$(date '+%Y%m%d-%H%M%S')"
RUN_DIR="${MOONLIGHT_RUNS_DIR}/${TS}-moonlight-build-fingerprint"
mkdir -p "$RUN_DIR"
REPORT="$RUN_DIR/report.md"

have() { command -v "$1" >/dev/null 2>&1; }

section() {
  printf '\n### %s\n\n```text\n' "$1" >> "$REPORT"
}
end_section() {
  printf '```\n' >> "$REPORT"
}

run_into() {
  local title="$1"; shift
  section "$title"
  "$@" >>"$REPORT" 2>&1 || printf '\n(command failed: %s)\n' "$*" >>"$REPORT"
  end_section
}

cat > "$REPORT" <<EOF
# moonlight-embedded build fingerprint

- Timestamp: $(date -Iseconds)
- Host: $(uname -n) ($(uname -m))
- Binary: \`$MOONLIGHT_BIN\`
- Closure root: \`$CLOSURE_ROOT\`
- Evidence dir: \`$RUN_DIR\`

## Build manifest

\`\`\`text
$(cat "$MANIFEST")
\`\`\`
EOF

run_into "moonlight --help (first 40 lines, captures version + advertised platforms)" \
  bash -c "'$MOONLIGHT_BIN' 2>&1 | head -40"

if have file; then
  run_into "file" file "$MOONLIGHT_BIN"
fi

if have readelf; then
  run_into "ELF header" readelf -h "$MOONLIGHT_BIN"
  run_into "dynamic NEEDED/RPATH/RUNPATH" bash -c "readelf -d '$MOONLIGHT_BIN' | grep -E 'NEEDED|RPATH|RUNPATH|FLAGS' || true"
fi

if have ldd; then
  run_into "ldd" ldd "$MOONLIGHT_BIN"
fi

if [ -d "$CLOSURE_ROOT/nix-support/moonlight-embedded-build" ]; then
  section "nix-support/moonlight-embedded-build/ contents"
  ls -la "$CLOSURE_ROOT/nix-support/moonlight-embedded-build" >>"$REPORT" 2>&1
  end_section
  if [ -f "$CLOSURE_ROOT/nix-support/moonlight-embedded-build/CMakeCache.txt" ]; then
    section "selected CMakeCache flags"
    grep -E 'ENABLE_|CMAKE_BUILD_TYPE|FFmpeg|SDL|libdrm|libglvnd' \
      "$CLOSURE_ROOT/nix-support/moonlight-embedded-build/CMakeCache.txt" \
      >>"$REPORT" 2>&1 || true
    end_section
  fi
fi

if have nix-store; then
  run_into "nix-store --query --references (direct)" \
    bash -c "nix-store --query --references '$CLOSURE_ROOT' 2>/dev/null | sort"
fi

printf '%s\n' "$RUN_DIR"
