# Thor/Bandai `/storage/.guest` backup reconnaissance

Scan target: `ssh -p 2222 root@bandai`, scope `/storage/.guest` only. Remote commands were read-only (`find`, `du`, `ls`, `stat`, `df`) with `-xdev`/`-x` where applicable; no remote writes, mounts, or deletes.

## Prioritized backup list

### P0 — back up before risky device work

1. `/storage/.guest/roms/wiiu/The Legend of Zelda - Breath of the Wild (USA) (DLC) (v208).wua` — `13,660,330,872` bytes (`13G`)
   - Main Wii U game image used by Cemu. Large and not rebuildable from the repo.

2. `/storage/.guest/roms/bios/cemu` — `6.5M`
   - Contains Cemu's linked MLC tree, including BOTW save data under `mlc01/usr/save/00050000/101c9400` (`6.3M`), account/play-stat state, and empty `keys`/`online` dirs. This is the user-progress data most likely to be painful to lose.

3. `/storage/.guest/korri/roms` — `68M`
   - Korri GBA ROM library plus save files: `Drill Dozer (U).sav` (`32K`) and `Legend of Zelda, The - The Minish Cap (U).sav` (`8K`). ROMs are not repo-derived.

4. `/storage/.guest/korri/library` — `20K`
   - Korri library/launcher metadata: `games.yaml`, `launch-targets.yaml`, `launcher-profiles.yaml`, and a timestamped `games.yaml` backup. Small but important for preserving library presentation and launch wiring.

5. `/storage/.guest/backups` — `144K`
   - Existing external-card BOTW save-import backup/provenance. It appears to contain only BOTW metadata files, not the current full save, but it is small and documents the import source.

6. Top-level ad-hoc scripts/config/docs in `/storage/.guest` — about `236K` total for top-level files
   - Back up the root-level `*.sh`, `*.nix`, `*.py`, `*.md`, `*.txt` files. `70/88` remote script/doc/config basenames were not found in the local repo by basename, so these likely include live experiments and device-specific operational knowledge. Exclude obvious runtime-only files if desired (`*.log`, `*.pid`, `latest-*`, `current-*`).

### P1 — useful, but partly rebuildable

7. Cemu config subset: `/storage/.guest/.config/Cemu/settings.xml` (`8.4K`) and `/storage/.guest/.config/Cemu/controllerProfiles` (`16K`)
   - Preserves Cemu paths/controller setup. Do not rely on `/storage/.guest/.config/Cemu/share/mlc01` alone; it is a symlink to `/storage/.guest/roms/bios/cemu/mlc01`.

8. `/storage/.guest/rocknix-nix-guest-packaged` — `2.0M`
   - Packaged source/deployment snapshot with `result -> /nix/store/...nixos-system-bandai...`. Mostly rebuildable from git/Nix, but worth keeping for exact deployed provenance if space is cheap.

9. `/storage/.guest/korri/media` — `600K`
   - Cover art/media generated for Korri library entries. Likely rebuildable/downloadable, but small.

## Rebuildable / low backup value

- `/storage/.guest/.cache` — `4K`; cache only.
- `/storage/.guest/.config/Cemu/graphicPacks` — `14M`; downloaded/generated graphics packs, duplicated under `share/graphicPacks`; can be recreated.
- Cemu log/cache files: `/storage/.guest/.config/Cemu/share/log.txt` (`5.4K`) and `title_list_cache.xml` (`2.0K`).
- Diagnostics/proofs: `/storage/.guest/shots` (`24K`), `/storage/.guest/touch-test` (`16K`), `*.log`, `*.pid`, `latest-*`, `current-*`, `live-checkpoint`.
- No Cemu `shaderCache` directory was found under `/storage/.guest`; the only `shader` matches were static `AMDShaderCrash` graphic-pack workaround files.

## Evidence commands and results

### Scope and filesystem

```sh
ssh -p 2222 root@bandai 'stat -c "%n|%F|%U:%G|mode=%a|size=%s|mtime=%y" /storage/.guest; df -P /storage/.guest'
```

