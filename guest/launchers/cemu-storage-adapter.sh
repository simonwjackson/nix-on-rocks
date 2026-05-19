#!/run/current-system/sw/bin/bash
# cemu-storage-adapter.sh -- Layer 14 Cemu user-data compatibility adapter
#
# Owns the temporary ROCKNIX-era /storage Cemu layout for the guest session.
# The Cemu package entry point remains generic; this adapter preserves existing
# settings/saves/keys while the guest transitions toward normal XDG-owned state.
set -eu

: "${XDG_CONFIG_HOME:?missing XDG_CONFIG_HOME; launch from guest session or export it explicitly}"
: "${XDG_DATA_HOME:?missing XDG_DATA_HOME; launch from guest session or export it explicitly}"

CEMU_CONFIG_ROOT="${CEMU_CONFIG_ROOT:-${XDG_CONFIG_HOME}/Cemu}"
CEMU_HOME_CONFIG="${CEMU_HOME_CONFIG:-${CEMU_CONFIG_ROOT}/share}"
CEMU_HOME_LOCAL="${CEMU_HOME_LOCAL:-${XDG_DATA_HOME}/Cemu}"
CEMU_BIOS_ROOT="${CEMU_BIOS_ROOT:-/storage/roms/bios/cemu}"
CEMU_DEFAULT_SETTINGS="${CEMU_DEFAULT_SETTINGS:-}"
CEMU_NORMALIZE_AUDIO_SETTINGS="${CEMU_NORMALIZE_AUDIO_SETTINGS:-1}"

mkdir -p "$CEMU_HOME_CONFIG"

# Seed only fresh guest/user state. Never overwrite an existing settings.xml;
# BOTW validation and user choices mutate this file during normal operation.
if [ ! -f "${CEMU_CONFIG_ROOT}/settings.xml" ] && [ -n "$CEMU_DEFAULT_SETTINGS" ] && [ -f "$CEMU_DEFAULT_SETTINGS" ]; then
  cp "$CEMU_DEFAULT_SETTINGS" "${CEMU_CONFIG_ROOT}/settings.xml"
fi

normalize_audio_settings() {
  settings="${CEMU_CONFIG_ROOT}/settings.xml"
  [ "$CEMU_NORMALIZE_AUDIO_SETTINGS" = "1" ] || return 0
  [ -f "$settings" ] || return 0
  grep -q '<Audio>' "$settings" || return 0

  tmp="${settings}.tmp.$$"
  awk '
    /<Audio>/ { in_audio = 1 }
    in_audio && /^[[:space:]]*<api>.*<\/api>/ {
      sub(/<api>.*<\/api>/, "<api>3</api>")
    }
    in_audio && /^[[:space:]]*<TVDevice>.*<\/TVDevice>/ {
      sub(/<TVDevice>.*<\/TVDevice>/, "<TVDevice></TVDevice>")
    }
    in_audio && /^[[:space:]]*<PadDevice>.*<\/PadDevice>/ {
      sub(/<PadDevice>.*<\/PadDevice>/, "<PadDevice></PadDevice>")
    }
    in_audio && /^[[:space:]]*<InputDevice>.*<\/InputDevice>/ {
      sub(/<InputDevice>.*<\/InputDevice>/, "<InputDevice></InputDevice>")
    }
    { print }
    /<\/Audio>/ { in_audio = 0 }
  ' "$settings" > "$tmp"

  if cmp -s "$settings" "$tmp"; then
    rm -f "$tmp"
    return 0
  fi

  backup="${settings}.bak.audio.$(date '+%Y%m%d-%H%M%S')"
  cp -p "$settings" "$backup"
  mv "$tmp" "$settings"
  echo "cemu_audio_settings_normalized=$settings backup=$backup" >&2
}

normalize_audio_settings

# Cemu expects ~/.local/share/Cemu. Preserve the existing ROCKNIX-compatible
# config root by converting a real data directory once, then linking XDG data
# back to the compatibility root.
if [ -d "$CEMU_HOME_LOCAL" ] && [ ! -L "$CEMU_HOME_LOCAL" ]; then
  cp -rf "$CEMU_HOME_LOCAL"/* "$CEMU_HOME_CONFIG"/ 2>/dev/null || true
  rm -rf "$CEMU_HOME_LOCAL"
fi
[ -L "$CEMU_HOME_LOCAL" ] || { mkdir -p "$(dirname "$CEMU_HOME_LOCAL")"; ln -sfn "$CEMU_HOME_CONFIG" "$CEMU_HOME_LOCAL"; }

# Keep online/mlc01/keys in the existing BIOS tree for compatibility with
# ROCKNIX-era layouts. This is deliberately adapter-owned, not package-owned.
for sub in online mlc01 keys; do
  src="${CEMU_HOME_CONFIG}/${sub}"
  dst="${CEMU_BIOS_ROOT}/${sub}"
  mkdir -p "$dst"
  if [ -d "$src" ] && [ ! -L "$src" ]; then
    mv "$src"/* "$dst"/ 2>/dev/null || true
    rm -rf "$src"
  fi
  [ -L "$src" ] || ln -sfn "$dst" "$src"
done

# The host bind exposes settings.xml at $CEMU_CONFIG_ROOT/settings.xml while
# Cemu reads from its share dir. Link it after seeding and leave existing
# user-managed files untouched.
if [ -f "${CEMU_CONFIG_ROOT}/settings.xml" ] && [ ! -e "${CEMU_HOME_CONFIG}/settings.xml" ]; then
  ln -sf "${CEMU_CONFIG_ROOT}/settings.xml" "${CEMU_HOME_CONFIG}/settings.xml"
fi

{
  echo "cemu_storage_adapter=ok"
  echo "CEMU_CONFIG_ROOT=$CEMU_CONFIG_ROOT"
  echo "CEMU_HOME_CONFIG=$CEMU_HOME_CONFIG"
  echo "CEMU_HOME_LOCAL=$CEMU_HOME_LOCAL"
  echo "CEMU_BIOS_ROOT=$CEMU_BIOS_ROOT"
  echo "CEMU_NORMALIZE_AUDIO_SETTINGS=$CEMU_NORMALIZE_AUDIO_SETTINGS"
} >&2
