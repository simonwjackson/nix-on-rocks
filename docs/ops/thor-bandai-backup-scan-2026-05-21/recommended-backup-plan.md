# Thor/Bandai backup recommendation

Read-only scan target: `ssh -p 2222 root@bandai` on 2026-05-21.

## Storage model

- The only mounted persistent writable filesystem in the guest is `/dev/sda19`, ext4 label `STORAGE`.
- `/`, `/storage`, `/storage/.guest`, and `/nix/store` all come from the same physical partition; `/storage/.guest` is a bind/subdirectory mount, not a second disk.
- `/nix/store` is mounted read-only and is rebuildable; do not back it up unless preserving exact closures is required.
- `/dev/mmcblk0p1` is a present but unmounted 1.7T ext4 card labeled `GAMES`; it was not scanned. Inspect/back it up separately before any destructive work touching removable media.

## P0 backup set

Back these up before risky device work:

1. `/storage/.guest/`
   - Includes 13G Wii U BOTW image, Cemu MLC/save data, Cemu config symlinks/targets, Korri guest ROM/library/media, existing backups, and many ad-hoc live scripts/configs not present in the repo.

2. `/storage/korri/`
   - Includes 6.3G Korri ROM library and GBA save files plus library metadata.

3. `/storage/.config/Ryujinx/`
   - Includes Switch saves under `bis/user/save`, save metadata, emulator config, profiles, keys, mods, sdcard state, firmware/system state.

4. Guest identity/local state outside `/storage`:
   - `/root/.ssh`
   - `/root/.config`
   - `/root/.local/share`
   - `/root/.local/state`
   - `/root/.nix-channels`, `/root/.nix-defexpr`, `/root/.bash_history`
   - `/etc/ssh/ssh_host_*`
   - `/etc/NetworkManager/system-connections/`
   - `/etc/machine-id`
   - `/etc/nixos*`
   - `/etc/inputplumber/`
   - `/etc/sway*`
   - `/etc/rocknix-guest-*`
   - `/var/lib/tailscale/`
   - `/var/lib/iwd/`
   - `/var/lib/NetworkManager/`
   - `/var/lib/bluetooth/`
   - `/var/lib/nixos/`

5. Top-level proof/debug artifacts if you care about preserving validation history:
   - `/guest-import.log`, `/guest-promote.log`, `/promote.log`, `/cemu-sm8550-performance.log`, `/steam.log`, `/grim.err`
   - `/screenshot-DSI2.png`, `/u3-current.png`, `/u3-screen.png`

## P1 backup set

Back up if preserving exact current experience/provenance matters:

- `/storage/.config/Ryujinx.guest-before-host-sync-20260509-222531/`
- `/storage/.pki/`
- `/storage/.config/chromium/Default` and `/storage/.config/chromium/Local State`
- `/storage/apps/ryujinx/`
- `/nix/var/nix/profiles/`, `/nix/var/nix/gcroots/`, `/nix/var/nix/db/` as provenance/manifests only; closures still live in `/nix/store`.
- `/var/log/journal/` if boot/session history is useful.

## Skip by default

- `/nix/store`
- `/proc`, `/sys`, `/dev`, `/run`, `/tmp`
- `/storage/.cache`, `/root/.cache`, `/var/cache`, `/var/tmp`
- Mesa/fontconfig/Nix/Chromium caches
- Ryujinx shader caches under `/storage/.config/Ryujinx/games/*/cache`
- `/cache` Mesa shader cache

## Suggested no-regrets rsync pull

Run from this workstation; adjust `BACKUP` first.

```sh
BACKUP="$HOME/backups/bandai-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"
SSH='ssh -p 2222'
RSYNC='rsync -aHAX --numeric-ids --info=progress2 --protect-args -e'

rsync -aHAX --numeric-ids --info=progress2 --protect-args -e "$SSH" root@bandai:/storage/.guest/ "$BACKUP/storage/.guest/"
rsync -aHAX --numeric-ids --info=progress2 --protect-args -e "$SSH" root@bandai:/storage/korri/ "$BACKUP/storage/korri/"
rsync -aHAX --numeric-ids --info=progress2 --protect-args -e "$SSH" root@bandai:/storage/.config/Ryujinx/ "$BACKUP/storage/.config/Ryujinx/"

mkdir -p "$BACKUP/rootfs"
rsync -aHAX --numeric-ids --relative --info=progress2 --protect-args \
  --exclude='/root/.cache' --exclude='/var/cache' --exclude='/var/tmp' \
  -e "$SSH" \
  root@bandai:/root/.ssh \
  root@bandai:/root/.config \
  root@bandai:/root/.local/share \
  root@bandai:/root/.local/state \
  root@bandai:/root/.nix-channels \
  root@bandai:/root/.nix-defexpr \
  root@bandai:/root/.bash_history \
  root@bandai:/etc/ssh \
  root@bandai:/etc/NetworkManager/system-connections \
  root@bandai:/etc/machine-id \
  root@bandai:/etc/nixos \
  root@bandai:/etc/nixos.before-layer14-validation \
  root@bandai:/etc/inputplumber \
  root@bandai:/etc/sway \
  root@bandai:/etc/sway-minimal.conf \
  root@bandai:/etc/rocknix-guest-revision \
  root@bandai:/etc/rocknix-guest-system-path \
  root@bandai:/var/lib/tailscale \
  root@bandai:/var/lib/iwd \
  root@bandai:/var/lib/NetworkManager \
  root@bandai:/var/lib/bluetooth \
  root@bandai:/var/lib/nixos \
  root@bandai:/guest-import.log \
  root@bandai:/guest-promote.log \
  root@bandai:/promote.log \
  root@bandai:/cemu-sm8550-performance.log \
  root@bandai:/steam.log \
  root@bandai:/grim.err \
  root@bandai:/screenshot-DSI2.png \
  root@bandai:/u3-current.png \
  root@bandai:/u3-screen.png \
  "$BACKUP/rootfs/"
```

Run with `--dry-run` added to each `rsync` first if you want a preview.
