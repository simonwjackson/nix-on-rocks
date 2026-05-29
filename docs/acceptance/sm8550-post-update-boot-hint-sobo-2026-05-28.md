# SM8550 post-update boot-hint hardening — sobo / Odin2Portal — 2026-05-28

## Result

`DeviceAccepted` for the Layer 14 main-space `/storage/.boot.hint=UPDATE` consumer (`rocknix-post-update.service`) on `sobo` / AYN Odin2Portal (`ayn,odin2portal`).

Scope:

- `BuildProof`: image-only `build-image-only.yml` run completed and verified.
- `ArtifactVerified`: image-only update tar + img.gz artifact verified locally including SM8550 FAT geometry and Gate 2 KERNEL/SYSTEM md5 expectations.
- `DeviceAccepted`: update tar applied through normal `/storage/.update/` path; three on-device behavior passes (happy / no-op / recovery) all observed as designed.
- `HandsOnAcceptance`: NotRun/Deferred — no screen/input/Moonlight smoke checks were run.
- `ReleasePublication`: NotPublished/Deferred — no release tag was published in this phase.

Plan resolved: `docs/plans/2026-05-27-002-fix-main-space-post-update-boot-hint-plan.md` units U1–U3.

Phase 4 caveat resolved: the `/storage/.boot.hint=UPDATE` residual recorded in `docs/acceptance/sm8550-product-payload-full-build-sobo-2026-05-27.md` is now consumed on main-space boot by `rocknix-post-update.service`.

This evidence applies only to sobo / Odin2Portal. Thor remains a separate lane.

## Build proof

- Product repo: `https://github.com/simonwjackson/nix-on-rocks`
- Branch: `refactor/product-payload-image-consumption`
- Product SHA: `ef65fbdde7ac9133cfb420f49362f7e465a39dec`
- Image-only run (this acceptance): `https://github.com/simonwjackson/nix-on-rocks/actions/runs/26551856521`
- Base run consumed: `prepare-sm8550-base.yml` run `26505366012` (sha `887b1aa4fa541ad0ea512eec5434229c81cc1070`)
- `packaging_only_accept_stale_base=true` (substrate-only patch delta; toolchain base unchanged; first cutover proof was Phase 3/4)
- Upstream ROCKNIX SHA: `f080b462f54b5807bdd16ac7cc2ab64528b038b1`
- Source branch SHA: `3ed044db39bcf69256fbae02fa4b17595da3a0c1`
- Patch-series hash: `633f9022a29035af39eca4acc44a5bc47124b3bf17cedc19f3f07b69cde74122`
- Rendered product payload hash: `2e2108c51fb5ef327f773f2606604fc32aabd38a921d85b9c45e503601578f2a`

## Active product payload

From `product-payload.lock` at the proven SHA:

- Authority repo: `simonwjackson/korri`
- Product revision: `a3fabfd8a35190cd23d027f4f8569bc11344a3d5`
- Product source SHA256: `0dea10b50a12d2a96944d44d401d4786f95768d4e79df7a13a237d4fcef0f80d`
- Build target: `.#nixosConfigurations.korri-rocknix-kiosk-odin2portal.config.system.build.toplevel`
- Seed device: `odin2portal`
- Seed compatible: `ayn,odin2portal`
- Seed archive: `rocknix-guest-rootfs-odin2portal-a3fabfd8a351.tar.zst`
- Seed SHA256: `bdfe9a73acc327c77b3c813d7c284bfc4c182b930b436b24cdcfa878d73ccd0a`

## Artifacts

Downloaded artifact: `nix-on-rocks-sm8550-image-only-26551856521`

Payloads:

- `ROCKNIX-SM8550.aarch64-20260528.tar`
  - SHA256: `c3b15de40e84312f2cc216b6b9ddb290ccf9042f7916ee43df1e09228ccacabb`
- `ROCKNIX-SM8550.aarch64-20260528.img.gz`
  - SHA256: `8da0e6a4561f5fc5589090186298bc9ed59f4e942254d13693e10f98405e27c1`

Local verification before install (via `rocknix_artifact_verify`):

- FAT label `ROCKNIX`
- FAT logical block size `4096`
- KERNEL md5 (from update tar): `f6a3e62f440b3f47093db740edad5f66`
- SYSTEM md5 (from update tar): `723404d835a57cbfdc33f1ddcd1228ad`

Expected on-device hashes after install:

- KERNEL md5: `f6a3e62f440b3f47093db740edad5f66`
- SYSTEM md5: `723404d835a57cbfdc33f1ddcd1228ad`

## Pre-install device state

- LAN host: `192.168.1.239`
- Compatible strings:
  - `ayn,odin2portal`
  - `qcom,qcs8550`
  - `qcom,sm8550`
