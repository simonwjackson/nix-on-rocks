# SM8550 DeviceAccepted Evidence — bandai / Thor — 2026-05-22

## Result

`DeviceAccepted` for `bandai` / AYN Thor (`ayn,thor`) on the Nix-on-Rocks SM8550 product lane.

This evidence applies only to the Thor-compatible SM8550 device tested here. Do not generalize it to Odin2Portal / `ayn,odin2portal` without the separate sobo evidence already recorded.

## Scope

This was the narrow Phase-5-style device acceptance requested for bandai:

- publish/build a Thor rootfs seed at the same guest revision accepted on sobo;
- build a Thor-pinned SM8550 image-only artifact;
- install through the normal `/storage/.update/` path;
- handle legacy storage migration on a pre-Nix-on-Rocks Thor install;
- capture host service health, guest activation audit, runtime smoke, short soak, and cold reboot evidence.

It did **not** repeat the full destructive install-safety audit that was already recorded for sobo in `docs/ops/sm8550-full-install-safety-audit-2026-05-20.md`.

## Build proof

- Product repo: `https://github.com/simonwjackson/nix-on-rocks`
- Branch: `feat/sm8550-thor-acceptance`
- Product SHA: `9da3b11` after the runbook update; image artifact was built from `8bcd1f0727266b43719b66858ddc94399aacdb6c`
- Image-only workflow run: `https://github.com/simonwjackson/nix-on-rocks/actions/runs/26266211051`
- Base run: `26182181755`
- Upstream ROCKNIX SHA: `f080b462f54b5807bdd16ac7cc2ab64528b038b1`
- Source branch SHA: `3ed044db39bcf69256fbae02fa4b17595da3a0c1`
- Patch-series hash: `f97847670919c084b91cb4b1b717f96ec9cbc0e1e87d587706ea50e257773951`

## Thor seed proof

- Seed release: `https://github.com/simonwjackson/nix-on-rocks/releases/tag/rootfs-seed-thor-d5d00fe4b588`
- Guest revision: `d5d00fe4b58822da8ab0a0c21ea4306a92c65c2a`
- Device: `thor`
- Compatible: `ayn,thor`
- Seed archive: `rocknix-guest-rootfs-thor-d5d00fe4b588.tar.zst`
- Seed SHA256: `0ff2b8c4bbe400d4f9445c6f4350f126d826fa7321f6f9e11d97f32987c8d9bb`
- Seed size from manifest: `2770116795`

The rootfs seed was built on native aarch64 host `fuji` because the GitHub Actions seed workflow successfully built and uploaded artifacts but failed to create the release with `Resource not accessible by integration`. The manually published release assets were verified by streaming both GitHub release asset API URLs and hashing the concatenated bytes:

```text
0ff2b8c4bbe400d4f9445c6f4350f126d826fa7321f6f9e11d97f32987c8d9bb  -
```

Follow-up: repo Actions workflow permissions should be changed to "Read and write permissions" so future `build-rootfs-seed.yml` runs can publish releases without manual intervention.

## Artifacts

Downloaded artifact: `nix-on-rocks-sm8550-image-only-26266211051`

Payloads:

- `ROCKNIX-SM8550.aarch64-20260522.tar`
  - SHA256: `7f2927a75b4c6c6341eac9e84b118d5ce5b0e0cfde3783986f1cde3557e84b66`
- `ROCKNIX-SM8550.aarch64-20260522.img.gz`
  - SHA256: `9adf643e7b67c1a476b13c3642c354dc8ce1abea6cf0235be03824ce82f31ba3`

Local artifact verification before install:

- `scripts/verify-sm8550-payloads /tmp/nix-on-rocks-thor-image/work/rocknix/target`: passed
- `sha256sum -c *.sha256`: passed
- update tar contained `target/SYSTEM`
- update tar contained `target/KERNEL`
- update tar contained `target/seed/rocknix-guest-rootfs-thor-d5d00fe4b588.tar.zst`
- embedded seed extracted from the update tar hashed to `0ff2b8c4bbe400d4f9445c6f4350f126d826fa7321f6f9e11d97f32987c8d9bb`

## Pre-install device state

The device was reachable over Tailscale as `bandai` before reboot and later over LAN as `192.168.1.239` after Tailscale was unavailable during early boot.

Pre-install evidence:

- Compatible strings:
  - `ayn,thor`
  - `qcom,qcs8550`
  - `qcom,sm8550`
- Host `BUILD_ID`: `64a3aa4d1f9815520820cc221817aa869e734d55`
- Host hostname: `thor`
- Runtime mounts:
  - `/dev/sda18 on /flash`
  - `/dev/sda19 on /storage`
- Existing guest substrate revision: `d7d5d72821c509ba42b15f2663cd1bfa2e7c5229`
- Existing legacy root: `/storage/machines/rocknix-guest`
- Existing legacy seam: `/storage/.guest`
- Existing `/storage` free: `680.2G`
- Pre-install failed units:
  - `korri-sessiond.service` (local storage spike service)
  - `rocknix-report-stats.service`
  - `systemd-udev-settle.service`
