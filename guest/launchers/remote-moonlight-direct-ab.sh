#!/usr/bin/env bash
# remote-moonlight-direct-ab.sh
#
# Benchmark env-gated moonlight-embedded direct V4L2 renderer variants on
# Sobo and write repeatable evidence under /storage/.guest/runs/.
#
# Usage:
#   MOONLIGHT_BIN=/nix/store/.../bin/moonlight \
#   MOONLIGHT_HOST=192.168.1.117 \
#   MOONLIGHT_APP='Desktop (Sway)' \
#   MOONLIGHT_DURATION_S=30 \
#   remote-moonlight-direct-ab.sh direct_sdl direct_dmabuf
#
# Variants:
#   direct_sdl     MOONLIGHT_V4L2M2M_DIRECT=1, SDL NV12 presentation
#   direct_dmabuf  MOONLIGHT_V4L2M2M_DIRECT=1, MOONLIGHT_V4L2M2M_DMABUF=1
#
# Additional variants can be passed as names; their env can be provided by
# MOONLIGHT_VARIANT_<name>_ENV, e.g.
#   MOONLIGHT_VARIANT_cached_ENV='MOONLIGHT_V4L2M2M_DIRECT=1 MOONLIGHT_V4L2M2M_DMABUF=1 MOONLIGHT_V4L2M2M_CACHE=1'
set -eu

MOONLIGHT_RUNS_DIR="${MOONLIGHT_RUNS_DIR:-/storage/.guest/runs}"
MOONLIGHT_HOST="${MOONLIGHT_HOST:-192.168.1.117}"
MOONLIGHT_APP="${MOONLIGHT_APP:-Desktop (Sway)}"
MOONLIGHT_PLATFORM="${MOONLIGHT_PLATFORM:-v4l2m2m}"
MOONLIGHT_BIN="${MOONLIGHT_BIN:-$(command -v moonlight 2>/dev/null || true)}"
MOONLIGHT_KEYDIR="${MOONLIGHT_KEYDIR:-/storage/.cache/moonlight}"
MOONLIGHT_DURATION_S="${MOONLIGHT_DURATION_S:-30}"
MOONLIGHT_REPS="${MOONLIGHT_REPS:-1}"
MOONLIGHT_COOLDOWN_S="${MOONLIGHT_COOLDOWN_S:-4}"
MOONLIGHT_MAPPING="${MOONLIGHT_MAPPING:-}"
MOONLIGHT_AUDIO_DRIVER="${MOONLIGHT_AUDIO_DRIVER:-dummy}"
MOONLIGHT_CAPTURE="${MOONLIGHT_CAPTURE:-1}"

if [ -z "$MOONLIGHT_BIN" ] || [ ! -x "$MOONLIGHT_BIN" ]; then
  echo "remote-moonlight-direct-ab: MOONLIGHT_BIN missing or not executable" >&2
  exit 127
fi
if [ -z "$MOONLIGHT_MAPPING" ]; then
  candidate="$(dirname "$(dirname "$MOONLIGHT_BIN")")/share/moonlight/gamecontrollerdb.txt"
  [ -f "$candidate" ] && MOONLIGHT_MAPPING="$candidate"
fi

variants="$*"
[ -n "$variants" ] || variants="direct_sdl direct_dmabuf"

TS="$(date '+%Y%m%d-%H%M%S')"
ROOT="${MOONLIGHT_RUNS_DIR}/${TS}-moonlight-direct-ab"
mkdir -p "$ROOT/runs"
echo "$ROOT" > /tmp/moonlight-direct-ab-root

hz="$(getconf CLK_TCK 2>/dev/null || echo 100)"
pagesize="$(getconf PAGESIZE 2>/dev/null || echo 4096)"

variant_env() {
  name="$1"
  var="MOONLIGHT_VARIANT_${name}_ENV"
  eval custom=\${$var:-}
  if [ -n "${custom:-}" ]; then
    printf '%s\n' "$custom"
    return 0
  fi
  case "$name" in
    direct_sdl)
      printf '%s\n' 'MOONLIGHT_V4L2M2M_DIRECT=1'
      ;;
    direct_dmabuf)
      printf '%s\n' 'MOONLIGHT_V4L2M2M_DIRECT=1 MOONLIGHT_V4L2M2M_DMABUF=1'
      ;;
    *)
      printf '%s\n' 'MOONLIGHT_V4L2M2M_DIRECT=1 MOONLIGHT_V4L2M2M_DMABUF=1'
      ;;
  esac
}

