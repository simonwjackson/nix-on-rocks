# Thor/Bandai `/storage` backup reconnaissance, excluding `/storage/.guest`

Date: 2026-05-21. Host: `bandai` via `ssh -p 2222 root@bandai`.

Scope was read-only: `/storage` only, with `/storage/.guest` pruned/excluded. I used `find`, `du`, `ls`/`stat`-style metadata only; no remote writes, deletes, or mounts.

## Prioritized backup list

### P0 — back up before risky work

1. `/storage/korri/roms` — **6.3G**
   - Why: user-provided game library plus colocated emulator saves. Contains Switch and GBA ROMs, including `.xci`, `.nsp`, `.rar`, `.gba`, `.zip`, and `.sav` files.
   - Especially important saves found:
     - `/storage/korri/roms/nintendo-gameboy-advance/Drill Dozer (U).sav` — 32K
     - `/storage/korri/roms/nintendo-gameboy-advance/wl4.sav` — 0B placeholder/save file
     - `/storage/korri/roms/nintendo-gameboy-advance/Metroid Fusion (USA, Australia).sav` — 0B placeholder/save file
   - Note: archives such as `DWGDLHRTP-...rar` may be redundant if already stored elsewhere, but they are persistent user data on-device.

2. `/storage/.config/Ryujinx/bis/user/save` — **109M**
   - Why: Ryujinx game saves. This is the highest-value emulator state.
   - Also back up `/storage/.config/Ryujinx/bis/user/saveMeta` — **3.4M**.

3. Ryujinx identity/config/key material — small but critical:
   - `/storage/.config/Ryujinx/Config.json` — 8K on disk
   - `/storage/.config/Ryujinx/config-profiles` — 76K
   - `/storage/.config/Ryujinx/system/prod.keys` — 14,612 bytes, sensitive
   - `/storage/.config/Ryujinx/system/title.keys` — 1,292 bytes, sensitive
   - `/storage/.config/Ryujinx/system/Profiles.json` — 65,635 bytes
   - Why: emulator configuration, per-game profiles, user profiles, and Switch key material needed to restore the emulator cleanly.

4. Ryujinx custom content/state:
   - `/storage/.config/Ryujinx/mods` — 696K
   - `/storage/.config/Ryujinx/mods-disabled` — 132K
   - `/storage/.config/Ryujinx/sdcard` — 480K, includes `Nintendo/save` and `atmosphere`
   - `/storage/.config/Ryujinx/games` — **80M total**, but mostly shader caches. Back up non-cache metadata files such as per-game `Config.json`, `mods.json`, and `updates.json`; skip `games/*/cache` unless preserving warm shader cache matters.

### P1 — back up if preserving app/user experience matters

5. `/storage/korri/library` — 60K
   - Why: Korri launch/library metadata (`games.yaml`, `launch-targets.yaml`). Small and useful for restoring frontend state.

6. `/storage/.config/Ryujinx.guest-before-host-sync-20260509-222531` — 196K
   - Why: historical Ryujinx backup/sync snapshot. Cheap to keep; may help recover earlier config/profile state.

7. `/storage/.config/chromium` — 82M total
   - Why: Chromium user profile data. `Default` is only 2.9M and contains `History`, `Cookies`, `Login Data`, `Preferences`, sessions, local storage, etc. Much of the rest is downloadable component/model cache.
   - If minimizing: keep `/storage/.config/chromium/Default` and `/storage/.config/chromium/Local State`; skip large component/model/cache directories.

8. `/storage/.pki/nssdb` — 76K
   - Why: NSS certificate/key database (`cert9.db`, `key4.db`, `pkcs11.txt`). Sensitive; back up only if browser/cert identity matters.

9. Small user/device configs:
   - `/storage/.config/MangoHud/MangoHud.conf` — 213 bytes
   - `/storage/.config/btop/btop.conf` — 9,815 bytes
   - `/storage/.config/rocknix/lid-suspend.disabled` — 0B marker
   - `/storage/.config/nix-apps` — 44K
   - `/storage/.bash_history` — 1,124 bytes, optional/sensitive history

### P2 — optional/convenience, mostly rebuildable

10. `/storage/apps/ryujinx` — 86M
    - Why: local Ryujinx 1.3.3 app bundle/binary. Rebuildable/reinstallable if source/package is available; back up if exact local app version matters.

11. `/storage/.config/Ryujinx/system` — 650M total and `/storage/.config/Ryujinx/bis/system` — 327M
    - Why: mostly firmware zips and installed firmware/system contents. Not user save data, but useful for fast restore if firmware/key sources are not elsewhere.
    - If minimizing, keep only `prod.keys`, `title.keys`, `Profiles.json`, and `README-KEYS-FIRMWARE.txt`; firmware zips and installed contents are rebuildable/reinstallable.