- Pre-install build label: `SM8550.aarch64-20260527` (Phase 4 image)
- Pre-install KERNEL md5: `42386591bf1bda598f54693cda60a82f`
- Pre-install SYSTEM md5: `2fb7374a51673dc5976c29d808fba22c`
- Pre-install `/storage/.boot.hint`: `UPDATE` (residual from Phase 4 install; same residual that motivated this plan)
- Pre-install `/flash/rocknix.no-nspawn`: absent
- Pre-install `rocknix.safe` cmdline: not set
- Pre-install `/usr/lib/systemd/system/rocknix-post-update.service`: NOT present (Phase 4 image predates this patch)
- Pre-install `/usr/bin/rocknix-post-update`: NOT present (Phase 4 image predates this patch)
- Pre-install legacy `/usr/lib/autostart/common/003-upgrade`: present (unchanged)
- Pre-install `/usr/share/post-update`: present
- Pre-install `/var/log/upgrade.log`: absent (never run on this device since Phase 4 — confirming the bug)
- Pre-install free units: `rocknix-report-stats.service` (failed; pre-existing, not a regression)
- Pre-install `/storage` free: `37.1G`

## Install path

Installed through the normal ROCKNIX update path:

1. Cleared `/storage/.update/`.
2. `rsync -av --progress -e 'ssh -o ServerAliveInterval=20 -o ServerAliveCountMax=20'` of `ROCKNIX-SM8550.aarch64-20260528.tar` to `root@192.168.1.239:/storage/.update/`. (Used `rsync` over a kept-alive SSH per handoff note; BusyBox `scp` closes mid-transfer for multi-GB tars.)
2. Verified on-device sha256 = `c3b15de40e84312f2cc216b6b9ddb290ccf9042f7916ee43df1e09228ccacabb`.
3. `systemctl reboot`; initramfs applied the update.

No ABL/firmware partitions intentionally touched.

## Pass A — happy path (cutover proof)

Reboot timestamp: `2026-05-28T05:35:56Z`. SSH back: `2026-05-28T05:36:54Z`.

Observed:

- Build label: `SM8550.aarch64-20260528` (new image active)
- `default.target`: `rocknix-main-space.target` (`ActiveState=active`)
- `/storage/.boot.hint`: `absent`
- KERNEL md5: `f6a3e62f440b3f47093db740edad5f66` (matches manifest)
- SYSTEM md5: `723404d835a57cbfdc33f1ddcd1228ad` (matches manifest)
- `/usr/lib/systemd/system/rocknix-post-update.service`: present (`-rw-r--r-- 954 bytes`)
- `/usr/bin/rocknix-post-update`: present (`-rwxr-xr-x 2602 bytes`)
- `rocknix-post-update.service`: `active (exited)` `status=0/SUCCESS` in `~250ms` at `05:36:42-05:36:43`
- Journal:

  ```text
  Starting rocknix-post-update.service...
  rocknix-post-update: consuming UPDATE hint on main-space boot
  Finished rocknix-post-update.service.
  ```