cpu_total() { awk '/^cpu /{s=0; for(i=2;i<=NF;i++) s+=$i; print s}' /proc/stat; }
cpu_idle() { awk '/^cpu /{print $5+$6}' /proc/stat; }
proc_ticks() { awk '{print $14+$15}' "/proc/$1/stat" 2>/dev/null || echo 0; }
proc_rss_kib() { awk -v ps="$pagesize" '{printf "%.0f", $2*ps/1024}' "/proc/$1/statm" 2>/dev/null || echo 0; }
thread_count() { ls "/proc/$1/task" 2>/dev/null | wc -l; }
max_temp_mC() { for t in /sys/class/thermal/thermal_zone*/temp; do [ -r "$t" ] && cat "$t"; done 2>/dev/null | sort -nr | head -1; }

sample_pid() {
  label="$1" pid="$2" rundir="$3"
  {
    printf 'label=%s\n' "$label"
    printf 'pid=%s\n' "$pid"
    printf 'duration_s=%s\n' "$MOONLIGHT_DURATION_S"
    printf 'hz=%s\n' "$hz"
    printf 'pagesize=%s\n' "$pagesize"
    printf 'rundir=%s\n' "$rundir"
  } > "$rundir/meta.txt"
  echo "sec,proc_ticks,rss_kib,threads,cpu_total,cpu_idle,max_temp_mC" > "$rundir/samples.csv"
  start="$(date +%s)"
  while [ $(( $(date +%s) - start )) -lt "$MOONLIGHT_DURATION_S" ]; do
    if [ ! -d "/proc/$pid" ]; then
      echo "PROCESS_EXITED" >> "$rundir/events.log"
      break
    fi
    sec=$(( $(date +%s) - start ))
    echo "$sec,$(proc_ticks "$pid"),$(proc_rss_kib "$pid"),$(thread_count "$pid"),$(cpu_total),$(cpu_idle),$(max_temp_mC || echo 0)" >> "$rundir/samples.csv"
    sleep 1
  done
}

summarize_csv() {
  file="$1"
  awk -F, -v hz="$hz" '
    NR==2 {s=$1; pt=$2; rss=$3; ct=$5; ci=$6; min=$3; max=$3; next}
    NR>2 {e=$1; pt2=$2; rss2=$3; if($3<min)min=$3; if($3>max)max=$3; ct2=$5; ci2=$6; n++}
    END {
      dt=e-s; if (dt<=0) dt=1;
      cpu=ct2-ct; if (cpu<=0) cpu=1;
      busy=(ct2-ct)-(ci2-ci);
      printf "proc_cpu_pct=%.1f system_busy_pct=%.1f rss_mib=%.1f rss_range_mib=%.1f-%.1f samples=%d", ((pt2-pt)/hz)/dt*100, busy/cpu*100, rss2/1024, min/1024, max/1024, n+1
    }' "$file"
}

signal_counts() {
  log="$1"
  for pat in \
    'first cached plane EGL import succeeded' \
    'first plane EGL import succeeded' \
    'first EGL import succeeded' \
    'Network dropped' \
    'Waiting for IDR' \
    'Unrecoverable' \
    'no free OUTPUT' \
    'glEGLImageTargetTexture' \
    'glDrawArrays error' \
    'presentation('; do
    printf '%s=%s\n' "$pat" "$(grep -c "$pat" "$log" 2>/dev/null || true)"
  done
}

