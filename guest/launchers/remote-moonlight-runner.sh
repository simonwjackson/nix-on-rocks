#!/usr/bin/env bash
# remote-moonlight-runner.sh
#
# Run a single moonlight-embedded streaming smoke and capture evidence into
# ${MOONLIGHT_RUNS_DIR}/<ts>-<platform>-<app-slug>/. Mirrors the shape of
# guest/launchers/remote-cemu-runner.sh; scope is narrower (no shader cache,
# no candidate-vs-current A/B at this layer, no MangoHud) because moonlight's
# concerns are different.
#
# Inputs (env, with operator overrides):
#
#   MOONLIGHT_HOST          Required. Sunshine host name, IP, or UUID.
#                           Also accepted as arg $1 to mirror the streaming
#                           launcher's positional shape.
#   MOONLIGHT_APP           Stream app (default Desktop). Also arg $2.
#   MOONLIGHT_PLATFORM      moonlight -platform value. Default sdl.
#                           sdl       = software decode (always available)
#                           ffmpeg_drm = PR #932 KMS atomic (requires DRM master
#                                        outside gamescope)
#                           v4l2m2m   = SM8550 zero-copy (requires patch 0002)
#   MOONLIGHT_BIN           Path to moonlight binary. Default: PATH lookup.
#   MOONLIGHT_GAMESCOPE_BIN Path to gamescope binary. Default: PATH lookup.
#                           Set to `command -v true` for dry-runs that exercise
#                           the harness shape without a real display.
#   MOONLIGHT_KEYDIR        Pair-state directory. Default
#                           /storage/.cache/moonlight. Created (700) if missing
#                           so first-run on a fresh closure does not hard-fail
#                           before reaching the streaming launcher.
#   MOONLIGHT_RUNS_DIR      Evidence root. Default /storage/.guest/runs.
#   MOONLIGHT_DURATION_S    Smoke duration in seconds. Default 30 (per plan
#                           U4 G5a target). 0 disables the timer (operator
#                           ends the stream manually).
#   MOONLIGHT_AUDIO_GATE    Enforce the PipeWire audio precondition (refuse to
#                           start if `wpctl status` reports only auto_null /
#                           cannot connect). Default 1. Set to 0 for
#                           video-only smoke runs where audio is parked.
#   MOONLIGHT_CAPTURE       If 1 and `grim` is available, capture a screenshot
#                           ~5s after launch. Default 0.
#   GS_OUT_W GS_OUT_H GS_NESTED_W GS_NESTED_H GS_REFRESH GS_FILTER GS_SHARPNESS
#                           gamescope geometry passed through to the streaming
#                           launcher.
#
# Exit codes:
#
#   0   smoke finished, evidence written
#   64  missing host argument (sysexits EX_USAGE)
#   78  audio gate refused start (sysexits EX_PROTOCOL)
#  127  moonlight or gamescope binary not resolvable
set -eu

# Positional shim so this script is drop-in compatible with the streaming
# launcher's argv shape: `remote-moonlight-runner.sh <host> <app>`.
if [ "${1:-}" != "" ] && [ -z "${MOONLIGHT_HOST:-}" ]; then
  MOONLIGHT_HOST="$1"
fi
if [ "${2:-}" != "" ] && [ -z "${MOONLIGHT_APP:-}" ]; then
  MOONLIGHT_APP="$2"
fi

