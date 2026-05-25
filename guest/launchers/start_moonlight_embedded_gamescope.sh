#!/run/current-system/sw/bin/bash
# Launch moonlight-embedded (CLI Moonlight client) inside Nix gamescope on
# the SM8550 guest. Streams from a paired Sunshine host into a gamescope
# nested compositor so the player sees the same FSR-scaled, fixed-resolution
# surface as the local Cemu / Steam launchers.
#
# ---------------------------------------------------------------------------
# Refactor staging note (2026-05-22)
#
# This launcher is staged at the post-refactor target path defined in
# docs/plans/2026-05-22-001-refactor-monorepo-merge-layered-restructure-plan.md
# (U9). It is NOT yet wired into any kiosk profile or guest/modules/
# entry — staging only. When the refactor lands moonlight-embedded into the
# main-space profile, deploy this script alongside the cemu and steam
# launchers under /storage/.guest/ and reference it from the kiosk app
# manifest.
#
# Pair state assumed (pre-flight) — see "Pairing" below.
# ---------------------------------------------------------------------------
#
# Usage:
#
#   start_moonlight_embedded_gamescope.sh <host> <app>
#
# Examples:
#
#   start_moonlight_embedded_gamescope.sh aka "Desktop"
#   MOONLIGHT_PLATFORM=v4l2m2m start_moonlight_embedded_gamescope.sh aka "BotW"
#
# Environment knobs:
#
#   GS_OUT_W, GS_OUT_H        gamescope output dimensions (default 1920x1080)
#   GS_NESTED_W, GS_NESTED_H  gamescope nested dimensions (default 1920x1080)
#   GS_REFRESH                gamescope refresh rate     (default 60)
#   GS_FILTER                 gamescope filter           (default linear)
#   GS_SHARPNESS              gamescope sharpness        (default 0)
#   GS_BACKEND                gamescope backend          (default wayland)
#                             Set to empty to let gamescope auto-select.
#   GS_EXTRA                  extra gamescope flags      (default empty)
#   MOONLIGHT_BIN             absolute path to the moonlight binary
#                             (default: resolved from PATH via command -v)
#                             used by out-of-band deploys (nix copy + ad-hoc
#                             store path) so the launcher works before the
#                             refactor wires the package into the profile.
#   MOONLIGHT_KEYDIR          pair-state directory       (default /storage/.cache/moonlight)
#   MOONLIGHT_PLATFORM        moonlight -platform value  (default sdl)
#                             sdl       = software decode (always available)
#                             ffmpeg_drm = vendored PR #932 path (requires KMS master — not under gamescope)
#                             v4l2m2m   = SM8550 hardware decode (requires patch 0002)
#   MOONLIGHT_MAPPING         SDL controller mapping file
#                             (default: share/moonlight/gamecontrollerdb.txt next to MOONLIGHT_BIN)
#   MOONLIGHT_BITRATE_KBPS    stream bitrate cap         (default 20000)
#   MOONLIGHT_FPS             stream fps target          (default 60)
#   MOONLIGHT_WIDTH           stream width               (default 1920)
#   MOONLIGHT_HEIGHT          stream height              (default 1080)
#   MOONLIGHT_LOG_OUT         combined launcher/gamescope/moonlight log path
#                             (default /storage/.guest/runs/moonlight-embedded-stdout.log)
#   MOONLIGHT_AUDIO_DRIVER    SDL2 audio driver name     (default unset -- SDL picks)
#                             Historically callers set this to "dummy" to
#                             work around the /run/user/0 PipeWire socket
#                             wipe race that made SDL_OpenAudio fail at
#                             stream start. That race was fixed in plan
#                             docs/plans/2026-05-24-001-fix-main-space-pipewire-runtime-dir-plan.md
#                             (see acceptance doc dated 2026-05-24), so
#                             the workaround should no longer be needed.
#                             The env var is retained for video-only
#                             smoke postures (and for future bring-up of
#                             new devices where the substrate is not yet
#                             ready).
#
# Pairing:
#
#   moonlight-embedded reads its keydir to find a pair cert for <host>. If
#   the host is not paired, the stream fails with "Failed to connect to host".
#   Pair from a regular SSH shell on the guest (NOT inside the kiosk Sway
#   session) before invoking this launcher:
#
#     ${MOONLIGHT_KEYDIR:-/storage/.cache/moonlight}
#       moonlight -keydir <keydir> pair <host>
#
#   This is intentionally separate from guest/launchers/pair-moonlight.sh,
#   which pairs the Moonlight-Qt GUI client (different binary, different
#   keystore at ~/.config/Moonlight\ Game\ Streaming\ Project/).

