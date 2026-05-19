# /storage audit — bandai + sobo

Date: 2026-05-14
Hosts: `bandai` (thor host, SM8550 desktop), `sobo` (SM8550 portable)
Architecture (both): trimmed-down ROCKNIX host + NixOS guest running as `rocknix-guest.service` under `systemd-nspawn`. `/storage` is the same `/dev/sda19` ext4 partition, bind-mounted into the guest namespace — host and guest see identical contents, so this audit is per-device, not per-namespace.

## Capacity at a glance

| device | size | used  | free | %    | guest rootfs at        |
|--------|------|-------|------|------|------------------------|
| bandai | 923G | 272G  | 650G | 30%  | /storage/machines/rocknix-guest |
| sobo   | 94.5G| 87.5G | 6.9G | 93%  | /storage/machines/rocknix-guest |

> **sobo is critical (6.9G free).** Prioritise tier 1–3 cleanup there. bandai has plenty of headroom and only tier 1 is worth touching.

Raw listings (kept off-document for size):
- `/tmp/storage-audit/bandai-raw.tsv` (5,907,266 entries, 846 MB)
- `/tmp/storage-audit/sobo-raw.tsv`   (1,909,986 entries, 262 MB)
- `/tmp/storage-audit/{bandai,sobo}-top.txt`, `-l2.txt`, `-l3.txt`, `-signals.txt`

---

## Legend

- 🟥 **Tier 1 — delete now.** Almost certainly garbage; safe on both devices. Timestamped backups, snapshot logs, leftover machinectl orphans, scratch dirs.
- 🟧 **Tier 2 — delete after a sanity check.** Regenerable caches, superseded archives, finished experiment payloads.
- 🟨 **Tier 3 — delete if you reclaim space.** Per-app caches and replaceable assets. Lose state but easy to rebuild.
- 🟩 **Tier 4 — keep.** Live state, current guest rootfs, current Nix store.

> **Out of scope for this audit:** games, ROMs, savegames, Steam library, and anything under `/storage/games-internal`, `/storage/games-external`, `/storage/.steam*`, `/storage/.guest/roms`. They are kept unconditionally and intentionally not enumerated here — do **not** add them to any delete list.
- ⬜ **Tier 5 — investigate.** Looks suspicious but needs you to confirm it's not load-bearing.

Sizes are bytes from `du -sb` rounded.

---

# bandai (thor host) — 272 GB used, 650 GB free

## 🟥 Tier 1 — delete now (≈ 4.4 GB easy wins)

### Editor-lock / machinectl orphans (≈ 4.0 GB)
Left over from interrupted `machinectl clone`. mtimes 2026-05-07, current guest is unrelated.
- `/storage/machines/.#machine.rocknix-guest167625662479f279/` — 2,023,421,665 B
- `/storage/machines/.#machine.rocknix-guestb2fe91d33abd5bdc/` — 2,299,003,342 B
- `/storage/machines/.#rocknix-guest.lck` — 0 B (stale)

### Cemu settings.xml `.bak.NNNN` rotation (60+ files, tiny but pure noise)
Cemu spawns a new `.bak.<pid>` every launch. Keep `settings.xml`, drop the rest:
- `/storage/.config/Cemu/settings.xml.bak.*` (60+ files)
- `/storage/.guest/.config/Cemu/settings.xml.bak.*` (8 files)
- `/storage/.guest/.config/Cemu/settings.xml.pre-audio-api-restore.143506`
- `/storage/.guest/.config/Cemu/settings.xml.pre-restore-15501.143613`
- `/storage/.guest/.config/Cemu/settings.xml.bak.audio.20260514-{163213,172003}`
- `/storage/.guest/backups/settings.xml.audio-device-20260514-131040.bak` (8 KB)