run_one() {
  variant="$1" rep="$2" env_line="$3"
  slug="${variant}-rep${rep}"
  rundir="$ROOT/runs/$slug"
  mkdir -p "$rundir"

  pkill -KILL -x moonlight 2>/dev/null || true
  sleep "$MOONLIGHT_COOLDOWN_S"

  {
    printf 'MOONLIGHT_HOST=%s\n' "$MOONLIGHT_HOST"
    printf 'MOONLIGHT_APP=%s\n' "$MOONLIGHT_APP"
    printf 'MOONLIGHT_PLATFORM=%s\n' "$MOONLIGHT_PLATFORM"
    printf 'MOONLIGHT_BIN=%s\n' "$MOONLIGHT_BIN"
    printf 'MOONLIGHT_KEYDIR=%s\n' "$MOONLIGHT_KEYDIR"
    printf 'MOONLIGHT_MAPPING=%s\n' "$MOONLIGHT_MAPPING"
    printf 'MOONLIGHT_AUDIO_DRIVER=%s\n' "$MOONLIGHT_AUDIO_DRIVER"
    printf 'VARIANT=%s\n' "$variant"
    printf 'VARIANT_ENV=%s\n' "$env_line"
    printf 'XDG_RUNTIME_DIR=/run/user/0\n'
    printf 'WAYLAND_DISPLAY=wayland-1\n'
    printf 'SDL_VIDEODRIVER=wayland\n'
    printf 'SDL_AUDIODRIVER=%s\n' "$MOONLIGHT_AUDIO_DRIVER"
  } > "$rundir/env.txt"

  {
    printf '=== uptime ===\n'; uptime || true
    printf '\n=== video devices ===\n'; ls -la /dev/video* 2>&1 | head -20
    printf '\n=== thermals ===\n'; for t in /sys/class/thermal/thermal_zone*/temp; do [ -r "$t" ] && printf '%s %s\n' "$t" "$(cat "$t")"; done | sort
  } > "$rundir/host-state.txt" 2>&1

  env_exports="$(printf '%s\n' "$env_line" | tr ' ' '\n' | awk 'NF { print "export " $0 }')"
  cat > "$rundir/launcher.sh" <<EOF
#!/bin/sh
export XDG_RUNTIME_DIR=/run/user/0
export WAYLAND_DISPLAY=wayland-1
export SDL_VIDEODRIVER=wayland
export SDL_AUDIODRIVER=$MOONLIGHT_AUDIO_DRIVER
$env_exports
exec /nix/store/nja3jimv61blss0mfgjqa68rfiwfxv39-coreutils-9.8/bin/stdbuf -oL -eL \\
  "$MOONLIGHT_BIN" -verbose stream -platform "$MOONLIGHT_PLATFORM" -keydir "$MOONLIGHT_KEYDIR" -mapping "$MOONLIGHT_MAPPING" -app "$MOONLIGHT_APP" "$MOONLIGHT_HOST" > "$rundir/launch.log" 2>&1
EOF
  chmod +x "$rundir/launcher.sh"

  XDG_RUNTIME_DIR=/run/user/0 SWAYSOCK="${SWAYSOCK:-/run/user/0/sway-ipc.0.263.sock}" setsid swaymsg exec "$rundir/launcher.sh" </dev/null >/dev/null 2>&1 || true
  pid=""
  for _ in $(seq 1 25); do
    pid="$(pgrep -n -x moonlight 2>/dev/null || true)"
    [ -n "$pid" ] && break
    sleep 1
  done
  if [ -z "$pid" ]; then
    echo "FAILED_TO_START" > "$rundir/result.txt"
    return 1
  fi

  for _ in $(seq 1 45); do
    grep -q 'presentation(' "$rundir/launch.log" 2>/dev/null && break
    sleep 1
  done

  sample_pid "$variant" "$pid" "$rundir"
  if [ "$MOONLIGHT_CAPTURE" = "1" ] && command -v grim >/dev/null 2>&1; then
    XDG_RUNTIME_DIR=/run/user/0 WAYLAND_DISPLAY=wayland-1 grim "$rundir/screenshot.png" 2>>"$rundir/launch.log" || true
  fi
  signal_counts "$rundir/launch.log" > "$rundir/signals.txt"

  pkill -TERM -x moonlight 2>/dev/null || true
  sleep 2
  pkill -KILL -x moonlight 2>/dev/null || true
  echo "OK" > "$rundir/result.txt"
}

REPORT="$ROOT/evidence.md"
cat > "$REPORT" <<EOF
# moonlight direct V4L2 renderer A/B

- Timestamp: $(date -Iseconds)
- Host: $(uname -n) ($(uname -m))
- Sunshine host: \`$MOONLIGHT_HOST\`
- App: \`$MOONLIGHT_APP\`
- Binary: \`$MOONLIGHT_BIN\`
- Duration per run after first presentation: ${MOONLIGHT_DURATION_S}s
- Repetitions: ${MOONLIGHT_REPS}

| Variant | Rep | Summary | Run dir |
|---|---:|---|---|
EOF

for rep in $(seq 1 "$MOONLIGHT_REPS"); do
  for variant in $variants; do
    env_line="$(variant_env "$variant")"
    run_one "$variant" "$rep" "$env_line" || true
    rundir="$ROOT/runs/${variant}-rep${rep}"
    summary="failed"
    [ -f "$rundir/samples.csv" ] && summary="$(summarize_csv "$rundir/samples.csv")"
    printf '| `%s` | %s | %s | `%s` |\n' "$variant" "$rep" "$summary" "$rundir" >> "$REPORT"
  done
done

cat >> "$REPORT" <<'EOF'

## Signals

EOF
for rundir in "$ROOT"/runs/*; do
  [ -d "$rundir" ] || continue
  {
    printf '### %s\n\n```text\n' "$(basename "$rundir")"
    [ -f "$rundir/signals.txt" ] && cat "$rundir/signals.txt"
    printf '\n--- launch highlights ---\n'
    grep -E 'setup: decoder|presenter=|direct-dmabuf|presentation\(|Received first|Network dropped|Waiting for IDR|Unrecoverable|no free OUTPUT|glEGLImageTargetTexture|glDrawArrays' "$rundir/launch.log" 2>/dev/null | tail -80 || true
    printf '\n```\n\n'
  } >> "$REPORT"
done

printf '%s\n' "$ROOT"
cat "$REPORT"
