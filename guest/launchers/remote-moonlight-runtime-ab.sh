#!/usr/bin/env bash
# remote-moonlight-runtime-ab.sh
#
# Run two consecutive moonlight smokes with different -platform values and
# write a side-by-side evidence report. Mirrors guest/launchers/
# remote-cemu-runtime-ab.sh in shape; scope is narrower (one knob -- the
# moonlight platform -- rather than candidate-vs-current binary parity).
#
# Used to quantify the sdl -> v4l2m2m delta that justifies patch 0002 in
# repo history (per plan 003 U5: "U6's learning doc benefits from a
# quantified sdl->v4l2m2m delta to justify the patch's existence").
#
# Usage:
#
#   remote-moonlight-runtime-ab.sh [variant-a] [variant-b]
#
#   variant-a / variant-b   moonlight -platform values. Defaults: sdl v4l2m2m.
#
# All MOONLIGHT_* knobs read by remote-moonlight-runner.sh are forwarded.
# The two runs share host / app / keydir / audio gate / duration so the
# delta is attributable to the platform alone.
#
# Output: parent dir ${MOONLIGHT_RUNS_DIR}/<ts>-moonlight-runtime-ab/
# containing one subdir per variant and a top-level evidence.md report.
set -eu

VARIANT_A="${1:-sdl}"
VARIANT_B="${2:-v4l2m2m}"

MOONLIGHT_RUNS_DIR="${MOONLIGHT_RUNS_DIR:-/storage/.guest/runs}"
MOONLIGHT_HOST="${MOONLIGHT_HOST:-}"
MOONLIGHT_APP="${MOONLIGHT_APP:-Desktop}"
MOONLIGHT_DURATION_S="${MOONLIGHT_DURATION_S:-30}"

# Locate the sibling runner script. Prefer /storage/.guest/ (operator-deployed)
# else next to this script in-tree.
RUNNER=""
for candidate in \
    "/storage/.guest/remote-moonlight-runner.sh" \
    "$(dirname -- "$0")/remote-moonlight-runner.sh"; do
  if [ -x "$candidate" ]; then
    RUNNER="$candidate"
    break
  fi
done
if [ -z "$RUNNER" ]; then
  printf 'remote-moonlight-runtime-ab: cannot locate remote-moonlight-runner.sh\n' >&2
  exit 127
fi

TS="$(date '+%Y%m%d-%H%M%S')"
PARENT_DIR="${MOONLIGHT_RUNS_DIR}/${TS}-moonlight-runtime-ab"
mkdir -p "$PARENT_DIR"
REPORT="$PARENT_DIR/evidence.md"

cat > "$REPORT" <<EOF
# moonlight-embedded runtime A/B

- Timestamp: $(date -Iseconds)
- Host: $(uname -n) ($(uname -m))
- Sunshine host: \`${MOONLIGHT_HOST:-not-set}\`
- App: \`$MOONLIGHT_APP\`
- Per-run duration: ${MOONLIGHT_DURATION_S}s
- Variant A: \`$VARIANT_A\`
- Variant B: \`$VARIANT_B\`

## Variant summary

| Variant | Platform | Evidence dir | Exit |
|---------|----------|--------------|------|
EOF

run_one() {
  local label="$1" platform="$2"
  local run_dir exit_code run_output
  set +e
  run_output=$(env \
    MOONLIGHT_RUNS_DIR="$PARENT_DIR/runs" \
    MOONLIGHT_HOST="$MOONLIGHT_HOST" \
    MOONLIGHT_APP="$MOONLIGHT_APP" \
    MOONLIGHT_PLATFORM="$platform" \
    MOONLIGHT_DURATION_S="$MOONLIGHT_DURATION_S" \
    "$RUNNER" 2>>"$PARENT_DIR/dispatch.log")
  exit_code=$?
  run_dir=$(printf '%s\n' "$run_output" | tail -1)
  set -e
  printf '| %s | `%s` | `%s` | %s |\n' \
    "$label" "$platform" "${run_dir:-?}" "$exit_code" >> "$REPORT"
  # Inline a short cross-link to the runner telemetry and launch log for reviewers.
  if [ -n "$run_dir" ] && [ -d "$run_dir" ]; then
    {
      printf '\n### %s (`%s`) telemetry\n\n```text\n' "$label" "$platform"
      [ -f "$run_dir/telemetry-summary.txt" ] && cat "$run_dir/telemetry-summary.txt" || printf 'telemetry-summary.txt missing\n'
      printf '\n\n--- signals ---\n'
      [ -f "$run_dir/signals.txt" ] && cat "$run_dir/signals.txt" || printf 'signals.txt missing\n'
      printf '\n```\n'
    } >> "$REPORT"
  fi
  if [ -n "$run_dir" ] && [ -f "$run_dir/launch.log" ]; then
    {
      printf '\n### %s (`%s`) launch.log tail\n\n```text\n' "$label" "$platform"
      tail -40 "$run_dir/launch.log" 2>/dev/null || true
      printf '\n```\n'
    } >> "$REPORT"
  fi
}

run_one "A" "$VARIANT_A"
run_one "B" "$VARIANT_B"

cat >> "$REPORT" <<'EOF'

## How to read this report

Each variant subdirectory under `runs/` carries the same evidence layout
the single-shot runner produces (`env.txt`, `host-state.txt`,
`launch.log`, optional `screenshot.png`). Compare across variants by
diffing `host-state.txt` (governor + thermal sanity) and inspecting
`launch.log` for decoder/EGL signals.

For the sdl -> v4l2m2m delta that justifies patch 0002, look for:

  - Frame drops per second in `launch.log` (moonlight verbose output).
  - `EGL_BAD_*` errors in `launch.log` for the v4l2m2m variant only.
  - `dmesg` iris errors captured under `host-state.txt`.
EOF

printf '%s\n' "$PARENT_DIR"