```text
/storage/.guest|directory|root:root|mode=755|size=12288|mtime=2026-05-14 23:14:48.020910587 -0400
Filesystem     1024-blocks      Used Available Capacity Mounted on
/dev/sda19       967796212 254588116 713191712      27% /storage/.guest
```

### Top-level size map

```sh
ssh -p 2222 root@bandai 'du -xh -d 2 /storage/.guest | sort -h'
```

```text
4.0K  /storage/.guest/.cache
8.0K  /storage/.guest/.config/pulse
16K   /storage/.guest/touch-test
24K   /storage/.guest/shots
140K  /storage/.guest/backups/external-card-botw-save-import-20260514-124649
144K  /storage/.guest/backups
600K  /storage/.guest/korri/media
2.0M  /storage/.guest/rocknix-nix-guest-packaged
6.5M  /storage/.guest/roms/bios
18M   /storage/.guest/.config/Cemu
68M   /storage/.guest/korri
68M   /storage/.guest/korri/roms
13G   /storage/.guest/roms
13G   /storage/.guest/roms/wiiu
13G   /storage/.guest
```

### ROMs, BIOS, and Cemu save data

```sh
ssh -p 2222 root@bandai 'du -xh -d 3 /storage/.guest/roms | sort -h; find /storage/.guest/roms -xdev -type f -printf "%s|%TY-%Tm-%Td %TH:%TM:%TS|%p\n" | sort -nr | head -30'
```

```text
6.5M /storage/.guest/roms/bios/cemu/mlc01
6.5M /storage/.guest/roms/bios/cemu
13G  /storage/.guest/roms/wiiu
13G  /storage/.guest/roms
13660330872|2026-05-09 17:04:36.6797318350|/storage/.guest/roms/wiiu/The Legend of Zelda - Breath of the Wild (USA) (DLC) (v208).wua
1027208|2026-05-10 ...|/storage/.guest/roms/bios/cemu/mlc01/usr/save/00050000/101c9400/user/80000001/{0..5}/game_data.sav
65584|2026-05-14 ...|/storage/.guest/roms/bios/cemu/mlc01/usr/save/00050000/101c9400/meta/iconTex.tga
5124|2026-05-14 ...|/storage/.guest/roms/bios/cemu/mlc01/usr/save/system/pdm/80000001/PlayStats.dat
```

```sh
ssh -p 2222 root@bandai 'du -xh -d 6 /storage/.guest/roms/bios/cemu | sort -h'
```

```text
6.2M /storage/.guest/roms/bios/cemu/mlc01/usr/save/00050000/101c9400/user
6.3M /storage/.guest/roms/bios/cemu/mlc01/usr/save/00050000/101c9400
6.4M /storage/.guest/roms/bios/cemu/mlc01/usr/save
6.5M /storage/.guest/roms/bios/cemu/mlc01
6.5M /storage/.guest/roms/bios/cemu
```

### Cemu config and symlink layout

```sh
ssh -p 2222 root@bandai 'find /storage/.guest/.config/Cemu -xdev -maxdepth 2 -mindepth 1 -printf "%y|%p|%s|%TY-%Tm-%Td %TH:%TM:%TS\n" | sort; ls -la /storage/.guest/.config/Cemu/share'
```

```text
f|/storage/.guest/.config/Cemu/settings.xml|8409|2026-05-14 18:05:55...
d|/storage/.guest/.config/Cemu/controllerProfiles|4096|2026-05-14 12:03:24...
f|/storage/.guest/.config/Cemu/controllerProfiles/controller0.xml|2287|2026-05-14 12:03:24...
lrwxrwxrwx ... keys -> /storage/.guest/roms/bios/cemu/keys
lrwxrwxrwx ... mlc01 -> /storage/.guest/roms/bios/cemu/mlc01
lrwxrwxrwx ... online -> /storage/.guest/roms/bios/cemu/online
lrwxrwxrwx ... settings.xml -> /storage/.guest/.config/Cemu/settings.xml
```

### Korri library/media/roms