## Rebuildable/low-value caches to skip

- `/storage/.cache` — 228M total. Mostly rebuildable:
  - `/storage/.cache/mesa_shader_cache` — 113M
  - `/storage/.cache/nix` — 106M, including tarball/eval caches
  - `/storage/.cache/chromium` — 7.7M
  - `/storage/.cache/fontconfig` — 1.1M
  - `/storage/.cache/nix-apps` — 1.7M
  - `/storage/.cache/dev.korri.desktop` — WebKit/HSTS cache only
- `/storage/.config/Ryujinx/games/*/cache` — Ryujinx per-game shader caches, included in the 80M `games` total.
- `/storage/.fex-emu` — 352K, observed as server lock plus telemetry files; appears rebuildable.
- Empty/placeholders: `/storage/bin`, `/storage/games-internal`, `/storage/.steam`, `/storage/.nix-defexpr` except symlinked Nix channels.

## Symlink caution

These symlinks are in scope but point into excluded `/storage/.guest`; do not follow them for this non-guest backup. Preserve symlinks only if backing up the directory tree.

- `/storage/roms/wiiu -> /storage/.guest/roms/wiiu`
- `/storage/roms/bios/cemu -> /storage/.guest/roms/bios/cemu`
- `/storage/.config/Cemu -> /storage/.guest/.config/Cemu`
- `/storage/.cache/Cemu -> /storage/.guest/.cache/Cemu`
- `/storage/.local/share/Cemu -> /storage/.guest/.config/Cemu/share`

## Evidence commands/results

### Filesystem and top-level inventory

Command:

```sh
ssh -p 2222 root@bandai 'hostname; id; stat -f -c "%T %i %s %b %a" /storage; find /storage -xdev -mindepth 1 -maxdepth 1 ! -name .guest -printf "%M %u %g %s %TY-%Tm-%Td %TH:%TM %p -> %l\n" | sort'
```

Result excerpt:

```text
bandai
uid=0(root) gid=0(root) groups=0(root)
ext2/ext3 b0a9c598dd035d2b 4096 241949053 178297928
drwxr-xr-x root root 4096 2026-05-13 15:18 /storage/korri ->
drwxr-xr-x root root 4096 2026-05-16 11:18 /storage/roms ->
drwxr-xr-x root root 4096 2026-05-14 16:39 /storage/.config ->
drwxr-xr-x root root 4096 2026-05-14 12:23 /storage/.cache ->
drwxr-xr-x root root 4096 2026-05-09 22:53 /storage/apps ->
-rw------- root root 1124 2026-05-14 00:07 /storage/.bash_history ->
lrwxrwxrwx root root 43 2026-05-08 21:07 /storage/.nix-profile -> /nix/var/nix/profiles/per-user/root/profile
```

### Top-level sizes, excluding `/storage/.guest`

Command:

```sh
ssh -p 2222 root@bandai 'du -xhd1 --exclude=/storage/.guest /storage 2>/dev/null | sort -h'
```

Result:

```text
4.0K	/storage/bin
4.0K	/storage/games-internal
4.0K	/storage/.nix-defexpr
4.0K	/storage/.steam
8.0K	/storage/roms
12K	/storage/.local
76K	/storage/.pki
352K	/storage/.fex-emu
86M	/storage/apps
228M	/storage/.cache
1.3G	/storage/.config
6.3G	/storage/korri
7.8G	/storage
```

### Korri ROM/library evidence

Command:

```sh
ssh -p 2222 root@bandai 'du -xhd3 /storage/korri 2>/dev/null | sort -h | tail -20; find /storage/korri -xdev -type f -printf "%s\t%TY-%Tm-%Td %TH:%TM\t%p\n" 2>/dev/null | sort -nr | head -20'
```

Result excerpt:

```text
60K	/storage/korri/library
68M	/storage/korri/roms/nintendo-gameboy-advance
6.2G	/storage/korri/roms/switch
6.3G	/storage/korri/roms
6.3G	/storage/korri
1996488704	2025-10-02 14:41	/storage/korri/roms/switch/DreamWorks Gabby’s Dollhouse Ready to Party [0100F69020BD8000] [v0].xci
1913238236	2026-05-16 10:19	/storage/korri/roms/switch/DWGDLHRTP-NSwTcH-[BASE]-XCI-Ziperto.rar
1352998695	2026-05-16 10:22	/storage/korri/roms/switch/DWGDLHRTP-NSwTcH-NSP-Update101-Ziperto.rar
1352998167	2025-10-02 15:59	/storage/korri/roms/switch/DreamWorks Gabby’s Dollhouse Ready to Party [0100F69020BD8800] [v65536].nsp
16777216	2024-10-17 23:12	/storage/korri/roms/nintendo-gameboy-advance/Legend of Zelda, The - The Minish Cap (U).gba
32768	2026-05-13 21:03	/storage/korri/roms/nintendo-gameboy-advance/Drill Dozer (U).sav
42780	2026-05-13 01:40	/storage/korri/library/games.yaml
9866	2026-05-13 01:40	/storage/korri/library/launch-targets.yaml
```

