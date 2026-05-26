# Bandai backup mount/device reconnaissance

Host: `bandai` via `ssh -p 2222 root@bandai`  
Date: 2026-05-21  
Mode: read-only reconnaissance. No remote mounts, writes, or deletes were performed.

## Summary

Only one persistent writable filesystem is mounted in the guest: internal `STORAGE` on `/dev/sda19` (`ext4`, label `STORAGE`, UUID `2c01726b-8c35-40df-b4c4-dbdba7684302`). Several visible paths are bind/subdirectory mounts from that same partition. The external `GAMES` card is present as `/dev/mmcblk0p1` but is **not mounted** and was not scanned.

## Risk map

| Mount/path | Backing device/source | State | Backup implication |
| --- | --- | --- | --- |
| `/` | `/dev/sda19[/machines/rocknix-guest]`, ext4 label `STORAGE`, 923G mounted, 243G used | `rw,noatime` | Primary guest root. Back up for current system/config/data under the guest root. Physical partition is shared with the paths below. |
| `/storage` | resolved by `findmnt -T` to `/` on `/dev/sda19[/machines/rocknix-guest]` | writable through `/` | Not a separate filesystem by itself. It is part of the guest root unless a child mount is crossed. |
| `/storage/.guest` | `/dev/sda19[/.guest]` | `rw,noatime`, bind/subdir mount | Persistent data on the same physical `STORAGE` partition, but from a different source directory than `/`. Include if needed, but do not count it as a separate disk. Be careful with backup tools that cross bind mounts: this can duplicate or add same-partition data. |
| `/nix/store` | `/dev/sda19[/machines/rocknix-guest/nix/store]` | VFS `ro`, same ext4 source fs is `rw` | Same physical partition and same guest-root subtree as `/nix/store`. Do not back it up separately if backing up `/`; it is read-only at this mount. |
| `/tmp` | `tmpfs` | `rw` | Volatile; no persistent backup value. |
| `/run`, `/run/user/0`, `/run/wrappers`, `/run/keys` | `tmpfs`/`ramfs` | mostly `rw` | Volatile runtime state; exclude from backups. |
| `/dev` and device submounts | `tmpfs`/`devtmpfs` | `rw` | Device nodes only; exclude from backups. `/dev/mmcblk0` and `/dev/mmcblk0p1` are exposed device nodes, not mounted data paths. |
| `/proc`, `/sys`, cgroup/fuse/mqueue/hugetlbfs | virtual filesystems | mixed `rw`/`ro` | Kernel/runtime interfaces; exclude from backups. |
| `/run/host`, `/run/udev`, `/run/host/incoming` | `tmpfs` bind/subdir mounts | VFS `ro` | Runtime/host plumbing; not persistent user data from this guest view. |
| `/run/host/os-release` | `/dev/loop0[/etc/os-release]`, squashfs | `ro` | Read-only host image artifact; no backup action. |

## Same-storage callouts

- `/`, `/storage`, `/storage/.guest`, and `/nix/store` all report the same device id (`10303`) and are backed by `/dev/sda19`.
- `/` is the `machines/rocknix-guest` directory on `STORAGE`.
- `/storage/.guest` is the `/.guest` directory on the same `STORAGE` partition.
- `/nix/store` is a read-only mount of the same guest-root store directory already under `/machines/rocknix-guest/nix/store`.

## Mounted block devices

- `/dev/sda19`: `938.8G` partition, `ext4`, label `STORAGE`, UUID `2c01726b-8c35-40df-b4c4-dbdba7684302`, PARTLABEL `STORAGE`, PARTUUID `d317ab5f-4775-4f9a-8647-5fcdea01d41a`; mounted at `/`, `/storage/.guest`, and `/nix/store`.
- `/dev/zram0`: `6G` swap, UUID `7c559ce7-bebe-4e1c-8d1f-a90b948e3518`; not a backup target.

## Unmounted devices/partitions not scanned

These were identified by `lsblk` labels/UUIDs only. They were not mounted or scanned.

High backup/destructive-work concern:

- `/dev/mmcblk0p1`: `1.7T` `ext4`, label/PARTLABEL `GAMES`, UUID `fc1f2bfc-b6ea-42ca-8d6b-a1c8aac4f551`, PARTUUID `0c58672a-f78e-41cd-b20d-3bb9d34ce7a0`. External GAMES card appears present but unmounted; inspect/back up before any destructive work touching removable/external media.
- `/dev/sda18`: `2G` `vfat`, label/PARTLABEL `ROCKNIX`, UUID `D9CB-F2E8`, PARTUUID `205c4a75-a947-41f1-ad51-8f8e8b6b56db`. Boot/removable-style payload on internal disk; not mounted.
- `/dev/sda5`: `32M` `ext4`, PARTLABEL `persist`, UUID `5614fe98-1c16-4071-99af-b093e66faec8`. Device persist/calibration-style data; preserve before destructive partition work.
- `/dev/sda13`: `64M` `f2fs`, PARTLABEL `metadata`, UUID `a25b2da5-93be-4af9-983b-496a8160a351`. Not mounted.
- `/dev/sda17`: `1G`, PARTLABEL `userdata`, no filesystem reported. Treat as possible raw/encrypted/device data until proven otherwise.

Other unmounted partitions with recognized filesystems:

- `/dev/sde1` `320M` vfat `modem_a`, UUID `00BC-614E`; `/dev/sde2` `320M` vfat `modem_b`, UUID `00BC-614E`.
- `/dev/sde3` `6M` vfat `bluetooth_a`, UUID `00BC-614E`; `/dev/sde4` `6M` vfat `bluetooth_b`, UUID `00BC-614E`.
- `/dev/sde13` `64M` ext4 `dsp_a`, UUID `9601e943-f732-4178-a810-54016c9b834b`; `/dev/sde32` `64M` ext4 `dsp_b`, same UUID.
- `/dev/sde22` `537.1M` ext4 `vm-bootsys_a`, UUID `57f8f4bc-abf4-655f-bf67-946fc0f9f25b`; `/dev/sde60` `120M` ext4 `vm-persist`, same UUID.
- `/dev/sde57` `8M` vfat label `LOGFS`, UUID `D273-55EA`.
- `/dev/sde70` `30M` vfat `qmcs`, UUID `3D21-07B2`.

Many additional unmounted Qualcomm/Android firmware, boot, metadata, modem, and calibration partitions are present across `/dev/sda`, `/dev/sdb`, `/dev/sdc`, `/dev/sdd`, `/dev/sde`, and `/dev/sdf` with no filesystem reported by `lsblk`. They were not scanned. They are not ordinary mounted data paths, but destructive work against whole disks or partition tables should treat them as device-critical state.

## Commands used

- `findmnt -R -o TARGET,SOURCE,FSTYPE,OPTIONS,PROPAGATION`
- `findmnt -R -o TARGET,SOURCE,FSTYPE,SIZE,USED,AVAIL,USE%,VFS-OPTIONS,FS-OPTIONS --submounts /`
- `df -hT` and `df -aTh`
- `lsblk -e7 -o NAME,PATH,TYPE,SIZE,FSTYPE,LABEL,UUID,PARTLABEL,PARTUUID,MOUNTPOINTS,RO,RM,MODEL,SERIAL`
- `lsblk -P -e7 -o NAME,PATH,KNAME,TYPE,SIZE,FSTYPE,LABEL,UUID,PARTLABEL,PARTUUID,MOUNTPOINTS,RO,RM,MODEL,SERIAL`
- `findmnt -T` and `stat` for selected paths