set -eu

HOST="${1:-}"
APP="${2:-}"
if [ -z "$HOST" ] || [ -z "$APP" ]; then
  echo "usage: $(basename "$0") <host> <app>" >&2
  echo "" >&2
  echo "  host  Sunshine host name, IP, or UUID (e.g. aka, 192.168.1.117)" >&2
  echo "  app   Sunshine application name (e.g. Desktop)" >&2
  exit 64
fi

export PATH=/run/current-system/sw/bin:/bin:/usr/bin:/nix/var/nix/profiles/per-user/root/profile/bin:/root/.nix-profile/bin:$PATH
export SDL_VIDEO_ALLOW_SCREENSAVER=1
export SDL_HINT_VIDEO_ALLOW_SCREENSAVER=1
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/0}"
export HOME=/storage
export XDG_CONFIG_HOME=/storage/.config
export XDG_DATA_HOME=/storage/.local/share
export XDG_CACHE_HOME=/storage/.cache

GS_OUT_W="${GS_OUT_W:-1920}"
GS_OUT_H="${GS_OUT_H:-1080}"
GS_NESTED_W="${GS_NESTED_W:-1920}"
GS_NESTED_H="${GS_NESTED_H:-1080}"
GS_REFRESH="${GS_REFRESH:-60}"
GS_FILTER="${GS_FILTER:-linear}"
GS_SHARPNESS="${GS_SHARPNESS:-0}"
GS_EXTRA="${GS_EXTRA:-}"
GS_BACKEND="${GS_BACKEND:-wayland}"

MOONLIGHT_KEYDIR="${MOONLIGHT_KEYDIR:-/storage/.cache/moonlight}"
MOONLIGHT_PLATFORM="${MOONLIGHT_PLATFORM:-sdl}"

# SDL audio driver override. Optional. When set (typically to "dummy")
# the launcher exports SDL_AUDIODRIVER so moonlight does not tear down
# the whole stream on SDL_OpenAudio failure. Only export if explicitly
# set so SDL retains its normal autodetection path in the happy case.
# The substrate's /run/user/0 socket wipe race that historically required
# the "dummy" workaround is fixed (plan 2026-05-24-001); the override is
# now reserved for video-only smoke postures rather than a routine
# workaround.
if [ -n "${MOONLIGHT_AUDIO_DRIVER:-}" ]; then
  export SDL_AUDIODRIVER="$MOONLIGHT_AUDIO_DRIVER"
fi
MOONLIGHT_BITRATE_KBPS="${MOONLIGHT_BITRATE_KBPS:-20000}"
MOONLIGHT_FPS="${MOONLIGHT_FPS:-60}"
MOONLIGHT_WIDTH="${MOONLIGHT_WIDTH:-1920}"
MOONLIGHT_HEIGHT="${MOONLIGHT_HEIGHT:-1080}"
MOONLIGHT_MAPPING="${MOONLIGHT_MAPPING:-}"

# Resolve the moonlight binary. MOONLIGHT_BIN lets out-of-band deploys
# (nix copy + ad-hoc store path) point at a specific binary before the
# refactor wires the package into the guest profile. Falls back to PATH
# resolution once the profile-installed binary is available.
MOONLIGHT_BIN="${MOONLIGHT_BIN:-$(command -v moonlight 2>/dev/null || true)}"