MOONLIGHT_HOST="${MOONLIGHT_HOST:-}"
MOONLIGHT_APP="${MOONLIGHT_APP:-Desktop}"
MOONLIGHT_PLATFORM="${MOONLIGHT_PLATFORM:-sdl}"
MOONLIGHT_BIN="${MOONLIGHT_BIN:-$(command -v moonlight 2>/dev/null || true)}"
MOONLIGHT_GAMESCOPE_BIN="${MOONLIGHT_GAMESCOPE_BIN:-$(command -v gamescope 2>/dev/null || true)}"
MOONLIGHT_KEYDIR="${MOONLIGHT_KEYDIR:-/storage/.cache/moonlight}"
MOONLIGHT_RUNS_DIR="${MOONLIGHT_RUNS_DIR:-/storage/.guest/runs}"
MOONLIGHT_DURATION_S="${MOONLIGHT_DURATION_S:-30}"
MOONLIGHT_AUDIO_GATE="${MOONLIGHT_AUDIO_GATE:-1}"
MOONLIGHT_CAPTURE="${MOONLIGHT_CAPTURE:-0}"
# MOONLIGHT_AUDIO_DRIVER defaults to unset (SDL picks its normal driver).
# The earlier auto-park to "dummy" when MOONLIGHT_AUDIO_GATE=0 existed
# because the substrate /run/user/0 PipeWire sockets were being wiped at
# boot; that race is fixed in plan
# docs/plans/2026-05-24-001-fix-main-space-pipewire-runtime-dir-plan.md
# (see acceptance doc dated 2026-05-24), so the auto-park is no longer
# warranted. Operators who still want video-only with no audio init must
# now set MOONLIGHT_AUDIO_DRIVER=dummy themselves explicitly.
MOONLIGHT_AUDIO_DRIVER="${MOONLIGHT_AUDIO_DRIVER:-}"

if [ -z "$MOONLIGHT_HOST" ]; then
  cat >&2 <<EOF
usage: $(basename "$0") <host> [app]
       MOONLIGHT_HOST=<host> MOONLIGHT_APP=<app> $(basename "$0")

  host  Sunshine host name, IP, or UUID (e.g. aka, 192.168.1.117).
  app   Sunshine application name (default: Desktop).

See top of script for the full env knob list.
EOF
  exit 64
fi

# Audio gate runs before binary resolution: it's an environmental
# precondition (exit 78, EX_PROTOCOL) and surfacing it first is more
# actionable than a downstream "binary missing" (exit 127) when both are
# wrong simultaneously.
#
# Audio gate. PipeWire-via-systemd-nspawn on ROCKNIX has surfaced the
# `auto_null` failure mode at least once (see
# docs/solutions/runtime-errors/guest-pipewire-dummy-sink-missing-udev-sound-records-rocknix-2026-05-13.md).
# Enforce by default so smoke runs never produce silent-stream evidence.
if [ "$MOONLIGHT_AUDIO_GATE" = "1" ]; then
  if ! command -v wpctl >/dev/null 2>&1; then
    cat >&2 <<EOF
