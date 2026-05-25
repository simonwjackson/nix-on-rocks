---
title: SM8550 boot fails with "logical sector size too small" because mkimage hardcodes -S 512 for qcom-abl
date: 2026-05-25
category: runtime-errors
module: sm8550-image-build
problem_type: runtime_error
component: tooling
severity: high
symptoms:
  - "Unable to find LABEL=ROCKNIX, powering off and on should correct it."
  - "FAT-fs (sda18): logical sector size too small for device (logical sector size = 512)"
  - "device boots to ROCKNIX boot animation then halts at busybox initramfs init"
  - "ABL successfully loads /KERNEL from the same partition that Linux refuses to mount"
  - "mount stderr silenced by busybox init masks the real FAT-fs rejection"
root_cause: config_error
resolution_type: code_fix
tags:
  - sm8550
  - qcom-abl
  - mkimage
  - vfat
  - 4k-lba
  - ufs
  - initramfs
  - rocknix
---

# SM8550 boot fails with "logical sector size too small" because mkimage hardcodes -S 512 for qcom-abl

## Problem

A freshly CI-built ROCKNIX image for the SM8550 handheld (Snapdragon 8 Gen 2, UFS, codename "Sobo") failed to boot after `fastboot flash ROCKNIX`. The on-screen busybox-initramfs error pointed at a missing filesystem label, but the real failure was the Linux FAT driver refusing to mount the boot filesystem because its logical sector size (512 B) was smaller than the underlying UFS device's logical sector size (4096 B).

The `qcom-abl` branch of `work/rocknix/scripts/mkimage` formats the boot FAT with `mkfs.vfat -S 512`, which is incompatible with UFS storage that reports 4 KiB logical sectors. ABL itself reads the FAT fine (it does raw reads via its own FS driver), so the image looks bootable up until Linux tries to mount `/dev/sda18` and bails.

## Symptoms

- On-screen, after `fastboot reboot` from a freshly installed image:

  ```
  Unable to find LABEL=ROCKNIX, powering off and on should correct it.
  ```

- After patching the initramfs `/init` to redirect `mount` stderr to `/dev/console`, the real kernel error appeared, repeated 15 times (once per second, matching the initramfs retry loop):

  ```
  FAT-fs (sda18): logical sector size too small for device (logical sector size = 512)
  ```

- ABL successfully loaded `/KERNEL` from the same partition — so the failure looked like "filesystem present, label missing", not "filesystem unmountable".
- On the host, `blkid -p` on the built artifact reported:

  ```
  BLOCK_SIZE="512"
  ```

- On the device, the underlying block geometry was:

  ```
  /sys/class/block/sda18/queue/logical_block_size  -> 4096
  /sys/class/block/sda18/queue/physical_block_size -> 4096
  ```

## What Didn't Work

1. **Chasing duplicate FS labels** (`ROCKNIX_INT`/`STORAGE_INT` from a previous `installtointernal` run vs. `ROCKNIX`/`STORAGE`) — the labels were fine; the FS never mounted, so the label was never even read by Linux.
2. **Ejecting the SD card to rule out a duplicate-label collision** — no change; the SD card was never the source.
3. **Investigating A/B slot routing** (`current-slot:a`) — the ROCKNIX partition is not A/B-slotted on this device, so slot selection cannot affect it.
4. **Suspecting AVB footer corruption** from the `fastboot` warning `Warning: skip copying ROCKNIX image avb footer due to sparse image` — ROCKNIX is not AVB-verified on this target; the warning is cosmetic.
5. **Blaming the FAT32 cluster-count warning** when test-shrinking to a 512 MiB raw image (`Number of clusters for 32 bit FAT is less than suggested minimum`) — that produced a different, unrelated ABL `Error booting Linux` panel and was a red herring for the real mount failure.
6. **RAM-booting via `fastboot boot` with `boot=/dev/disk/by-partlabel/ROCKNIX` and `boot=/dev/sda18`** — failed for two reasons unrelated to the root cause: (a) the bootimg's ramdisk slot is a 5-byte `dummy` placeholder so externally-supplied ramdisks were silently ignored, and (b) the rocknix initramfs has no mdev/udev so `/dev/disk/by-partlabel/*` symlinks never exist.
7. **Switching to `boot=/dev/sda18` once the partition was actually flashed** — initramfs found the node via sysfs but `mount` still failed; this finally exposed the sector-size mismatch once `mount` stderr was unsilenced, but only after the rest of the rabbit holes had been ruled out.

## Solution

Match the FAT logical sector size to the device's logical sector size on `qcom-abl` targets. UFS on SM8550 reports 4096-byte logical sectors, so the boot FAT must be formatted with `-S 4096`. Cluster size drops from `-s 32` (32 × 512 B = 16 KiB) to `-s 1` (1 × 4096 B = 4 KiB); a 768 MiB image yields ~196608 clusters, well above the FAT32 minimum of 65525.

