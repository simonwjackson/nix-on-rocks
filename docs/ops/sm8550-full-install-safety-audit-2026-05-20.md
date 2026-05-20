# SM8550 full-install safety audit

Date: 2026-05-20
Device audited: `sobo` / Odin2Portal (`ayn,odin2portal`)
Artifact audited: `ROCKNIX-SM8550.aarch64-20260520.img.gz` from image-only run `26152901081`

## Scope

This is a read-only audit for whether a full install can be validated without touching Android, firmware, or bootloader-sensitive partitions.

No destructive device writes were performed during this audit.

## Local image audit

The accepted image was decompressed to a local regular file for partition inspection only.

- Compressed image SHA256: `5520db591ad1bef18d29d65cf07ca569e341c3ef59e7fed2f6e2deba8322a5c9`
- Uncompressed size: `2,198,863,872` bytes
- Partition table: MBR/DOS

Partition layout:

| Partition | Start sector | Sectors | Size | Type | Filesystem | Purpose |
| --- | ---: | ---: | ---: | --- | --- | --- |
| 1 | 32768 | 4194304 | 2 GiB | W95 FAT32 LBA | FAT32, label `ROCKNIX` | boot/update payload partition |
| 2 | 4227072 | 65536 | 32 MiB | Linux | ext4 | small storage seed partition in removable image |

FAT partition contents:

- `KERNEL`
- `SYSTEM`
- `KERNEL.md5`
- `SYSTEM.md5`
- `rocknix_abl/`

The raw full image itself does not contain Android GPT partition names such as `abl_a`, `xbl_a`, `boot_a`, `vendor_boot_a`, `super`, `metadata`, or `userdata`. It is a removable-style two-partition image, not an Android/UFS repartition image.

## Live `sobo` partition map

Read-only live audit showed:

- `/flash` mounted from `/dev/sda18`, partition label `ROCKNIX`, vfat, read-only
- `/storage` mounted from `/dev/sda19`, partition label `STORAGE`, ext4, read-write

Relevant internal UFS partitions:

| Device | Partlabel | Mounted as | Notes |
| --- | --- | --- | --- |
| `/dev/sda18` | `ROCKNIX` | `/flash` | accepted safe update/install target |
| `/dev/sda19` | `STORAGE` | `/storage` | accepted storage target only with explicit approval |
| `/dev/sda17` | `userdata` | not mounted by ROCKNIX | Android userdata; install-to-internal script shrinks/recreates this during first internal install |
| `/dev/sde64` / `/dev/sde65` | `abl_a` / `abl_b` | not mounted | bootloader-sensitive; must not be touched by Nix-on-Rocks normal install/update |
| `/dev/sdb1` / `/dev/sdc1` | `xbl_a` / `xbl_b` | not mounted | bootloader-sensitive |
| `/dev/sde66` / `/dev/sde67` | `boot_a` / `boot_b` | not mounted | Android boot-sensitive |
| `/dev/sda14` | `super` | not mounted | Android dynamic partitions |
| `/dev/sda13` | `metadata` | not mounted | Android metadata |

Caveat: a removable card with duplicate filesystem labels `ROCKNIX` and `STORAGE` was visible as `/dev/mmcblk0p1` and `/dev/mmcblk0p2`; the live mounts still resolved to internal `/dev/sda18` and `/dev/sda19`. Any future full-install procedure should avoid relying on ambiguous `/dev/disk/by-label` symlinks when duplicate labels exist.

## Script audit

Product repo scripts outside the generated ROCKNIX work tree had no direct destructive write commands (`fastboot flash`, `dd of=`, `parted mkpart/rm`, `mkfs`, `wipefs`, `blkdiscard`).

Relevant ROCKNIX substrate scripts:

- `scripts/mkimage` creates the local image file only; it does not touch device block devices.
- `projects/ROCKNIX/packages/rocknix/sources/scripts/installtointernal` is destructive by design for first internal install:
  - refuses to run if `ROCKNIX` or `STORAGE` partitions already exist;
  - prompts before proceeding;
  - finds Android `userdata` on `/dev/sda`;
  - removes/recreates `userdata` smaller;
  - creates/formats `ROCKNIX` and `STORAGE` after `userdata`;
  - does not reference `abl_*`, `xbl_*`, `boot_*`, `vendor_boot_*`, `super`, or other bootloader/firmware partitions.