- Pre-install ABL checksums:

```text
91037267a0578fee2e43ca2a8f109120ce055829edcd860cd117645563bdead6  /dev/disk/by-partlabel/abl_a
91037267a0578fee2e43ca2a8f109120ce055829edcd860cd117645563bdead6  /dev/disk/by-partlabel/abl_b
```

## Install path

Installed through the normal ROCKNIX update path:

1. Copied `ROCKNIX-SM8550.aarch64-20260522.tar` and `.sha256` to `/storage/.update/` on bandai.
   - Needed legacy scp mode (`scp -O`) because the target SSH server did not accept the default SFTP-backed scp mode.
2. Verified on-device:

   ```text
   ROCKNIX-SM8550.aarch64-20260522.tar: OK
   ```

3. Rebooted and let initramfs apply the update.

No Android, firmware, or bootloader partitions were intentionally touched.

## First-boot migration recovery

The update applied and installed the new host substrate, but first boot did not immediately start the guest because bandai had legacy `/storage/.guest` content outside the migration allow-list.

Initial post-install state:

- Host `BUILD_ID`: `f080b462f54b5807bdd16ac7cc2ab64528b038b1`
- Compatible first entry: `ayn,thor`
- `rocknix-guest-root-ensure.service`: failed
- `rocknix-guest.service`: inactive
- Host substrate revision: `d5d00fe4b58822da8ab0a0c21ea4306a92c65c2a`
- Seed manifest was installed and pointed at the Thor seed
- `/storage/nix-on-rock/rootfs/current` contained the migrated legacy root at revision `d7d5d72821c509ba42b15f2663cd1bfa2e7c5229`
- `/storage/nix-on-rock/images/seeds/` was empty
- ABL checksums remained unchanged

Relevant journal:

```text
nix-on-rock-migrate: migrating active guest root: /storage/machines/rocknix-guest -> /storage/nix-on-rock/rootfs/current
nix-on-rock-migrate: migrating packaged guest source: /storage/.guest/rocknix-nix-guest-packaged -> /storage/nix-on-rock/staging/guest-exchange/rocknix-nix-guest-packaged
nix-on-rock-migrate: FAIL: legacy seam still has unmigrated content: /storage/.guest
```

Resolution:

1. Confirmed `/storage/.guest` was on internal `/dev/sda19` and no SD card was touched.
2. Manually staged the Thor seed from the update tar into `/storage/nix-on-rock/images/seeds/` and verified SHA256.
3. Moved 109 unknown legacy seam entries to `/storage/legacy-guest-backup-2026-05-22`:

   ```text
   12.8G /storage/legacy-guest-backup-2026-05-22
   ```

   The moved content was local spike/user state such as `roms/`, `korri/`, Cemu/Steam scripts, diagnostics, `.cache`, `.config`, `backups`, and `shots`. User confirmed Thor had already been backed up and SD should not be touched.

4. Removed the stale migration-in-progress marker left by the failed first migration attempt:

   ```text
   /storage/nix-on-rock/staging/layout-migration-in-progress
   ```

5. Re-ran `rocknix-guest-root-ensure.service`; migration completed and `/storage/.guest` became the legacy alias:

   ```text
   /storage/.guest -> /storage/nix-on-rock/staging/guest-exchange
   ```

6. Forced a clean reseed using `/flash/rocknix.reseed-guest` and restarted `rocknix-guest-root-ensure.service`.

Reseed evidence:

```text
rocknix-guest-root-ensure: synthesized missing guest selected profile from init link: /nix/var/nix/profiles/per-user/root/rocknix-guest-system -> /nix/store/kyybawskxcqq2knrl3jxkd4yhzzd0apr-nixos-system-bandai-25.11.20260505.0c88e1f
rocknix-guest-root-ensure: reseeded guest root is valid: /storage/nix-on-rock/rootfs/current; previous root retained at /storage/nix-on-rock/rootfs/previous
```

After reseed, `rocknix-guest.service` started successfully.

## Final clean device evidence

After cleanup and cold reboot:

- LAN IP used for evidence: `192.168.1.239`
- Host hostname: `thor`
- Installed host `BUILD_ID`: `f080b462f54b5807bdd16ac7cc2ab64528b038b1`
- Compatible strings:
  - `ayn,thor`
  - `qcom,qcs8550`
  - `qcom,sm8550`
- Default target: `rocknix-main-space.target`
- Host system state: `running`
- Host failed units: `0`
- `rocknix-guest.service`: `active`
- `rocknix-guest-promote.service`: `inactive`
- `rocknix-guest-root-ensure.service`: `active`
- `/storage/.update`: empty after update consumption
- Host substrate revision: `d5d00fe4b58822da8ab0a0c21ea4306a92c65c2a`
- `/storage/.guest`: symlink to `/storage/nix-on-rock/staging/guest-exchange`
- Legacy spike backup: `/storage/legacy-guest-backup-2026-05-22` (`12.8G`)
- Rootfs layout:
  - `/storage/nix-on-rock/rootfs/current` = reseeded Thor root
  - `/storage/nix-on-rock/rootfs/previous` = prior migrated legacy root
