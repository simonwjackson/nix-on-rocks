# SM8550 DeviceAccepted Evidence — sobo / Odin2Portal — 2026-05-27

## Result

`DeviceAccepted` for `sobo` / AYN Odin2Portal (`ayn,odin2portal`) on the Nix-on-Rocks SM8550 product lane, sourced from the authoritative full `build-sm8550.yml` Docker/ROCKNIX run.

Scope of this evidence:

- `BuildProof`: full chain `build-sm8550.yml` run completed and verified.
- `ArtifactVerified`: full update tar + full image artifact verified locally including SM8550 FAT geometry.
- `DeviceAccepted`: update tar applied through normal `/storage/.update/` path, host/guest came back green with active product payload facts, ABL unchanged.
- `HandsOnAcceptance`: NotRun/Deferred — no screen/input/Moonlight smoke checks were run as part of this acceptance.
- `ReleasePublication`: NotPublished/Deferred — no release tag was published in this phase.

This evidence applies only to sobo / Odin2Portal. Thor evidence remains separate (`docs/acceptance/sm8550-device-acceptance-2026-05-22-thor.md`).

## Build proof

- Product repo: `https://github.com/simonwjackson/nix-on-rocks`
- Branch: `refactor/product-payload-image-consumption`
- Product SHA: `ea836506446619b805acc7954a190fdee95be446`
- Phase 4 full-build workflow run: `https://github.com/simonwjackson/nix-on-rocks/actions/runs/26539625977`
- Phase 4 continue-from-toolchain confidence run: `https://github.com/simonwjackson/nix-on-rocks/actions/runs/26534216483`
- Toolchain run consumed: `26037562850` (known-good toolchain checkpoint)
- Upstream ROCKNIX SHA: `f080b462f54b5807bdd16ac7cc2ab64528b038b1`
- Source branch SHA: `3ed044db39bcf69256fbae02fa4b17595da3a0c1`
- Patch-series hash: `c600bea4dea990f8bbcf888e531425e161dce7f297d05f77d0ac454b238e258b`
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
- Seed URLs: GitHub release `rocknix-product-payload-a3fabfd8a351` `.tar.zst.part-00` + `.part-01`

## Artifacts

Downloaded artifact: `nix-on-rocks-sm8550-26539625977`

Payloads:

- `ROCKNIX-SM8550.aarch64-20260527.tar`
  - SHA256: `1ce300313c2d2dc8df3d325921c0579c446acc006d1dffdb1f9ce75fa829558f`
- `ROCKNIX-SM8550.aarch64-20260527.img.gz`
  - SHA256: `2d675027e82bef86a7ecfbde22dbb2892d3787b74598c6c4e39368fc14e5e82f`

Local verification before install:

- `scripts/verify-sm8550-payloads --require-full-image work/rocknix/target`: passed
- `sha256sum -c *.sha256` for `.tar` and `.img.gz`: passed
- `scripts/verify-image-fat-sector-size`: FAT label `ROCKNIX`, logical sector size `4096`
- Update tar carried `target/SYSTEM`, `target/KERNEL`, and `target/seed/rocknix-guest-rootfs-odin2portal-a3fabfd8a351.tar.zst`
- Embedded seed SHA256 hashed to `bdfe9a73acc327c77b3c813d7c284bfc4c182b930b436b24cdcfa878d73ccd0a`
- Manifest carried active product payload authority, revision, source SHA256, seed device/compatible/archive/SHA256, rendered payload hash, and patch-series hash

Expected on-device hashes from the Gate 2 build:

- KERNEL md5: `42386591bf1bda598f54693cda60a82f`
- SYSTEM md5: `2fb7374a51673dc5976c29d808fba22c`

## Pre-install device state

- LAN host: `192.168.1.239`
- Compatible strings:
  - `ayn,odin2portal`
  - `qcom,qcs8550`
  - `qcom,sm8550`
- Pre-install host `BUILD_ID`: `f080b462f54b5807bdd16ac7cc2ab64528b038b1` (Phase 3 image-only run `26509482057`)
- Pre-install KERNEL md5: `f6a3e62f440b3f47093db740edad5f66`
- Pre-install SYSTEM md5: `603a7ae69aaabd54b2faa39b9baa2309`
- Pre-install ABL:

  ```text
  59ef01bb919f800c9455aa7864d4178b  /dev/sde64
  59ef01bb919f800c9455aa7864d4178b  /dev/sde65
  ```

- Pre-install `/storage` free: `39.5G`
- Pre-install battery: `68%`
- Pre-install `/storage/.boot.hint`: `UPDATE` (residual from Phase 3 install)
- Pre-install runtime mounts:
  - `/dev/sda18 on /flash` (`vfat`)
  - `/dev/sda19 on /storage` (`ext4`)
  - `/dev/loop0 on /` (`squashfs`)

## Install path

Installed through the normal ROCKNIX update path:

1. Copied `ROCKNIX-SM8550.aarch64-20260527.tar` and `.sha256` to `/storage/.update/`. Used `rsync` over SSH (single SSH session held open) instead of `scp` because the BusyBox `scp` server closed the long-running connection mid-transfer.
2. Verified on-device:

   ```text
   ROCKNIX-SM8550.aarch64-20260527.tar: OK
   ```

3. Rebooted and let initramfs apply the update.