On current `sobo`, because `ROCKNIX` and `STORAGE` already exist, `installtointernal` would exit before destructive operations.

## Finding: automatic ABL update risk

The audit found that upstream SM8550 `bootloader/update.sh` unconditionally sourced `updateabl`, and `updateabl` can write `/dev/disk/by-partlabel/abl_a` and `abl_b` when the packaged ABL differs.

That violates the Nix-on-Rocks safety boundary for normal install/update work: bootloader partitions are sensitive and require separate explicit approval.

Mitigation added in the patch queue:

- `0008-sm8550-install-safety-boundary.patch`
- SM8550 `bootloader/update.sh` now skips ABL updates by default.
- ABL writes require explicit `ROCKNIX_ALLOW_ABL_UPDATE=yes` in the update environment.
- Static checks now assert the default skip and safety-boundary message.

## Current answer

After the mitigation patch, the normal Nix-on-Rocks update path can be validated against the safe partition boundary: `ROCKNIX` is the default write target, and `STORAGE` remains explicit-approval-only for destructive fresh-storage proof.

A true first internal install is still destructive to Android `userdata` by design. It does not target bootloader/firmware partitions, but it should remain an explicit-approval operation because it repartitions and formats persistent storage.

## Follow-up CI validation

After adding `0008-sm8550-install-safety-boundary.patch`, the safety-gated build path was proven in CI:

- Preflight: `https://github.com/simonwjackson/nix-on-rocks/actions/runs/26182086143`
- Prepare base artifacts: `https://github.com/simonwjackson/nix-on-rocks/actions/runs/26182181755`
- Image-only: `https://github.com/simonwjackson/nix-on-rocks/actions/runs/26186760445`
- Product SHA: `c5733ef07bfe47443c8dba492cc16919ab2100c9`
- Patch-series hash: `5c96f3efef510ad1599191fa121c45ce80453968f862f7cf3cd0c76402aa8547`

New artifact verification:

- Artifact: `nix-on-rocks-sm8550-image-only-26186760445`
- Update tar: `ROCKNIX-SM8550.aarch64-20260520.tar`
- Update tar SHA256: `b811052046f49435165a445715e3059a6b5974fd64bff98c1bcc68d206449ce8`
- Image SHA256: `9d17a48b41b39afa787eb0d5a668cf2ce8fb4041b8f03fbb9403626f1118759a`
- `scripts/verify-sm8550-payloads`: passed
- `sha256sum -c *.sha256`: passed
- Extracted `SYSTEM` contains `/usr/share/bootloader/update.sh` with the `ROCKNIX_ALLOW_ABL_UPDATE:-no` guard and safety-boundary message.

## Non-destructive device proof

The safety-gated update artifact from image-only run `26186760445` was installed on `sobo` through the standard `/storage/.update` path.

On-device install steps:

1. Copied `ROCKNIX-SM8550.aarch64-20260520.tar` and `.sha256` to `/storage/.update/`.
2. Verified `sha256sum -c ROCKNIX-SM8550.aarch64-20260520.tar.sha256` on-device.
3. Rebooted and let initramfs apply the update.

Pre-update ABL checksums:

```text
91037267a0578fee2e43ca2a8f109120ce055829edcd860cd117645563bdead6  /dev/disk/by-partlabel/abl_a
91037267a0578fee2e43ca2a8f109120ce055829edcd860cd117645563bdead6  /dev/disk/by-partlabel/abl_b
```

Post-update ABL checksums:

```text
91037267a0578fee2e43ca2a8f109120ce055829edcd860cd117645563bdead6  /dev/disk/by-partlabel/abl_a
91037267a0578fee2e43ca2a8f109120ce055829edcd860cd117645563bdead6  /dev/disk/by-partlabel/abl_b
```

Post-reboot evidence:

- Host system state: `running`
- Host failed units: `0`
- `rocknix-guest.service`: `active`
- `rocknix-guest-promote.service`: `inactive`
- `/storage/.update`: empty after update consumption
- Installed `/usr/share/bootloader/update.sh` contains `ROCKNIX_ALLOW_ABL_UPDATE:-no`.
- Installed `/usr/share/bootloader/update.sh` contains the safety-boundary message: `bootloader partitions are outside the Nix-on-Rocks install/update boundary`.
- Current rootfs revision: `d5d00fe4b58822da8ab0a0c21ea4306a92c65c2a`
- Stored seed SHA256: `650dafebc88abdc3581cb67dd05d825b54dc8807930898713b8086f5dda21a1f`
- `rocknix-guest-activation-audit --quiet`: passed
- `rocknix-guest-soak --hours 0 --interval-seconds 5`: passed with zero alarms
- Brightness: `410 / 4096`