- `/var/log/upgrade.log` first entry: `rocknix-post-update: consuming UPDATE hint on main-space boot` followed by `/usr/share/post-update` hook stdout/stderr (rsync/cp noise from the legacy post-update hook walking paths that don't exist on the guest-based image; same noise the legacy 003-upgrade consumer would produce on this image)
- `/storage/.update/`: empty
- `rocknix-guest.service`: `active`
- `systemctl --failed`: none — `rocknix-report-stats.service` failure no longer present after update install
- ABL partition labels intact (`abl_a`, `abl_b`, `boot_a`, `boot_b` all present under `/dev/disk/by-partlabel/`)

Assertions held: R1, R2, R3, R4, R8.

## Pass B — no-op path (preserves unknown hint content)

Pre-reboot setup:

- `rm /storage/.boot.hint`
- `printf 'FOO-SENTINEL' > /storage/.boot.hint`

Reboot timestamp: `2026-05-28T05:37:45Z`. SSH back: `2026-05-28T05:38:15Z`.

Observed:

- `/storage/.boot.hint`: still `FOO-SENTINEL` (preserved, NOT consumed)
- `rocknix-post-update.service`: `active (exited)` `status=0/SUCCESS` in `~8ms`
- Journal:

  ```text
  Starting rocknix-post-update.service...
  rocknix-post-update: skipping: unexpected hint content (left in place)
  Finished rocknix-post-update.service.
  ```

- `/var/log/upgrade.log` appended: `rocknix-post-update: skipping: unexpected hint content (left in place)`
- `default.target`: `rocknix-main-space.target`
- `rocknix-guest.service`: `active`
- `systemctl --failed`: none

Assertions held: R3, R6.

## Pass C — recovery boundary (no-nspawn flag)

Pre-reboot setup:

- `mount -o remount,rw /flash`
- `echo UPDATE > /storage/.boot.hint`
- `touch /flash/rocknix.no-nspawn`
- `mount -o remount,ro /flash`

Reboot timestamp: `2026-05-28T05:43:11Z`. SSH back: `2026-05-28T05:45:04Z`.

Observed:

- `default.target`: `multi-user.target` (`ActiveState=active`) — recovery routed by `libreelec-target-generator`
- `rocknix-main-space.target`: `inactive (dead)`
- `rocknix-guest.service`: `inactive`
- `/storage/.boot.hint`: still `UPDATE` (preserved during recovery boot)
- `/flash/rocknix.no-nspawn`: present
- `rocknix-post-update.service`: `inactive (dead)` — Condition guards held
- Journal for `rocknix-post-update`: `-- No entries --` (service never attempted to start)
- `systemctl --failed`: none

Assertions held: R5 (recovery boundary intact), R3 (idempotent — service is a no-op when its Condition is unmet).

### Note on legacy consumer in recovery

The plan's Pass C wording anticipated that the legacy `003-upgrade` autostart entry would consume the hint during recovery. On the modern substrate the recovery target is `multi-user.target` (SSH-first recovery), not `rocknix.target`, so the legacy autostart chain is not invoked under recovery either. The key recovery-boundary assertion was that `rocknix-post-update.service` must yield to recovery (R5); this held. Static checks already pin the legacy entry as unchanged (R5 build-time half).

If a future recovery model wants the hint consumed under recovery, that becomes a separate plan; this fix does not regress the existing recovery posture.

## Cleanup pass — idempotent no-op

Pre-reboot:

- `mount -o remount,rw /flash`
- `rm /flash/rocknix.no-nspawn`
- `mount -o remount,ro /flash`
- `rm /storage/.boot.hint`

Reboot timestamp: `2026-05-28T05:45:35Z`. SSH back: `2026-05-28T05:46:05Z`.

Observed:

- `default.target`: `rocknix-main-space.target`
- `/storage/.boot.hint`: absent
- `/flash/rocknix.no-nspawn`: absent
- `rocknix-guest.service`: `active`
- `rocknix-post-update.service`: `inactive (dead)`, condition explicitly logged:

  ```text
  Condition: start condition unmet at Thu 2026-05-28 05:45:46 UTC; 20s ago
             └─ ConditionPathExists=/storage/.boot.hint was not met
  rocknix-post-update.service was skipped because of an unmet condition check (ConditionPathExists=/storage/.boot.hint).
  ```

- `systemctl --failed`: none

Assertions held: R3 (no-op when no hint present; service does not run).

## Validation summary

Local pre-CI:

- `scripts/apply-rocknix-patches`: passed
- `scripts/verify-sm8550-contract`: passed (substrate static-checks include all 23 new rocknix-post-update assertions)
- `scripts/verify-sm8550-locks`: passed
- `scripts/verify-product-payload`: passed
- `guest/scripts/static-checks.sh`: passed
- `shellcheck -s sh rocknix-post-update`: clean

CI (build-image-only run `26551856521`):

- `Apply patches and verify SM8550 contract`: ok
- `Download base provenance`: ok
- `Acknowledge packaging-only stale-base override`: ok
- `Build SM8550 image and manifest`: ok
- `Verify SM8550 payloads`: ok

Artifact verification (`rocknix_artifact_verify`):

- `fat-label: LABEL=ROCKNIX`
- `fat-block-size: BLOCK_SIZE=4096`
- `kernel-md5`: `f6a3e62f440b3f47093db740edad5f66` (matches manifest)
- `system-md5`: `723404d835a57cbfdc33f1ddcd1228ad` (matches manifest)

Device behavior:

- Pass A (happy): hint consumed, log written, ABL untouched, guest active, no failed units
- Pass B (no-op): non-`UPDATE` hint preserved across reboot
- Pass C (recovery): `multi-user.target` active, new service did not start, hint preserved
- Cleanup: condition-unmet skip when no hint present

## Acceptance

`DeviceAccepted` for `rocknix-post-update.service` boot-hint hardening on sobo / AYN Odin2Portal (`ayn,odin2portal`).

- `BuildProof`: `build-image-only.yml` run `26551856521` (CI green; substrate static-checks include the new assertions)
- `ArtifactVerified`: update tar and img.gz sha256 verified; SM8550 FAT geometry verified; manifest carries product payload facts
- `DeviceAccepted`: three passes plus cleanup observed as designed; no regressions in guest activation, KERNEL/SYSTEM hashes, or ABL
- `HandsOnAcceptance`: NotRun/Deferred
- `ReleasePublication`: NotPublished/Deferred

Resolves the `/storage/.boot.hint=UPDATE` lifecycle caveat documented in `docs/acceptance/sm8550-product-payload-full-build-sobo-2026-05-27.md`.