- `/storage`: `669.0G` available
- `/flash`: `1.9G` available

Installed host seed manifest:

```text
seed_manifest_version=1
seed_device=thor
seed_compatible=ayn,thor
seed_revision=d5d00fe4b58822da8ab0a0c21ea4306a92c65c2a
seed_archive=rocknix-guest-rootfs-thor-d5d00fe4b588.tar.zst
seed_sha256=0ff2b8c4bbe400d4f9445c6f4350f126d826fa7321f6f9e11d97f32987c8d9bb
seed_size=2770116795
seed_source_urls=https://api.github.com/repos/simonwjackson/nix-on-rocks/releases/assets/426703720 https://api.github.com/repos/simonwjackson/nix-on-rocks/releases/assets/426704444
```

Seed completion marker:

```text
seeded_at=2026-05-22T03:50:10Z
seed_revision=d5d00fe4b58822da8ab0a0c21ea4306a92c65c2a
seed_device=thor
seed_compatible=ayn,thor
seed_sha256=0ff2b8c4bbe400d4f9445c6f4350f126d826fa7321f6f9e11d97f32987c8d9bb
seed_size=2770116795
seed_archive=rocknix-guest-rootfs-thor-d5d00fe4b588.tar.zst
seed_source=https://api.github.com/repos/simonwjackson/nix-on-rocks/releases/assets/426703720 https://api.github.com/repos/simonwjackson/nix-on-rocks/releases/assets/426704444
```

Final ABL checksums remained unchanged from pre-install:

```text
91037267a0578fee2e43ca2a8f109120ce055829edcd860cd117645563bdead6  /dev/disk/by-partlabel/abl_a
91037267a0578fee2e43ca2a8f109120ce055829edcd860cd117645563bdead6  /dev/disk/by-partlabel/abl_b
```

Validation commands:

- `rocknix-guest-activation-audit --quiet`: passed
- `ROCKNIX_GUEST_LIVE_SMOKE=1 /usr/lib/rocknix-guest-substrate/tests/guest-substrate-runtime-smoke.sh`: passed

  ```text
  rocknix-guest-substrate thin-host runtime smoke passed
  ```

- `ROCKNIX_REQUIRE_HOST_ESSWAY=no rocknix-guest-soak --hours 0 --interval-seconds 5`: passed with zero alarms

  ```text
  soak passed: 1 samples, zero alarms
  ```

## Cold reboot check

A follow-up reboot returned to the internal install at `192.168.1.239` after approximately 120 seconds.

Cold-reboot evidence:

- Host hostname: `thor`
- Host `BUILD_ID`: `f080b462f54b5807bdd16ac7cc2ab64528b038b1`
- Compatible first entry: `ayn,thor`
- `rocknix-guest.service`: `active`
- `rocknix-guest-promote.service`: `inactive`
- `rocknix-guest-root-ensure.service`: `active`
- `rocknix-guest-activation-audit --quiet`: passed
- short soak: passed with zero alarms
- ABL checksums remained unchanged

## Local cleanup during acceptance

After cold reboot, the host still reported `degraded` because of two pre-existing local/non-product failures:

- `korri-sessiond.service`, a storage-local old spike unit at `/storage/.config/system.d/korri-sessiond.service` running `/storage/korri/scripts/odin/run-sessiond.sh`;
- `systemd-udev-settle.service`, pulled by `rocknix-backlight-10.service` and timing out.

With user approval, the old Korri unit was disabled and failed transient units were reset. Final state was then:

```text
system_state=running
failed_units_start
failed_units_end
```

## Notes / follow-ups

- Tailscale was unavailable immediately after reboot, so final evidence used the LAN IP `192.168.1.239`.
- The host hostname remained `thor`; the guest rootfs path synthesized by root-ensure included `nixos-system-bandai-25.11.20260505.0c88e1f`, proving the Thor profile rootfs was selected.
- The legacy migration allow-list behaved correctly by failing closed on unknown `/storage/.guest` content. For future migration-friendly behavior, consider documenting or implementing a known archive destination for unknown legacy seam content so migrations can preserve spike data without manual intervention.
- Per-device seed manifest dispatch (single image with Odin2Portal + Thor seeds) remains deferred to a follow-up plan.

## Acceptance

`DeviceAccepted` for Nix-on-Rocks on bandai / AYN Thor (`ayn,thor`) for the narrow Phase-5-style path.

The install required manual legacy-seam cleanup and explicit reseed, but it ended in a clean internal boot with host state `running`, zero failed units, active guest, passed activation audit, passed live runtime smoke, passed short soak, cold reboot success, and unchanged ABL partitions.