if ! command -v gamescope >/dev/null 2>&1; then
  echo "gamescope is not installed in the guest profile" >&2
  echo "expected to be wired by the main-space profile" >&2
  exit 127
fi
if [ -z "$MOONLIGHT_BIN" ] || [ ! -x "$MOONLIGHT_BIN" ]; then
  echo "moonlight binary not found" >&2
  echo "set MOONLIGHT_BIN=/nix/store/...-moonlight-embedded-*/bin/moonlight" >&2
  echo "  (out-of-band deploy via nix copy)" >&2
  echo "or install via rocknix.sm8550.moonlight.enable = true; (post-refactor)" >&2
  exit 127
fi
if [ -z "$MOONLIGHT_MAPPING" ]; then
  candidate="$(dirname "$(dirname "$MOONLIGHT_BIN")")/share/moonlight/gamecontrollerdb.txt"
  [ -f "$candidate" ] && MOONLIGHT_MAPPING="$candidate"
fi

# Surface a clear error if the keydir is missing rather than letting
# moonlight-embedded write to a transient location and then fail to find
# pair state on the next run.
if [ ! -d "$MOONLIGHT_KEYDIR" ]; then
  echo "moonlight keydir missing: $MOONLIGHT_KEYDIR" >&2
  echo "expected to be created by guest/modules/moonlight.nix systemd.tmpfiles rule" >&2
  exit 1
fi

LOG_OUT="${MOONLIGHT_LOG_OUT:-/storage/.guest/runs/moonlight-embedded-stdout.log}"
mkdir -p "$(dirname "$LOG_OUT")"
echo "[$(date)] launching gamescope backend=${GS_BACKEND:-auto} ${GS_NESTED_W}x${GS_NESTED_H}->${GS_OUT_W}x${GS_OUT_H} ${GS_FILTER} moonlight=$MOONLIGHT_BIN host=$HOST app=$APP platform=$MOONLIGHT_PLATFORM mapping=${MOONLIGHT_MAPPING:-none}" | tee -a "$LOG_OUT" >&2
exec >>"$LOG_OUT" 2>&1

GAMESCOPE_BACKEND_ARGS=()
if [ -n "$GS_BACKEND" ]; then
  GAMESCOPE_BACKEND_ARGS=(--backend "$GS_BACKEND")
fi
MOONLIGHT_MAPPING_ARGS=()
if [ -n "$MOONLIGHT_MAPPING" ]; then
  MOONLIGHT_MAPPING_ARGS=(-mapping "$MOONLIGHT_MAPPING")
fi

# moonlight-embedded CLI shape: `moonlight [action] (options) [host]`.
# The app is an option (`-app <name>`), not a positional. Passing it as a
# trailing positional yields a confusing "Too many options: No such file
# or directory" abort even though pair / list work. Confirmed on Sobo
# 2026-05-22 during plan 003 U4 G1 -- see migration notes for context.
exec gamescope "${GAMESCOPE_BACKEND_ARGS[@]}" -f --force-windows-fullscreen \
  -W "$GS_OUT_W" -H "$GS_OUT_H" -w "$GS_NESTED_W" -h "$GS_NESTED_H" \
  -r "$GS_REFRESH" -S fit -F "$GS_FILTER" --sharpness "$GS_SHARPNESS" $GS_EXTRA -- \
  "$MOONLIGHT_BIN" \
    stream \
    -platform "$MOONLIGHT_PLATFORM" \
    -keydir "$MOONLIGHT_KEYDIR" \
    "${MOONLIGHT_MAPPING_ARGS[@]}" \
    -bitrate "$MOONLIGHT_BITRATE_KBPS" \
    -fps "$MOONLIGHT_FPS" \
    -width "$MOONLIGHT_WIDTH" \
    -height "$MOONLIGHT_HEIGHT" \
    -app "$APP" \
    "$HOST"