### Timestamped `.before-*` / `.bak-*` config snapshots (~1 MB total)
All have a sibling file with the live state; the dated copy is a manual rollback point you don't need any more:
- `/storage/bin/start_switch.sh.bak-before-thor-16g-20260504-175528`
- `/storage/bin/start_steam_desktop_ui.sh.bak-scale-20260505-005700`
- `/storage/power-profile-before-ultra-eco-20260504-182541.txt`
- `/storage/steam-wrapper-before-busybox-readlink-fix-20260505-111050`
- `/storage/.config/emulationstation/es_systems.cfg.bak-before-switch-20260504-174745`
- `/storage/.config/emulationstation/es_systems.cfg.bak-before-switch-20260504-174804`
- `/storage/.config/emulationstation/es_systems.cfg.bak-before-switch-20260505-122107`
- `/storage/.config/Ryujinx/Config.json.bak-before-gamepad-20260428215414`
- `/storage/.config/Ryujinx/Config.json.bak-before-1080p60-20260428221539`
- `/storage/.config/Ryujinx/Config.json.bak-before-launch-profiles-20260428230901`
- `/storage/.config/Ryujinx/Config.json.bak-before-fps-research-20260428225630`
- `/storage/.config/system.d/rocknix-guest-v2.service.d/99-tty-binding.conf.bak`
- `/storage/.config/system.d/rocknix-guest-v2.service.d/99-tty-binding.conf.before-remove-cache-bind.20260509113745`
- `/storage/.config/system.d/rocknix-guest-v2.service.d/99-tty-binding.conf.before-cache-bind.20260509113542`
- `/storage/.config/system.cfg.pre-tailscale-fix.bak`
- `/storage/.config/cloud_sync.conf.bak`
- `/storage/.config/cloud_sync-rules.txt.bak`
- `/storage/.config/system/configs/system.cfg.bak.20260507-012715`
- `/storage/.config/dolphin-emu/btdinf.bak`
- `/storage/.guest/botw-guest.sh.pre-mangohud`

### Finished-experiment payloads (≈ 75 MB)
- `/storage/cleanup-backups/nix-portable-legacy-20260505-221006` — 74,706,366 B (already labelled "cleanup-backups", nine days old)
- `/storage/bin/balatro-archive-20260505` — 40,362 B

### Stage / live debug logs and screenshots
- `/storage/.guest/stage10-bad-generation-drill-20260514T053744Z.log` — 18 KB
- `/storage/.guest/antimicrox.log` (6 KB), `antimicrox-xcb.log` (721 KB)
- `/storage/.guest/korri-desktop-odin.log` (8 KB), `session-dbus.log` (18 KB)
- `/storage/.guest/dsi1.png`, `dsi2.png`, plus assorted `*-DSI*.png` and `*-popup.png` screenshots — ~470 KB total
- `/storage/.guest/sdl-jstest-list*.log`, `jstest-gtk.log`, `gamepad-tool.log`, `ryubing-host-tune.log` — small
- `/storage/.guest/*-live-launch-cleanup.log`, `*-live-retry-cleanup.log`, `*-live-final-cleanup.log`, `ryubing-cleanup.log` — small, all from the cemu campaign

