#!/bin/sh
# Copy internal ROMs that were missing from the SD card to the SD card.
# Run on Bandai as root.
#
# Intentionally excludes the Ziperto .rar archives for DreamWorks Gabby's
# Dollhouse: Ready to Party; copies the extracted/installable .xci/.nsp files.
#
# Defaults optimize for same-device local copies:
# - whole-file transfer (no rsync delta algorithm)
# - no compression
# - no checksum pre-scan
# - per-file and aggregate progress

set -eu

SD_DEVICE=${SD_DEVICE:-/dev/mmcblk0p1}
SD_MOUNT=${SD_MOUNT:-/mnt/games-card}
DRY_RUN=${DRY_RUN:-1}
DELETE_SOURCE=${DELETE_SOURCE:-0}

mounted_here=0
LIST=$(mktemp /tmp/internal-roms-to-sd.XXXXXX)
trap 'rm -f "$LIST"; if [ "$mounted_here" -eq 1 ] && findmnt -rn "$SD_MOUNT" >/dev/null 2>&1; then umount "$SD_MOUNT"; fi' EXIT INT TERM

if ! findmnt -rn "$SD_MOUNT" >/dev/null 2>&1; then
  mkdir -p "$SD_MOUNT"
  mount "$SD_DEVICE" "$SD_MOUNT"
  mounted_here=1
fi

cat >"$LIST" <<'EOF'
gba|/storage/korri/roms/nintendo-gameboy-advance/dkkc3.zip
gba|/storage/korri/roms/nintendo-gameboy-advance/Drill Dozer (U).gba
gba|/storage/korri/roms/nintendo-gameboy-advance/Legend of Zelda, The - A Link To The Past Four Swords (U) [!].gba
gba|/storage/korri/roms/nintendo-gameboy-advance/Legend of Zelda, The - The Minish Cap (U).gba
gba|/storage/korri/roms/nintendo-gameboy-advance/Metroid Fusion (USA, Australia).gba
gba|/storage/korri/roms/nintendo-gameboy-advance/Wario Land 4 (UE) [!].gba
gba|/storage/korri/roms/nintendo-gameboy-advance/wl4.gba
switch|/storage/korri/roms/switch/DreamWorks Gabby’s Dollhouse Ready to Party [0100F69020BD8000] [v0].xci
switch|/storage/korri/roms/switch/DreamWorks Gabby’s Dollhouse Ready to Party [0100F69020BD8800] [v65536].nsp
EOF

missing=0
total_bytes=0
count=0
while IFS='|' read -r system src; do
  [ -n "$system" ] || continue
  if [ ! -f "$src" ]; then
    echo "missing source: $src" >&2
    missing=1
    continue
  fi
  size=$(stat -c '%s' "$src")
  total_bytes=$((total_bytes + size))
  count=$((count + 1))
done <"$LIST"
[ "$missing" -eq 0 ] || exit 1

echo "SD mount: $SD_MOUNT ($(findmnt -rn -o SOURCE,OPTIONS "$SD_MOUNT"))"
echo "Files queued: $count"
printf 'Bytes queued: %s\n' "$total_bytes"
if command -v numfmt >/dev/null 2>&1; then
  printf 'Human size: %s\n' "$(numfmt --to=iec --suffix=B "$total_bytes")"
fi
if [ "$DRY_RUN" = 1 ]; then
  echo "Mode: dry-run"
else
  echo "Mode: copy"
fi
if [ "$DELETE_SOURCE" = 1 ]; then
  echo "DELETE_SOURCE=1 requested; sources will be removed only after successful rsync."
fi
echo

RSYNC_BASE='-a --whole-file --no-compress --inplace --ignore-existing --human-readable --progress --stats --protect-args'
if [ "$DRY_RUN" = 1 ]; then
  RSYNC_BASE="$RSYNC_BASE --dry-run --itemize-changes"
else
  RSYNC_BASE="$RSYNC_BASE --info=progress2,name1,stats2"
fi

idx=0
copied_ok=0
while IFS='|' read -r system src; do
  [ -n "$system" ] || continue
  idx=$((idx + 1))
  dest_dir="$SD_MOUNT/roms/$system"
  mkdir -p "$dest_dir"
  size=$(stat -c '%s' "$src")
  echo "[$idx/$count] $src"
  echo "      -> $dest_dir/"
  if command -v numfmt >/dev/null 2>&1; then
    echo "      size $(numfmt --to=iec --suffix=B "$size")"
  else
    echo "      size $size bytes"
  fi
  # shellcheck disable=SC2086
  rsync $RSYNC_BASE -- "$src" "$dest_dir/"
  copied_ok=$((copied_ok + 1))
  echo
done <"$LIST"

if [ "$DRY_RUN" = 1 ]; then
  echo "Dry run complete. Re-run with DRY_RUN=0 to copy."
else
  echo "Flushing writes with sync..."
  sync
  echo "Copy complete: $copied_ok/$count rsync operations succeeded."
  if [ "$DELETE_SOURCE" = 1 ]; then
    echo "Deleting sources after successful copy..."
    while IFS='|' read -r system src; do
      [ -n "$system" ] || continue
      rm -v -- "$src"
    done <"$LIST"
  fi
fi
