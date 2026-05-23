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
#                             v4l2m2m   = SM8550 zero-copy HW decode (requires patch 0002, not yet shipped)
#   MOONLIGHT_BITRATE_KBPS    stream bitrate cap         (default 20000)
#   MOONLIGHT_FPS             stream fps target          (default 60)
#   MOONLIGHT_WIDTH           stream width               (default 1920)
#   MOONLIGHT_HEIGHT          stream height              (default 1080)
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

MOONLIGHT_KEYDIR="${MOONLIGHT_KEYDIR:-/storage/.cache/moonlight}"
MOONLIGHT_PLATFORM="${MOONLIGHT_PLATFORM:-sdl}"
MOONLIGHT_BITRATE_KBPS="${MOONLIGHT_BITRATE_KBPS:-20000}"
MOONLIGHT_FPS="${MOONLIGHT_FPS:-60}"
MOONLIGHT_WIDTH="${MOONLIGHT_WIDTH:-1920}"
MOONLIGHT_HEIGHT="${MOONLIGHT_HEIGHT:-1080}"

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

# Surface a clear error if the keydir is missing rather than letting
# moonlight-embedded write to a transient location and then fail to find
# pair state on the next run.
if [ ! -d "$MOONLIGHT_KEYDIR" ]; then
  echo "moonlight keydir missing: $MOONLIGHT_KEYDIR" >&2
  echo "expected to be created by guest/modules/moonlight.nix systemd.tmpfiles rule" >&2
  exit 1
fi

LOG_OUT=/storage/.guest/runs/moonlight-embedded-stdout.log
mkdir -p "$(dirname "$LOG_OUT")"
echo "[$(date)] launching gamescope ${GS_NESTED_W}x${GS_NESTED_H}->${GS_OUT_W}x${GS_OUT_H} ${GS_FILTER} moonlight=$MOONLIGHT_BIN host=$HOST app=$APP platform=$MOONLIGHT_PLATFORM" | tee -a "$LOG_OUT" >&2
exec >>"$LOG_OUT" 2>&1

exec gamescope --backend sdl -f --force-windows-fullscreen \
  -W "$GS_OUT_W" -H "$GS_OUT_H" -w "$GS_NESTED_W" -h "$GS_NESTED_H" \
  -r "$GS_REFRESH" -S fit -F "$GS_FILTER" --sharpness "$GS_SHARPNESS" $GS_EXTRA -- \
  "$MOONLIGHT_BIN" \
    -platform "$MOONLIGHT_PLATFORM" \
    -keydir "$MOONLIGHT_KEYDIR" \
    -bitrate "$MOONLIGHT_BITRATE_KBPS" \
    -fps "$MOONLIGHT_FPS" \
    -width "$MOONLIGHT_WIDTH" \
    -height "$MOONLIGHT_HEIGHT" \
    stream "$HOST" "$APP"
