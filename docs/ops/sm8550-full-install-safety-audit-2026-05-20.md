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

## Remaining validation gates

Before any destructive proof:

1. Only with explicit approval, test first-install behavior against a sacrificial target or by allowing `installtointernal` to repartition `userdata`/`ROCKNIX`/`STORAGE`.
2. Keep ABL/bootloader flashing out of scope unless separately approved with `ROCKNIX_ALLOW_ABL_UPDATE=yes` and a dedicated recovery plan.