`work/rocknix/scripts/mkimage` around line 136:

```diff
-if [ "${BOOTLOADER}" = "syslinux" -o "${BOOTLOADER}" = "bcm2835-bootloader" -o "${BOOTLOADER}" = "u-boot" -o "${BOOTLOADER}" = "arm-efi" -o "${BOOTLOADER}" = "qcom-abl" ]; then
-  mkfs.vfat -F 32 -S 512 -s 32 -i "${UUID_SYSTEM//-/}" -n "${DISTRO_BOOTLABEL}" "${IMG_TMP}/part1.fat" >"${SAVE_ERROR}" 2>&1 || show_error
-fi
+if [ "${BOOTLOADER}" = "syslinux" -o "${BOOTLOADER}" = "bcm2835-bootloader" -o "${BOOTLOADER}" = "u-boot" -o "${BOOTLOADER}" = "arm-efi" ]; then
+  mkfs.vfat -F 32 -S 512 -s 32 -i "${UUID_SYSTEM//-/}" -n "${DISTRO_BOOTLABEL}" "${IMG_TMP}/part1.fat" >"${SAVE_ERROR}" 2>&1 || show_error
+elif [ "${BOOTLOADER}" = "qcom-abl" ]; then
+  # qcom-abl targets (SM8550) sit on UFS with 4096-byte logical sectors.
+  # The Linux FAT driver refuses to mount when FS logical sector < device
+  # logical sector, so match the device geometry here.
+  mkfs.vfat -F 32 -S 4096 -s 1 -i "${UUID_SYSTEM//-/}" -n "${DISTRO_BOOTLABEL}" "${IMG_TMP}/part1.fat" >"${SAVE_ERROR}" 2>&1 || show_error
+fi
```

Package the change as `patches/rocknix/0009-mkimage-qcom-abl-4k-sector-fat.patch` and add it to `patches/rocknix/series`. The companion `installtointernal` script at `work/rocknix/projects/ROCKNIX/packages/rocknix/sources/scripts/installtointernal:162` already does the right thing (`-S 4096 -s 4`), confirming this is the intended geometry for qcom-abl on-device.

### Recovery procedure for already-bricked devices

Run inside `nix shell nixpkgs#android-tools nixpkgs#mtools nixpkgs#dosfstools nixpkgs#cpio nixpkgs#gzip`. **Only flash the `ROCKNIX` fastboot partition** — never touch `abl_*`, `xbl*`, `vbmeta*`, `uefi*`, `modem*`, `loader_*`, the partition table, or `super`.

```sh
# 1. Build a raw 768 MiB FAT with 4 KiB sectors and 4 KiB clusters.
truncate -s 768M ROCKNIX.img
mkfs.vfat -F 32 -S 4096 -s 1 -n ROCKNIX ROCKNIX.img
fatlabel ROCKNIX.img ROCKNIX   # defensive

# 2. Copy boot payload into the FAT image.
for f in KERNEL SYSTEM KERNEL.md5 SYSTEM.md5; do
  mcopy -o -i ROCKNIX.img "$f" "::$f"
done

# 3. Repack the KERNEL bootimg (cmdline kept verbatim from production).
mkbootimg --header_version 0 --pagesize 2048 --base 0x0 \
  --kernel_offset 0x10000000 --ramdisk_offset 0x10000000 --tags_offset 0x10000000 \
  --cmdline 'boot=LABEL=ROCKNIX disk=LABEL=STORAGE rootwait console=tty0 allow_mismatched_32bit_el0 fw_devlink.strict=1 pcie_ports=compat irqaffinity=0-2 systemd.unified_cgroup_hierarchy=1 systemd.legacy_systemd_cgroup_controller=0 nosoftlockup usbcore.interrupt_interval_override=045e:028e:2 nofsck rocknix.safe=1 systemd.unit=multi-user.target' \
  --kernel <Image> --ramdisk <ramdisk.cpio.gz> -o KERNEL

# 4. Flash and reboot.
fastboot flash ROCKNIX ROCKNIX.img
fastboot reboot

# 5. After SSH is up, fix the STORAGE label if a prior installtointernal mangled it.
e2label /dev/sda19 STORAGE
```

If the initramfs is silencing mount errors, drop in a patched `/init` (resolve `boot=PARTNAME=<gpt-partlabel>` via `/sys/class/block/*/uevent`, wait for the `/dev/sdaXX` node in devtmpfs, pass `-t vfat` explicitly, and redirect `mount` stderr to `/dev/console` rather than `/dev/null`). A working copy lived at `/tmp/sobo-rocknix-raw-fat/init-patched` during the recovery session that produced this learning.

## Why This Works