```sh
ssh -p 2222 root@bandai 'du -xh -d 4 /storage/.guest/korri | sort -h; find /storage/.guest/korri -xdev -type f -printf "%s|%TY-%Tm-%Td %TH:%TM:%TS|%p\n" | sort -nr | head -25'
```

```text
20K  /storage/.guest/korri/library
600K /storage/.guest/korri/media
68M  /storage/.guest/korri/roms/nintendo-gameboy-advance
68M  /storage/.guest/korri/roms
16777216|2024-10-17 ...|/storage/.guest/korri/roms/nintendo-gameboy-advance/Legend of Zelda, The - The Minish Cap (U).gba
11835023|2024-11-17 ...|/storage/.guest/korri/roms/nintendo-gameboy-advance/dkkc3.zip
8388608|...|/storage/.guest/korri/roms/nintendo-gameboy-advance/*.gba
32768|2026-05-13 ...|/storage/.guest/korri/roms/nintendo-gameboy-advance/Drill Dozer (U).sav
8192|2026-05-13 ...|/storage/.guest/korri/roms/nintendo-gameboy-advance/Legend of Zelda, The - The Minish Cap (U).sav
1256|2026-05-14 ...|/storage/.guest/korri/library/games.yaml
1013|2026-05-13 ...|/storage/.guest/korri/library/launch-targets.yaml
265|2026-05-13 ...|/storage/.guest/korri/library/launcher-profiles.yaml
```

### Existing backups

```sh
ssh -p 2222 root@bandai 'du -xh -d 6 /storage/.guest/backups | sort -h; find /storage/.guest/backups -xdev -type f -printf "%s|%TY-%Tm-%Td %TH:%TM:%TS|%p\n" | sort -nr'
```

```text
144K /storage/.guest/backups
65584|2026-05-14 12:29:20...|/storage/.guest/backups/external-card-botw-save-import-20260514-124649/usr/save/00050000/101c9400/meta/iconTex.tga
9912|2026-05-14 12:29:20...|/storage/.guest/backups/external-card-botw-save-import-20260514-124649/usr/save/00050000/101c9400/meta/meta.xml
```

### Ad-hoc scripts/configs vs local repo basenames

```sh
remote=$(ssh -p 2222 root@bandai 'find /storage/.guest -xdev -maxdepth 1 -type f \( -name "*.sh" -o -name "*.nix" -o -name "*.py" -o -name "*.md" -o -name "*.txt" \) -printf "%f\n" | sort')
local=$(find . -path ./.git -prune -o -type f -printf '%f\n' | sort -u)
printf 'not_in_repo_count='; comm -23 <(printf '%s\n' "$remote") <(printf '%s\n' "$local") | wc -l
printf 'in_repo_count='; comm -12 <(printf '%s\n' "$remote") <(printf '%s\n' "$local") | wc -l
printf 'remote_script_doc_config_count='; printf '%s\n' "$remote" | wc -l
```

```text
not_in_repo_count=70
in_repo_count=18
remote_script_doc_config_count=88
```

Representative remote-only basenames: `audio-check.sh`, `btn-validate.sh`, `clean-cemu-potato-rocknixmesa.sh`, `korri-rootfs-apply.sh`, `launch-cemu-candidate.sh`, `register-fex-store.py`, `steam-fhs-live.nix`, `STEAM-SPIKE-MODS.md`, `start_ryujinx.sh`, `start_steam_guest.sh`, `sway-test.sh`.

### Packaged source copy

```sh
ssh -p 2222 root@bandai 'du -xh -d 2 /storage/.guest/rocknix-nix-guest-packaged | sort -h; find /storage/.guest/rocknix-nix-guest-packaged -xdev -maxdepth 1 -type l -exec stat -c "%N" {} \;'
```

```text
2.0M /storage/.guest/rocknix-nix-guest-packaged
/storage/.guest/rocknix-nix-guest-packaged/result -> /nix/store/i13qnjyq2rymvk6bzk2pxj9x0yknr26b-nixos-system-bandai-25.11.20260505.0c88e1f
```