Result: the safety-gated normal update path was accepted on-device and did not modify `abl_a` or `abl_b`.

## Fresh guest-root proof

Phase B validated fresh guest root creation without repartitioning or formatting `STORAGE`.

Procedure:

1. Stopped `rocknix-guest.service` and `rocknix-guest-promote.service`.
2. Moved `/storage/nix-on-rock/rootfs/current` and `/storage/nix-on-rock/rootfs/previous` aside under a timestamped backup directory, leaving `/storage/nix-on-rock/images/seeds/` intact.
3. Verified the staged Odin2Portal seed archive still matched SHA256 `650dafebc88abdc3581cb67dd05d825b54dc8807930898713b8086f5dda21a1f`.
4. Ran `/usr/bin/rocknix-guest-root-ensure` to recreate `/storage/nix-on-rock/rootfs/current` from the packaged/staged seed.
5. Started `rocknix-guest.service`.
6. Removed the temporary backup roots after the new root was accepted; immutable `/var/empty` directories required `chattr -R -i` before cleanup.

Result from `rocknix-guest-root-ensure`:

```text
rocknix-guest-root-ensure: guest root missing; seeding
rocknix-guest-root-ensure: seeding guest root from /storage/nix-on-rock/images/seeds/rocknix-guest-rootfs-odin2portal-d5d00fe4b588.tar.zst to /storage/nix-on-rock/rootfs/current.tmp.*
rocknix-guest-root-ensure: synthesized missing guest selected profile from init link: /nix/var/nix/profiles/per-user/root/rocknix-guest-system -> /nix/store/yf0b220kzayi9wbl4r1mvk9k7vdz34p8-nixos-system-sobo-25.11.20260505.0c88e1f
rocknix-guest-root-ensure: seeded guest root is valid: /storage/nix-on-rock/rootfs/current
```

Fresh seed completion marker:

```text
seeded_at=2026-05-20T20:59:33Z
seed_revision=d5d00fe4b58822da8ab0a0c21ea4306a92c65c2a
seed_device=odin2portal
seed_compatible=ayn,odin2portal
seed_sha256=650dafebc88abdc3581cb67dd05d825b54dc8807930898713b8086f5dda21a1f
seed_size=2776874918
seed_archive=rocknix-guest-rootfs-odin2portal-d5d00fe4b588.tar.zst
```

Post-proof evidence:

- Host system state: `running`
- Host failed units: `0`
- `rocknix-guest.service`: `active`
- `rocknix-guest-promote.service`: `inactive`
- `rocknix-guest-activation-audit --quiet`: passed
- `rocknix-guest-soak --hours 0 --interval-seconds 5`: passed with zero alarms
- `/storage` after cleanup: `80.6G` available

Operational note: in the same boot, manually moving the guest root after `rocknix-guest-root-ensure.service` has already completed does not cause systemd to rerun that oneshot dependency. Manual same-boot root removal should run `/usr/bin/rocknix-guest-root-ensure` explicitly before starting `rocknix-guest.service`. A true fresh boot with a missing root runs the oneshot normally.

## Install-path guarded rehearsal

Phase C validated the internal install guard on the already-installed `sobo` device.

Preflight confirmed existing internal install partitions:

```text
blkid -t PARTLABEL=ROCKNIX -o device  -> /dev/sda18
blkid -t PARTLABEL=STORAGE -o device  -> /dev/sda19
```

Guarded rehearsal command:

```sh
HW_DEVICE=SM8550 timeout 30s installtointernal </dev/null
```

Result:

```text
An installation already exists (found partition named 'ROCKNIX'). Exiting.
```

Post-rehearsal state:

- Host system state after resetting unrelated stats failure: `running`
- Host failed units: `0`
- `rocknix-guest.service`: `active`

Result: on an already-installed Odin2Portal, `installtointernal` exits before the prompt and before any destructive partitioning or formatting operations.

## Full removable-image write proof

Phase D validated that the accepted full `.img.gz` can be written to a sacrificial removable SD target without touching internal UFS or bootloader/firmware partitions.

Approved target: `/dev/mmcblk0`