### Ryujinx sizes and key files

Command:

```sh
ssh -p 2222 root@bandai 'du -xhd3 /storage/.config/Ryujinx 2>/dev/null | sort -h | tail -40; find /storage/.config/Ryujinx -xdev -maxdepth 3 -type f \( -iname "*.json" -o -iname "*.keys" -o -iname "*.txt" \) -printf "%s\t%TY-%Tm-%Td %TH:%TM\t%p\n" 2>/dev/null | sort -nr | head -30'
```

Result excerpt:

```text
3.4M	/storage/.config/Ryujinx/bis/user/saveMeta
80M	/storage/.config/Ryujinx/games
109M	/storage/.config/Ryujinx/bis/user/save
112M	/storage/.config/Ryujinx/bis/user
326M	/storage/.config/Ryujinx/bis/system/Contents
327M	/storage/.config/Ryujinx/bis/system
438M	/storage/.config/Ryujinx/bis
650M	/storage/.config/Ryujinx/system
1.2G	/storage/.config/Ryujinx
65635	2026-05-14 19:15	/storage/.config/Ryujinx/system/Profiles.json
14612	2026-04-28 23:40	/storage/.config/Ryujinx/system/prod.keys
5569	2026-05-14 19:15	/storage/.config/Ryujinx/Config.json
1292	2026-04-28 23:40	/storage/.config/Ryujinx/system/title.keys
341	2026-04-28 23:27	/storage/.config/Ryujinx/system/README-KEYS-FIRMWARE.txt
```

### Ryujinx save evidence

Command:

```sh
ssh -p 2222 root@bandai 'du -xhd4 /storage/.config/Ryujinx/bis/user/save 2>/dev/null | sort -h | tail -30'
```

Result excerpt:

```text
4.1M	/storage/.config/Ryujinx/bis/user/save/0000000000000001
4.2M	/storage/.config/Ryujinx/bis/user/save/0000000000000002
29M	/storage/.config/Ryujinx/bis/user/save/0000000000000003
33M	/storage/.config/Ryujinx/bis/user/save/0000000000000006
36M	/storage/.config/Ryujinx/bis/user/save/0000000000000007
109M	/storage/.config/Ryujinx/bis/user/save
```

### Apps and cache classification evidence

Command:

```sh
ssh -p 2222 root@bandai 'du -xhd3 /storage/apps 2>/dev/null | sort -h; du -xhd2 /storage/.cache 2>/dev/null | sort -h | tail -20'
```

Result excerpt:

```text
86M	/storage/apps
86M	/storage/apps/ryujinx
86M	/storage/apps/ryujinx/1.3.3
1.1M	/storage/.cache/fontconfig
1.7M	/storage/.cache/nix-apps
7.7M	/storage/.cache/chromium
103M	/storage/.cache/nix/tarball-cache
106M	/storage/.cache/nix
113M	/storage/.cache/mesa_shader_cache
228M	/storage/.cache
```

### Symlink evidence

Command:

```sh
ssh -p 2222 root@bandai 'find /storage -xdev -path /storage/.guest -prune -o -type l -printf "%M %u %g %s %TY-%Tm-%Td %TH:%TM %p -> %l\n" 2>/dev/null | sort'
```

Result excerpt:

```text
lrwxrwxrwx root root 25 2026-05-14 12:24 /storage/roms/wiiu -> /storage/.guest/roms/wiiu
lrwxrwxrwx root root 27 2026-05-14 12:23 /storage/.cache/Cemu -> /storage/.guest/.cache/Cemu
lrwxrwxrwx root root 28 2026-05-14 12:23 /storage/.config/Cemu -> /storage/.guest/.config/Cemu
lrwxrwxrwx root root 30 2026-05-14 12:23 /storage/roms/bios/cemu -> /storage/.guest/roms/bios/cemu
lrwxrwxrwx root root 34 2026-05-14 12:23 /storage/.local/share/Cemu -> /storage/.guest/.config/Cemu/share
lrwxrwxrwx root root 43 2026-05-08 21:07 /storage/.nix-profile -> /nix/var/nix/profiles/per-user/root/profile
```