The Linux FAT driver (`fs/fat/inode.c`) requires that the filesystem's logical sector size be **greater than or equal to** the underlying block device's logical sector size. When the FS reports 512 B sectors but the device reports 4096 B sectors, the driver cannot perform sub-sector I/O against the device and refuses the mount with `logical sector size too small for device`.

`mkfs.vfat -S 4096` writes a BPB (BIOS Parameter Block) that declares 4096-byte logical sectors, so the FS geometry matches the UFS device geometry and the driver accepts the mount. ABL never hit this because it has its own FAT reader that does raw byte reads independent of Linux's block layer — which is exactly why the failure looked like "FS is fine, label is missing" instead of "FS is unmountable".

Cluster size `-s 1` (one 4096-byte sector per cluster = 4 KiB clusters) keeps the cluster count high enough to remain a valid FAT32 (the 65525-cluster minimum); on a 768 MiB image that yields ~196608 clusters.

## Prevention

### CI guard

Add to `scripts/static-checks.sh` (or a dedicated `scripts/verify-image-fat-sector-size`) a post-build check that fails fast when the boot FAT geometry doesn't match the target bootloader's storage geometry:

```sh
# Verify qcom-abl boot FAT uses 4 KiB logical sectors to match UFS geometry.
# Linux refuses to mount FAT when FS logical sector < device logical sector.
fat_block_size=$(blkid -p "${IMG_TMP}/part1.fat" \
  | grep -oE 'BLOCK_SIZE="[0-9]+"' \
  | grep -oE '[0-9]+')

if [ "${BOOTLOADER}" = "qcom-abl" ] && [ "${fat_block_size}" != "4096" ]; then
  echo "qcom-abl image FAT must have 4096-byte logical sectors; got ${fat_block_size}" >&2
  exit 1
fi
```

### Diagnostic recipe (run this FIRST next time)

```sh
# On the host that built the image:
blkid -p path/to/ROCKNIX-fat.img | grep BLOCK_SIZE

# On the device (over any working boot — recovery, fastbootd, prior good image):
cat /sys/class/block/sda18/queue/logical_block_size
cat /sys/class/block/sda18/queue/physical_block_size
```

If the FS `BLOCK_SIZE` is smaller than the device's `logical_block_size`, this is the bug — stop investigating labels, partitions, AVB, or A/B slots.

### Operational guardrail

Busybox initramfs hardcodes `Unable to find $1, powering off and on should correct it.` and routes the real kernel `mount` error to `>&${SILENT_OUT}` (see `work/rocknix/projects/ROCKNIX/packages/sysutils/busybox/scripts/init` `mount_common`). **Before** chasing labels, partition tables, slot routing, or AVB, always patch initramfs `/init` to redirect `mount` stderr to `/dev/console`. The kernel's actual error message is the shortest path to the root cause and is silenced by default.

## Related Issues

- [docs/ops/sm8550-full-install-safety-audit-2026-05-20.md](../../ops/sm8550-full-install-safety-audit-2026-05-20.md) — full-image safety audit; certified the same image on SD but did not exercise `fastboot flash ROCKNIX` against UFS, which is where the FAT logical-sector mismatch surfaces.
- [docs/thinking/2026-05-14-stage11-fastboot-recovery-boundary.md](../../thinking/2026-05-14-stage11-fastboot-recovery-boundary.md) — fastboot is the asserted recovery boundary; this learning is the latent gap the memo's "rehearse fastboot restore" task was meant to catch.
- [docs/solutions/developer-experience/custom-fork-update-sm8550-rocknix-2026-05-04.md](../developer-experience/custom-fork-update-sm8550-rocknix-2026-05-04.md) — `/storage/.update/*.tar` OTA path, unaffected by the bug; preferred install route until `mkimage` is patched.
- [docs/ops/sm8550-thor-bandai-install-runbook-2026-05-22.md](../../ops/sm8550-thor-bandai-install-runbook-2026-05-22.md) — working tar-based install runbook for SM8550; does not exercise the fastboot-flash path.
- [patches/rocknix/0008-sm8550-install-safety-boundary.patch](../../../patches/rocknix/0008-sm8550-install-safety-boundary.patch) — sibling install-safety patch; the same SM8550 install/update boundary the FAT sector-size fix and static-check guard extend.
- [docs/contracts/HOW-TO-FALL-BACK.md](../../contracts/HOW-TO-FALL-BACK.md) — on-device fallback doc; should note that `fastboot flash ROCKNIX <img>` requires the patched `mkimage` output (4 KiB logical sectors).
- [docs/plans/2026-05-14-001-fix-sm8550-first-boot-recovery-plan.md](../../plans/2026-05-14-001-fix-sm8550-first-boot-recovery-plan.md) — first-boot/guest-root-ensure plan whose logic never runs when FAT mount fails earlier; adjacent context for the busybox `init` mount-error visibility prevention rule.