remote-moonlight-runner: MOONLIGHT_AUDIO_GATE=1 but \`wpctl\` is not on PATH.

  install wireplumber into the guest profile, or set MOONLIGHT_AUDIO_GATE=0
  to run a video-only smoke (G5a in plan 003 U4 -- audio is asserted at
  G5b, not G5a, so this is a legitimate posture for early iteration).
EOF
    exit 78
  fi

  wpctl_out=$(wpctl status 2>&1 || true)
  printf '%s\n' "$wpctl_out" | head -1 > /dev/null
  if printf '%s' "$wpctl_out" | grep -qiE 'could not connect|host is down'; then
    cat >&2 <<EOF
remote-moonlight-runner: PipeWire unreachable (wpctl could not connect).

  Restart rocknix-pipewire.service or re-stage udev sound records per
  docs/solutions/runtime-errors/guest-pipewire-dummy-sink-missing-udev-sound-records-rocknix-2026-05-13.md
  before re-running. Or set MOONLIGHT_AUDIO_GATE=0 for a video-only smoke.

wpctl output:
$wpctl_out
EOF
    exit 78
  fi
  # `auto_null` / "Dummy Output" is the no-real-sink failure mode. Refuse
  # rather than produce evidence that ignores the audio path.
  if ! printf '%s' "$wpctl_out" | grep -qE 'Sinks:' \
     || printf '%s' "$wpctl_out" | grep -E 'Sinks:' -A 20 | grep -qiE 'dummy output|auto_null'; then
    sinks_only=$(printf '%s' "$wpctl_out" | grep -E 'Sinks:' -A 20 | head -10 || true)
    cat >&2 <<EOF
remote-moonlight-runner: only auto_null / Dummy Output present.

  The smoke would produce evidence with no real audio routing. Fix per
  docs/solutions/runtime-errors/guest-pipewire-dummy-sink-missing-udev-sound-records-rocknix-2026-05-13.md
  (typically: re-run rocknix-guest-udev-stage and restart the guest), or
  set MOONLIGHT_AUDIO_GATE=0 for a video-only smoke posture.

sinks section:
$sinks_only
EOF
    exit 78
  fi
fi

if [ -z "$MOONLIGHT_BIN" ] || [ ! -x "$MOONLIGHT_BIN" ]; then
  printf 'remote-moonlight-runner: moonlight binary not resolvable\n' >&2
  printf '  set MOONLIGHT_BIN to an absolute store path or install the package\n' >&2
  exit 127
fi

if [ -z "$MOONLIGHT_GAMESCOPE_BIN" ] || [ ! -x "$MOONLIGHT_GAMESCOPE_BIN" ]; then
  printf 'remote-moonlight-runner: gamescope binary not resolvable\n' >&2
  printf '  install gamescope into the guest profile, or set MOONLIGHT_GAMESCOPE_BIN\n' >&2
  exit 127
fi

# Ensure keydir exists. The guest module's tmpfiles rule normally owns this,
# but for out-of-band deploys (plan U6 lane) the operator may not have the
# module enabled yet.
if [ ! -d "$MOONLIGHT_KEYDIR" ]; then
  mkdir -p "$MOONLIGHT_KEYDIR"
  chmod 700 "$MOONLIGHT_KEYDIR" || true
fi

# Evidence dir layout matches the cemu harness convention:
# ${runs}/<YYYYmmdd-HHMMSS>-<variant>-<profile-or-app>/.
APP_SLUG=$(printf '%s' "$MOONLIGHT_APP" | tr -c 'A-Za-z0-9._-' '-' | tr -s '-' | sed 's/^-//;s/-$//')
[ -n "$APP_SLUG" ] || APP_SLUG=app
TS="$(date '+%Y%m%d-%H%M%S')"
RUN_DIR="${MOONLIGHT_RUNS_DIR}/${TS}-${MOONLIGHT_PLATFORM}-${APP_SLUG}"
mkdir -p "$RUN_DIR"

# env.txt: filtered to MOONLIGHT_* / GS_* / SDL_* / WAYLAND_* / XDG_* so
# reviewers can re-run with the same inputs.
{
  printf '# run env (filtered)\n'
  printf 'MOONLIGHT_HOST=%s\n' "$MOONLIGHT_HOST"
  printf 'MOONLIGHT_APP=%s\n' "$MOONLIGHT_APP"
  printf 'MOONLIGHT_PLATFORM=%s\n' "$MOONLIGHT_PLATFORM"
  printf 'MOONLIGHT_BIN=%s\n' "$MOONLIGHT_BIN"
  printf 'MOONLIGHT_GAMESCOPE_BIN=%s\n' "$MOONLIGHT_GAMESCOPE_BIN"
  printf 'MOONLIGHT_KEYDIR=%s\n' "$MOONLIGHT_KEYDIR"
  printf 'MOONLIGHT_DURATION_S=%s\n' "$MOONLIGHT_DURATION_S"
  printf 'MOONLIGHT_AUDIO_GATE=%s\n' "$MOONLIGHT_AUDIO_GATE"
  printf 'MOONLIGHT_AUDIO_DRIVER=%s\n' "$MOONLIGHT_AUDIO_DRIVER"
  printf 'MOONLIGHT_CAPTURE=%s\n' "$MOONLIGHT_CAPTURE"
  printf 'TS=%s\n' "$TS"
  printf 'RUN_DIR=%s\n' "$RUN_DIR"
  env | grep -E '^(GS_|SDL_|WAYLAND_|XDG_|PATH)=' | sort
} > "$RUN_DIR/env.txt"

# host state: a small subset of what the cemu runner captures, just enough
# to correlate frame drops / EGL errors with power / thermals / governors
# at iteration time.
{
  printf '=== uptime ===\n'
  uptime 2>/dev/null || true
  printf '\n=== governors ===\n'
  for p in /sys/devices/system/cpu/cpufreq/policy*; do
    [ -d "$p" ] || continue
    printf '%s gov=%s cur=%s min=%s max=%s hw_max=%s\n' \
      "$(basename "$p")" \
      "$(cat "$p/scaling_governor" 2>/dev/null || echo ?)" \
      "$(cat "$p/scaling_cur_freq" 2>/dev/null || echo ?)" \
      "$(cat "$p/scaling_min_freq" 2>/dev/null || echo ?)" \
      "$(cat "$p/scaling_max_freq" 2>/dev/null || echo ?)" \
      "$(cat "$p/cpuinfo_max_freq" 2>/dev/null || echo ?)"
  done
  printf '\n=== thermals ===\n'
  for tz in /sys/class/thermal/thermal_zone*; do
    [ -d "$tz" ] || continue
    t="$(cat "$tz/type" 2>/dev/null || true)"
    v="$(cat "$tz/temp" 2>/dev/null || true)"
    [ -n "$t" ] && [ -n "$v" ] && printf '%s %sC\n' "$t" "$((v/1000))"
  done | sort 2>/dev/null
  printf '\n=== /dev/video* ===\n'
  ls -la /dev/video* 2>&1 | head -10
} > "$RUN_DIR/host-state.txt" 2>&1

hz="$(getconf CLK_TCK 2>/dev/null || echo 100)"
pagesize="$(getconf PAGESIZE 2>/dev/null || echo 4096)"

cpu_total() { awk '/^cpu /{s=0; for(i=2;i<=NF;i++) s+=$i; print s}' /proc/stat; }
cpu_idle() { awk '/^cpu /{print $5+$6}' /proc/stat; }
proc_ticks() { awk '{print $14+$15}' "/proc/$1/stat" 2>/dev/null || echo 0; }
proc_rss_kib() { awk -v ps="$pagesize" '{printf "%.0f", $2*ps/1024}' "/proc/$1/statm" 2>/dev/null || echo 0; }
thread_count() { ls "/proc/$1/task" 2>/dev/null | wc -l; }
max_temp_mC() { for t in /sys/class/thermal/thermal_zone*/temp; do [ -r "$t" ] && cat "$t"; done 2>/dev/null | sort -nr | head -1; }

summarize_samples() {
  file="$1"
  awk -F, -v hz="$hz" '
    NR==2 {s=$1; pt=$2; rss=$3; ct=$5; ci=$6; temp=$7; min=$3; max=$3; n=1; next}
    NR>2 {e=$1; pt2=$2; rss2=$3; if($3<min)min=$3; if($3>max)max=$3; ct2=$5; ci2=$6; temp=$7; n++}
    END {
      if (n == 0) { print "samples=0"; exit }
      if (n == 1) { e=s+1; pt2=pt; rss2=rss; ct2=ct+1; ci2=ci; }
      dt=e-s; if (dt<=0) dt=1;
      cpu=ct2-ct; if (cpu<=0) cpu=1;
      busy=(ct2-ct)-(ci2-ci);
      printf "proc_cpu_pct=%.1f system_busy_pct=%.1f rss_mib=%.1f rss_range_mib=%.1f-%.1f max_temp_C=%.1f samples=%d", ((pt2-pt)/hz)/dt*100, busy/cpu*100, rss2/1024, min/1024, max/1024, temp/1000, n
    }' "$file"
}

sample_moonlight_process() {
  rundir="$1"
  launcher_pid="$2"

  if ! [ "$MOONLIGHT_DURATION_S" -gt 0 ] 2>/dev/null; then
    printf 'sampling skipped: MOONLIGHT_DURATION_S=%s\n' "$MOONLIGHT_DURATION_S" > "$rundir/telemetry-summary.txt"
    return 0
  fi

  pid=""
  for _ in $(seq 1 30); do
    pid="$(pgrep -n -x moonlight 2>/dev/null || true)"
    [ -n "$pid" ] && break
    kill -0 "$launcher_pid" 2>/dev/null || break
    sleep 1
  done

  if [ -z "$pid" ]; then
    printf 'moonlight process not observed\n' > "$rundir/telemetry-summary.txt"
    return 0
  fi

  {
    printf 'pid=%s\n' "$pid"
    printf 'duration_s=%s\n' "$MOONLIGHT_DURATION_S"
    printf 'hz=%s\n' "$hz"
    printf 'pagesize=%s\n' "$pagesize"
    printf 'rundir=%s\n' "$rundir"
  } > "$rundir/telemetry-meta.txt"

  echo "sec,proc_ticks,rss_kib,threads,cpu_total,cpu_idle,max_temp_mC" > "$rundir/telemetry-samples.csv"
  start="$(date +%s)"
  while kill -0 "$launcher_pid" 2>/dev/null && [ -d "/proc/$pid" ]; do
    sec=$(( $(date +%s) - start ))
    [ "$sec" -gt "$((MOONLIGHT_DURATION_S + 5))" ] && break
    echo "$sec,$(proc_ticks "$pid"),$(proc_rss_kib "$pid"),$(thread_count "$pid"),$(cpu_total),$(cpu_idle),$(max_temp_mC || echo 0)" >> "$rundir/telemetry-samples.csv"
    sleep 1
  done

  summarize_samples "$rundir/telemetry-samples.csv" > "$rundir/telemetry-summary.txt"
}

extract_launch_signals() {
  log="$1"
  out="$2"
  for pat in \
    'Network dropped' \
    'Waiting for IDR' \
    'Unrecoverable' \
    'Received first' \
    'Frames dropped' \
    'packet loss' \
    'RTT' \
    'latency' \
    'presentation(' \
    'EGL_BAD' \
    'glEGLImageTargetTexture' \
    'glDrawArrays error'; do
    printf '%s=%s\n' "$pat" "$(grep -ci "$pat" "$log" 2>/dev/null || true)"
  done > "$out"
}

# Locate the streaming launcher. Prefer the operator-deployed copy at
# /storage/.guest/ (the convention plan 001 U9 wires); fall back to the
# in-tree copy two levels up from this script.
STREAM_LAUNCHER=""
for candidate in \
    "/storage/.guest/start_moonlight_embedded_gamescope.sh" \
    "$(dirname -- "$0")/start_moonlight_embedded_gamescope.sh"; do
  if [ -x "$candidate" ]; then
    STREAM_LAUNCHER="$candidate"
    break
  fi
done

LAUNCH_LOG="$RUN_DIR/launch.log"

if [ -n "$STREAM_LAUNCHER" ]; then
  printf '[%s] dispatching %s host=%s app=%s platform=%s\n' \
    "$(date -Iseconds)" "$STREAM_LAUNCHER" "$MOONLIGHT_HOST" "$MOONLIGHT_APP" "$MOONLIGHT_PLATFORM" \
    > "$LAUNCH_LOG"
  set +e
  if [ "$MOONLIGHT_DURATION_S" -gt 0 ] 2>/dev/null && command -v timeout >/dev/null 2>&1; then
    env MOONLIGHT_BIN="$MOONLIGHT_BIN" \
        MOONLIGHT_KEYDIR="$MOONLIGHT_KEYDIR" \
        MOONLIGHT_PLATFORM="$MOONLIGHT_PLATFORM" \
        MOONLIGHT_AUDIO_DRIVER="$MOONLIGHT_AUDIO_DRIVER" \
        MOONLIGHT_LOG_OUT="$LAUNCH_LOG" \
        timeout --preserve-status "$MOONLIGHT_DURATION_S" \
        "$STREAM_LAUNCHER" "$MOONLIGHT_HOST" "$MOONLIGHT_APP" >>"$LAUNCH_LOG" 2>&1 &
  else
    env MOONLIGHT_BIN="$MOONLIGHT_BIN" \
        MOONLIGHT_KEYDIR="$MOONLIGHT_KEYDIR" \
        MOONLIGHT_PLATFORM="$MOONLIGHT_PLATFORM" \
        MOONLIGHT_AUDIO_DRIVER="$MOONLIGHT_AUDIO_DRIVER" \
        MOONLIGHT_LOG_OUT="$LAUNCH_LOG" \
        "$STREAM_LAUNCHER" "$MOONLIGHT_HOST" "$MOONLIGHT_APP" >>"$LAUNCH_LOG" 2>&1 &
  fi
  LAUNCH_PID=$!
  sample_moonlight_process "$RUN_DIR" "$LAUNCH_PID" &
  SAMPLER_PID=$!
  wait "$LAUNCH_PID"
  RC=$?
  wait "$SAMPLER_PID" 2>/dev/null || true
  set -e
else
  # Fallback: invoke gamescope + moonlight inline. Useful for early dry-runs
  # before the streaming launcher is deployed to /storage/.guest/, and for
  # the test harness on dev machines.
  printf '[%s] dispatching inline (no streaming launcher found) host=%s app=%s platform=%s\n' \
    "$(date -Iseconds)" "$MOONLIGHT_HOST" "$MOONLIGHT_APP" "$MOONLIGHT_PLATFORM" \
    > "$LAUNCH_LOG"
  # Mirror the streaming launcher's audio-driver handling so inline runs
  # have the same posture as launcher-dispatched runs.
  if [ -n "$MOONLIGHT_AUDIO_DRIVER" ]; then
    export SDL_AUDIODRIVER="$MOONLIGHT_AUDIO_DRIVER"
  fi
  set +e
  # CLI shape: `moonlight [action] (options) [host]`. The app is an
  # option (`-app`), not a positional -- see
  # start_moonlight_embedded_gamescope.sh for the same correction.
  "$MOONLIGHT_GAMESCOPE_BIN" -- "$MOONLIGHT_BIN" \
    stream \
    -platform "$MOONLIGHT_PLATFORM" \
    -keydir "$MOONLIGHT_KEYDIR" \
    -app "$MOONLIGHT_APP" \
    "$MOONLIGHT_HOST" \
    >>"$LAUNCH_LOG" 2>&1 &
  LAUNCH_PID=$!
  sample_moonlight_process "$RUN_DIR" "$LAUNCH_PID" &
  SAMPLER_PID=$!
  wait "$LAUNCH_PID"
  RC=$?
  wait "$SAMPLER_PID" 2>/dev/null || true
  set -e
fi

# Optional screenshot capture. Best-effort; missing grim is not fatal.
if [ "$MOONLIGHT_CAPTURE" = "1" ] && command -v grim >/dev/null 2>&1; then
  XDG_RUNTIME_DIR=/run/user/0 grim "$RUN_DIR/screenshot.png" 2>>"$LAUNCH_LOG" || true
fi

extract_launch_signals "$LAUNCH_LOG" "$RUN_DIR/signals.txt"

printf '[%s] launcher exit=%s evidence=%s\n' \
  "$(date -Iseconds)" "$RC" "$RUN_DIR" >> "$LAUNCH_LOG"

printf '%s\n' "$RUN_DIR"
exit "$RC"