Target confirmation before write:

```text
/sys/block/mmcblk0/device/type=SD
/sys/block/mmcblk0/device/name=SD32G
/sys/block/mmcblk0/ro=0
mount | grep mmcblk0 -> no mounts
live /flash -> /dev/sda18
live /storage -> /dev/sda19
```

Write command shape:

```sh
gzip -dc ROCKNIX-SM8550.aarch64-20260520.img.gz | dd of=/dev/mmcblk0 bs=4M conv=fsync
```

Written bytes:

```text
2198863872 bytes (2.0GB) copied
```

Post-write partition identity:

```text
/dev/mmcblk0: PTUUID="9e37f1cb" PTTYPE="dos"
/dev/mmcblk0p1: LABEL="ROCKNIX" TYPE="vfat" PARTUUID="9e37f1cb-01"
/dev/mmcblk0p2: LABEL="STORAGE" TYPE="ext4" PARTUUID="9e37f1cb-02"
```

Exact image-length verification:

```text
local uncompressed image SHA256: 79d0186cfc7501e0d975a849516f7a46133233f420407d8c7c88fa467d75b57f
/dev/mmcblk0 first 4294656 sectors: 79d0186cfc7501e0d975a849516f7a46133233f420407d8c7c88fa467d75b57f
```

Filesystem verification:

```text
fsck.fat -n /dev/mmcblk0p1: clean enough for read-only check; 11 files
 e2fsck -fn /dev/mmcblk0p2: completed all passes
```

Explicit read-only mounts of `/dev/mmcblk0p1` and `/dev/mmcblk0p2` showed:

- `KERNEL`
- `SYSTEM`
- `KERNEL.md5`
- `SYSTEM.md5`
- `rocknix_abl/`

Direct MD5 verification matched the shipped sidecars after accounting for sidecar paths being `target/KERNEL` and `target/SYSTEM`:

```text
a1ff83877e19fefc68a87da0e489ce1f  KERNEL
c55eda5a1d80a6126f6b598197dffd8d  SYSTEM
```

Internal safety after the removable write:

- Live `/flash` remained `/dev/sda18`.
- Live `/storage` remained `/dev/sda19`.
- Host system state: `running`
- Host failed units: `0`
- `rocknix-guest.service`: `active`
- `rocknix-guest-activation-audit --quiet`: passed
- `abl_a` and `abl_b` checksums remained unchanged at `91037267a0578fee2e43ca2a8f109120ce055829edcd860cd117645563bdead6`.

Result: the full removable image can be laid down and verified on a sacrificial SD target without compromising internal Android, storage, ABL, or other sensitive UFS partitions.

## Reboot with written SD inserted

After writing the removable image, `sobo` was rebooted with `/dev/mmcblk0` still present and carrying duplicate `ROCKNIX`/`STORAGE` filesystem labels.

Pre-reboot labels:

```text
/dev/sda18: LABEL="ROCKNIX" PARTLABEL="ROCKNIX"
/dev/sda19: LABEL="STORAGE" PARTLABEL="STORAGE"
/dev/mmcblk0p1: LABEL="ROCKNIX"
/dev/mmcblk0p2: LABEL="STORAGE"
```

Post-reboot mount resolution:

```text
/dev/sda18 on /flash type vfat
/dev/sda19 on /storage type ext4
```

Post-reboot evidence:

- Host system state: `running`
- Host failed units: `0`
- `rocknix-guest.service`: `active`
- `rocknix-guest-activation-audit --quiet`: passed
- `rocknix-guest-soak --hours 0 --interval-seconds 5`: passed with zero alarms
- `abl_a` and `abl_b` checksums remained unchanged at `91037267a0578fee2e43ca2a8f109120ce055829edcd860cd117645563bdead6`.

Result: with current boot ordering on `sobo`, rebooting with the written SD inserted still selected the internal ROCKNIX/STORAGE partitions. The duplicate-label situation remains undesirable for deterministic operator procedures, but it did not cause a mixed or SD boot in this test.

## Remaining validation gates

Before any further destructive proof:

1. Internal first-install repartitioning with `installtointernal` still requires booting from external media so the target internal `/dev/sda` partitions are not the running `/flash` and `/storage`.
2. Keep ABL/bootloader flashing out of scope unless separately approved with `ROCKNIX_ALLOW_ABL_UPDATE=yes` and a dedicated recovery plan.