### Stale top-level scratch
- `/storage/.tmp/*-workdir/` — all empty overlayfs workdirs, contents 0 B; the dirs themselves are referenced by something (`canary-nat.nft` etc) so `rm -rf /storage/.tmp/*` is safe but `/storage/.tmp` itself should stay
- `/storage/.starbucks-wifi-watchdog.log` (4 KB) — leave the .sh, delete the .log
- `/storage/host:` (4 KB, looks like a typo'd filename from a `cp host: …`)
- `/storage/idVendor`, `/storage/idProduct` (4 KB each, sysfs artifacts copied by mistake)
- `/storage/korri-bottom-keyboard.pid`, `korri-electrobun-*.pid`, `wsprobe.pid` — all stale PID files (4 KB each)
- `/storage/host` (4 KB) — looks like another stray

### Per-app rotating logs (Chromium)
`/storage/apps/chromium/korri-profile/Default/**/LOG.old` (18 files, all small) — Chromium will recreate.

---

## 🟧 Tier 2 — verify, then delete (≈ 22 GB)

### Cemu campaign runs (≈ 145 MB)
`/storage/.guest/runs/` — 145,782,545 B total, mostly timestamped subdirs `20260509-*`, `20260510-*`, `20260511-*` covering the cemu/steam/balatro probe campaign that is now closed. Includes 22+ `ryujinx-startup.strace.220*` files and several PNG screenshots. Once you've extracted any findings, the whole tree can go. The newest is `20260511-120339-balatro-real-uinput-test`.

### Guest experiment artifacts at /storage/.guest top level
- `/storage/.guest/korri-thor-rootfs-20260512.tar.zst` — 2,767,296,191 B (2.7 GB rootfs snapshot, 2 days old)
- `/storage/.guest/rocknix-cemu-u2-closure.nar.zst` — 639,132,386 B (referenced by `.guest/rocknix-cemu-u2-*` import log; if the closure has already been imported into the guest store, delete)
- `/storage/.guest/rocknix-nix-guest-packaged.previous` — 1,683,060 B (previous generation marker, deletable once current is stable)
- `/storage/.guest/.runner-botw-*.sh`, `.candidate-cemu-*.sh`, `.campaign-cemu-*.sh`, `.live-minimal-direct-*.sh`, `.manual-candidate-botw*.sh`, `.botw-potato-rocknixmesa-mangohud.sh`, `.launch-now-botw-720p45.sh` — ~80 KB of dotfile launchers from cemu campaign; superseded by the non-dot scripts in the same dir
- `/storage/.guest/host-tune.sh`, `host-mesa-libs/`, `host-freedreno-icd.json`, `host-nix-store`, `host-var-log` — verify which are bind-mount targets vs leftovers
- `/storage/.guest/backups/cemu-state-migration-20260514-122300` — 86,472,006 B (today's migration backup; keep one more day, then drop)
- `/storage/.guest/backups/host-cemu-config-import-20260514-123459` — 43,235,873 B (same)

### Chromium guest debug profile
- `/storage/.guest/korri/chromium-youtube` — 140,835,194 B — debug Chromium profile from YouTube test
- `/storage/.guest/korri/chromium-youtube-test.log`, `chromium-youtube-test.pid` — small
- `/storage/.guest/korri/mgba-qt-test.log`, `mgba-qt-test.pid`, `vbam-test.log` — small
- `/storage/.guest/korri/library.backup.20260514T004933Z` — 56,742 B
- `/storage/.guest/korri/cache` — 1,460,259 B

### Korri/electrobun retained drops
- `/storage/korri-electrobun-debug/` — 125,298,526 B
- `/storage/korri-electrobun-visible-oldwebkit/` — 125,801,316 B
- `/storage/korri-electrobun-visible-wrapper-only/` — 125,801,324 B

Same idea three times: each is a frozen electrobun debug bundle. The "current" one lives elsewhere; these are A/B comparison drops, ~376 MB combined.

### Bun install cache (might be regenerable)
- `/storage/.bun/install` — 1,379,021,440 B — verify nothing references it directly; if you only use `bun install --no-cache` in CI it can go.

### Korri repo node_modules
- `/storage/korri/node_modules` — 1,373,750,758 B — only delete if you don't develop on-device; otherwise keep.

---

## 🟨 Tier 3 — drop if you need space (≈ 100 GB)

### Caches that regenerate
- `/storage/.cache/Cemu` — 59,520,563 B
- `/storage/.cache/mesa_shader_cache` — 70,978,184 B
- `/storage/.cache/dolphin-emu` — 3,099,793 B
- `/storage/.cache/nix-install` — 140,731,788 B (only useful for re-bootstrap)
- `/storage/.cache/rocknix-layer10b-rootfs-artifacts` — 262,047,471 B
- `/storage/.cache/rocknix-layer12-rootfs-artifacts` — 262,626,823 B
- `/storage/.cache/rocknix-layer10b-nix-integration-package-2d394bec52` — 326,047 B
- `/storage/.cache/dev.korri.desktop` — 1,724,847 B
- `/storage/.cache/gp.zip` — 2,062,449 B
- `/storage/.guest/.cache/mesa_shader_cache` — 16,290,404 B
- `/storage/.guest/.cache/Cemu` — 82,044,241 B

### Bun cache (separate from install)
- `/storage/.bun` total — 1.4 GB; can go on a clean device

### Replaceable runtime / bundles
- `/storage/.guest/rocknix-graphics-runtime` — 21,740,791 B (rebuilt by guest activation)
- `/storage/.guest/rocknix-lib` — 120,973,776 B (same)
- `/storage/.guest/rocknix-ld-linux-aarch64.so.1` — 201,056 B (links into host)
- `/storage/.guest/empty-vk-layers/` — 4 KB placeholder
- `/storage/.nix-portable` — 18,978,842,874 B (19 GB!) — only used by `nix-portable` bootstrap. If `/storage/.nix-root` is healthy you don't need this.
- `/storage/.local/share/fex-emu` — 5,321,991,559 B (5.3 GB). Fex prebuilt thunks. Will regenerate (slow) on next launch; delete only if you're not using x86 emulation.
- `/storage/.local/share/nix-apps` — 158,655,629 B
- `/storage/.local/share/jellyfin-desktop` — 3,097,892 B

### Korri media & jellyfin
- `/storage/.local/share/jellyfin` — 565,081 B (DB+icons; harmless to keep)
- `/storage/.cache/jellyfin-desktop` — 48,680 B

---

## ⬜ Tier 5 — investigate (don't delete blind)

- `/storage/.guest/host-nix-store`, `/storage/.guest/host-var-log` — names suggest bind-mount targets that the guest mounts from. Confirm they're empty mountpoints before treating them as data.
- `/storage/.guest/init`, `pid`, `dev`, `proc`, `mnt`, `lib`, `etc`, `bin`, `cache`, `home`, `nix` shown under `/storage/.guest` — these look like the guest rootfs internals leaking into the host's `.guest` dir. Verify: is `/storage/.guest` the guest rootfs root, or just a scratch dir? If rootfs, **do not delete** anything here.
- `/storage/.bin/` (8 KB) vs `/storage/bin/` (97 MB) — two parallel bin dirs; only one is on PATH.
- `/storage/canary-nat.nft` (4 KB), `/storage/wifi-canary/` (44 KB) — watchdog data; keep until you confirm wifi watchdog is retired.
- `/storage/inputd-listen.ts`, `inputd-listen-filter.ts`, `read-event-stream.ts`, `wsclient.ts`, `wsprobe.ts`, `who-holds-snd.sh`, `setup_opengl_driver.sh`, `run_egl.sh`, `run_egl2.sh`, `run_vk.sh`, `launch_guest_sway.sh`, `e1-suspend-cycle.sh` — top-level scripts; pick up into `/storage/bin/` or `~/.config/scripts/` and delete the loose copies.

---

## 🟩 Tier 4 — keep

- `/storage/machines/rocknix-guest/` — 24.6 GB live guest rootfs
- `/storage/.nix-root` — 58.8 GB live host Nix store
- `/storage/.config/Ryujinx`, `Cemu`, `retroarch`, `dolphin-emu`, `scummvm`, `emulationstation`, `PortMaster`, `Ryujinx` — live emulator state
- `/storage/.local/share/fex-emu` already listed Tier 3 — listed under "drop if needed", *not* mandatory
- `/storage/.ssh`, `/storage/.config/wireguard`, `/storage/.config/zerotier`, `/storage/.config/tailscale*`, `/storage/.cache/tailscale`, `/storage/.cache/iwd`, `/storage/.cache/connman`, `/storage/.cache/bluetooth`
- `/storage/korri` (repo) — 38 MB without node_modules
- `/storage/.pki`

---

# sobo (SM8550 portable) — 87.5 GB used, 6.9 GB free ⚠

`/storage` is 93 % full. Aim for tier 1 + 2; tier 3 likely needed.

## 🟥 Tier 1 — delete now (≈ 4 GB)

### Old guest rootfs
- `/storage/machines/rocknix-guest.old/` — **1,124,712,532 B** — mtime 2026-05-11, replaced by current `rocknix-guest`. Direct 1 GB win.
- `/storage/machines/.#rocknix-guest.lck` — 0 B stale lock

### Stage10 closure proof artifacts
- `/storage/.guest/stage10-proof/` — **8,403,148,678 B (8.4 GB!)** — contains `sobo-B.closure`, `sobo-B.nar`, `sobo-B.nar.sha256`. This is a one-shot validation export from the stage10 work. If stage10 is closed out, this is the single biggest fast win on sobo.

### Top-level debug logs from one closed investigation (≈ 28 MB)
All loose log/png/text files at the root of `/storage/` left over from a single sway/headless launch debugging session. Largest items:
- `*.nohup.log` (738 KB)
- `*.snapshot.log`, `*.terminal.log`, `*.log`, `*.png` (twenty-odd small files, ≈ 1 MB combined)
- `headless-sway-screen.png` (703 KB)
- `korri-input-bridge.log` — **26,748,838 B (26 MB)**
- `korri-runtime-rpath-2405.txt` (21 KB)

> Use a glob that excludes `/storage/games*` and `/storage/.steam*` when batch-deleting these; they all sit at the bare `/storage/` root.

### `/storage/backups/` — dated config snapshots only (≈ 5 MB after excluding save archives)
Keep-eligible items in this dir are only the **emulator/system config** snapshots:
- `cemu-controller0.before-*.xml`, `cemu-settings.before-*.xml`
- `system.cfg.before-*` (7 files)
- `sway-config.before-*` (3 files)
- `WiimoteNew.before-wii-nunchuk-*.ini`, `nunchuck-profile.before-wii-nunchuk-*.ini`
- `dolphin-GFX.before-*.ini`, `dolphin-Dolphin.before-*.ini`
- `start_switch.before-mk8-profile-*.sh`, `before-mm2-profile-*.sh`
- `Ryujinx-Config.before-mk8-profile-*.json`, `before-mm2-profile-*.json`
- `Ryujinx-touch-*-20260502*`, `Ryujinx-ABXY-swap-20260502-142909`
- `echoes-revert-20260428-231458` (55 KB)

> The remaining ≈ 140 MB in `/storage/backups/` is save-game restore archives (Zelda / Metroid / Mario Kart / Switch / Wii U / Steam manifests) — **out of scope**, do not delete from this list.

### Cemu settings.xml.bak rotation
- `/storage/.config/Cemu/settings.xml.bak.*` (60+ files like on bandai)

### `start_switch.sh` backup chain in /storage/bin
- `/storage/bin/start_switch.sh.bak-switch-perf-20260428-225841`
- `/storage/bin/start_switch.sh.bak-launch-profiles-20260428230901`
- `/storage/bin/start_switch.sh.bak-captain-toad-profile-20260429-161959`

### Misc top-level scratch
- `/storage/.tmp` (56 KB) — same as bandai, can prune contents.

## 🟧 Tier 2 — verify, then delete (≈ 4–5 GB)

### Scratch / experiment scripts in /storage/tmp (≈ 17 MB after excluding save data)
Only the non-save items in `/storage/tmp/` — anything `*-saves-*` or named like a game asset is out of scope:
- `/storage/tmp/cemu-graphic-packs-975` (2 MB)
- `/storage/tmp/cemu_gp_inspect` (13 MB)
- `/storage/tmp/switch-perf-mods.tgz` (481 KB) + `switch-perf-mods-extracted/` (741 KB)
- `/storage/tmp/smo_upscaling_settings.7z` + extracted dir (~17 KB)
- `/storage/tmp/*.py` repair/inspect scripts that don't bundle save data (20+ files, tiny)
- `/storage/tmp/move-switch-remaining-to-sd.sh`, `wipe-microsd-exfat.sh`

> `/storage/tmp/switch-saves-import` and `totk20*` are **out of scope** — leave them alone.

### Old layered rootfs tarballs in .cache
- `/storage/.cache/rocknix-layer10b-guest-rootfs-aarch64-linux.tar.zst` — 262,425,873 B
- `/storage/.cache/rocknix-main-space-rootfs-aarch64-linux.tar.zst` — **2,037,827,109 B (≈ 2 GB)**
- `/storage/.cache/nix-install` — 140,731,788 B
- `/storage/.cache/Cemu` — 43,298,014 B
- `/storage/.cache/dolphin-emu` — 21,023,937 B
- `/storage/.cache/mesa_shader_cache` — 47,506,486 B
- `/storage/.cache/mesa_shader_cache_db` — 1,574,339 B
- `/storage/.cache/qtshadercache-arm64-little_endian-lp64` — 63,526 B
- `/storage/.cache/FEXConfig` — 136,494 B
- `/storage/.cache/nix-chromium-profile` — 5,733,744 B
- `/storage/.cache/downloads` — 32,006,202 B
- `/storage/.cache/dev.korri.desktop` — 685,371 B
- `/storage/.cache/pip` — 1,472,020 B

### Chromium guest profile
- `/storage/apps/chromium/` — **943,088,181 B** (almost 1 GB). On bandai the equivalent is 89 MB — sobo's is bloated. Wipe Chromium profile data; settings will re-prompt.

### Korri out/ build directory
- `/storage/korri/out` — 229,585,287 B (build artifact)
- `/storage/korri/node_modules` — 1,695,927,071 B (1.7 GB)

### Korri media/cache
- `/storage/korri/media`, `docs`, `bun.lock` — small, keep
- `/storage/korri/tools` (686 KB), `korri/` (970 KB) — keep

## 🟨 Tier 3 — drop if you need space (≈ 35–55 GB)

### .nix-portable (≈ 9 GB)
- `/storage/.nix-portable/nix` — **8,966,408,825 B** — same logic as bandai; if `/storage/machines/rocknix-guest/nix/store` is healthy you don't need this.

### .local/share — **48 GB**
This is the dominant pile on sobo and almost all of it is replaceable:
- `/storage/.local/share/` total — 48,173,757,893 B
- Same families as bandai (fex-emu, nix-apps, jellyfin, etc.) — list with `du -sb /storage/.local/share/*` to triage; the largest bucket is `fex-emu` if x86 emulation is in play.

### Guest store leftovers in /storage/machines/rocknix-guest/nix/store
Look for store paths whose live generation no longer references them; safest with `nix-collect-garbage` inside the guest rather than rm.

## ⬜ Tier 5 — investigate

- `/storage/.guest/rocknix-guest-generation-{import-candidate,switch-a}` — tiny pointer files for guest A/B; keep until A/B retired.
- `/storage/.guest/rocknix-nix-guest-packaged.previous` (1.7 MB) vs `rocknix-nix-guest-packaged` — same pair as bandai.
- `/storage/.guest/stage10-proof/` — confirm stage10 is done before deleting (called out in Tier 1).
- `/storage/.local/lib` (10 MB) — small but unusual location.

## 🟩 Tier 4 — keep

- `/storage/machines/rocknix-guest/` — 15.0 GB live guest rootfs
- `/storage/.config/Ryujinx` (1.2 GB), `Cemu`, `retroarch`, `dolphin-emu`, `scummvm`, `emulationstation`, `PortMaster`, `ppsspp`, `rpcs3` etc.
- `/storage/.ssh`, wireguard, zerotier configs

---

# Suggested first cuts

## sobo (urgent)
1. **Tier 1 stage10-proof** → `rm -rf /storage/.guest/stage10-proof` → **+8.4 GB**
2. **Tier 1 rocknix-guest.old** → `rm -rf /storage/machines/rocknix-guest.old` → **+1.1 GB**
3. **Tier 2 main-space rootfs tarball** → `rm /storage/.cache/rocknix-main-space-rootfs-aarch64-linux.tar.zst /storage/.cache/rocknix-layer10b-guest-rootfs-aarch64-linux.tar.zst` → **+2.3 GB**
4. **Tier 2 /storage/tmp scratch (non-save items only)** → `rm -rf /storage/tmp/cemu_gp_inspect /storage/tmp/cemu-graphic-packs-975 /storage/tmp/switch-perf-mods.tgz /storage/tmp/switch-perf-mods-extracted` → **+15 MB** (the rest of `/storage/tmp/` is save data — out of scope)
5. **Tier 1 backups dir** (after verifying current saves) → `rm -rf /storage/backups` → **+0.14 GB**
6. **Tier 1 top-level debug logs** → `rm /storage/*.log /storage/headless-sway-screen.png /storage/korri-runtime-rpath-2405.txt` (run from `/storage`; double-check the glob does **not** match anything under `games-internal`, `games-external`, `.steam*`, `.guest/roms` — it shouldn't, but `ls` it first) → **+27 MB**
7. **Tier 2 chromium profile** → `rm -rf /storage/apps/chromium` → **+0.94 GB**

Estimated reclaim from the first three actions alone: **≈ 12 GB** (free goes from 6.9 GB → ≈ 19 GB).

## bandai (cleanup only)
1. **Tier 1 machinectl orphans** → `rm -rf /storage/machines/.#machine.rocknix-guest*` → **+4.3 GB**
2. **Tier 1 cleanup-backups** → `rm -rf /storage/cleanup-backups` → **+75 MB**
3. **Tier 2 korri-thor-rootfs tarball** (if no longer needed) → `rm /storage/.guest/korri-thor-rootfs-20260512.tar.zst` → **+2.7 GB**
4. **Tier 2 cemu-u2 closure** (if already imported) → `rm /storage/.guest/rocknix-cemu-u2-closure.nar.zst` → **+0.6 GB**
5. **Tier 2 korri-electrobun A/B drops** → `rm -rf /storage/korri-electrobun-debug /storage/korri-electrobun-visible-oldwebkit /storage/korri-electrobun-visible-wrapper-only` → **+376 MB**
6. **Tier 2 /storage/.guest/runs** (after extracting findings) → `rm -rf /storage/.guest/runs` → **+146 MB**
7. **Tier 2 downloads tarball** → `rm /storage/downloads/GE-Proton10-34.tar.gz*` → **+517 MB**

Estimated reclaim on bandai: **≈ 8.6 GB** — not urgent (650 GB free already) but tidy.