No Android, firmware, or bootloader partitions were intentionally touched. The update tar carries an `abl_signed-SM8550.elf` and `flash_abl.sh`, but the default ROCKNIX initramfs update path does not flash ABL without explicit opt-in. Final ABL checksums confirm no flashing occurred.

## Post-install device state

After update consumption and clean boot:

- LAN host: `192.168.1.239`
- Host hostname: `SM8550`
- Compatible strings:
  - `ayn,odin2portal`
  - `qcom,qcs8550`
  - `qcom,sm8550`
- Host `BUILD_ID`: `f080b462f54b5807bdd16ac7cc2ab64528b038b1`
- Host `OS_VERSION`: `20260527`
- Host `BUILD_DATE`: `Wed May 27 23:42:19 UTC 2026`
- Default target: `rocknix-main-space.target` (`active`)
- Host `systemctl is-system-running`: `running`
- Host failed units (immediately post-boot): `0`
- KERNEL md5 on `/flash`: `42386591bf1bda598f54693cda60a82f` (matches Gate 2 expected)
- SYSTEM md5 on `/flash`: `2fb7374a51673dc5976c29d808fba22c` (matches Gate 2 expected)
- `/storage/.update/`: empty (update consumed)
- `/storage` free: `36.5G`
- Battery: `75%` (post-install charge)
- `rocknix-guest.service`: `active running` (`Container running: Ready.`)
- `rocknix-guest-root-ensure.service`: `active`
- `rocknix-main-space.target`: `active`
- Guest NixOS toplevel: `/nix/store/vwv83jlv0cdqhfwsdgn4lbn4xaxiazh3-nixos-system-sobo-25.11pre-git`
- Substrate package state (`/usr/lib/rocknix-guest-substrate/`):
  - `guest-revision`: `a3fabfd8a35190cd23d027f4f8569bc11344a3d5`
  - `guest-build-target`: `.#nixosConfigurations.korri-rocknix-kiosk-odin2portal.config.system.build.toplevel`
  - `guest-rootfs-seed.manifest` matches the Odin2Portal payload facts above
- Active rootfs seeded marker (`/storage/nix-on-rock/rootfs/current/.rocknix-guest-rootfs-seed`) records the Odin2Portal seed revision, archive, and SHA256

Final ABL checksums remained unchanged from pre-install:

```text
59ef01bb919f800c9455aa7864d4178b  /dev/sde64
59ef01bb919f800c9455aa7864d4178b  /dev/sde65
```

## Lifecycle caveat — `/storage/.boot.hint=UPDATE`

`/storage/.boot.hint` remained `UPDATE` after a successful main-space boot. The hint is the legacy `003-upgrade` autostart trigger under `rocknix.target`, but Layer 14 main-space boot via `rocknix-main-space.target` does not invoke the legacy autostart chain that runs `/usr/share/post-update` and removes the hint.

This was the same residual condition observed at the start of Phase 4. It did not block the update from being applied, the device from booting cleanly, the guest from coming up, or ABL from staying unchanged.

**Resolved 2026-05-28:** `rocknix-post-update.service` now consumes the hint on `rocknix-main-space.target` boot while leaving recovery (`/flash/rocknix.no-nspawn` / `rocknix.safe=1`) and the legacy `003-upgrade` autostart entry unchanged. Device acceptance: `docs/acceptance/sm8550-post-update-boot-hint-sobo-2026-05-28.md`. Plan completed: `docs/plans/2026-05-27-002-fix-main-space-post-update-boot-hint-plan.md`.

## Validation commands

- `scripts/apply-rocknix-patches`: passed
- `scripts/verify-sm8550-contract`: passed
- `scripts/verify-sm8550-locks`: passed (`odin2portal a3fabfd8a35190cd23d027f4f8569bc11344a3d5`)
- `scripts/verify-product-payload`: passed (`simonwjackson/korri a3fabfd8a35190cd23d027f4f8569bc11344a3d5`)
- `scripts/verify-product-payload-fetches`: passed (source bytes `0dea10b5…`, seed bytes `bdfe9a73…`)
- `scripts/tests/product-payload-contract.sh`: passed
- `scripts/verify-sm8550-payloads --require-full-image work/rocknix/target` on Gate 2 artifact: passed
- `scripts/verify-image-fat-sector-size`: FAT label ROCKNIX, logical sector size 4096
- On-device `sha256sum -c ROCKNIX-SM8550.aarch64-20260527.tar.sha256`: OK

## Acceptance

`DeviceAccepted` for Nix-on-Rocks on sobo / AYN Odin2Portal (`ayn,odin2portal`) for the Phase 4 full-build release-path proof.

- `BuildProof`: full `build-sm8550.yml` run `26539625977` succeeded end-to-end (Docker → toolchain → base → image) with active product payload facts.
- `ArtifactVerified`: full update tar + full image artifact verified locally; SM8550 FAT geometry verified; manifest carries product payload facts.
- `DeviceAccepted`: update applied, KERNEL/SYSTEM md5 match Gate 2, ABL unchanged, host running, guest active, zero failed units, active rootfs and substrate facts match the Korri Odin2Portal payload.
- `HandsOnAcceptance`: NotRun/Deferred.
- `ReleasePublication`: NotPublished/Deferred.

Outstanding follow-up: `docs/plans/2026-05-27-002-fix-main-space-post-update-boot-hint-plan.md`.
