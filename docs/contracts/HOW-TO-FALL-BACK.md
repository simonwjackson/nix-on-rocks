# HOW TO FALL BACK

This file ships to `/flash/HOW-TO-FALL-BACK.md` on SM8550 images. It is
readable from a card reader on another machine without booting the device.

## What this image is

Default boot reaches `rocknix-main-space.target`, which starts
`rocknix-guest.service` as the NixOS main-space guest. The guest owns display,
audio, input, networking policy, Steam/Cemu launchers, and hardware-button
behavior.

ROCKNIX remains the recovery/update/container substrate. Recovery is explicit;
the host no longer automatically restarts the legacy UI if the guest crashes.

Identify the current boot mode:

```text
ssh root@<device> 'systemctl get-default; systemctl is-active rocknix-guest.service'
```

- `rocknix-main-space.target` + active guest → Nix main-space.
- `multi-user.target` or inactive guest after using a recovery toggle → host
  recovery.

## Offline guest rootfs seed

Fresh `/storage` needs a prebuilt guest rootfs seed before the NixOS guest can
start. The seed is not embedded in `/flash/SYSTEM`; it is too large for the
2GB system partition.

The host image ships a tiny manifest at:

```text
/usr/lib/rocknix-guest-substrate/guest-rootfs-seed.manifest
```

Copy the matching seed tarball to:

```text
/storage/nix-on-rock/images/seeds/<manifest seed_archive>.tar.zst
```

`rocknix-guest-root-ensure` verifies the staged seed SHA256, checks the device
compatible string, and extracts it into `/storage/nix-on-rock/rootfs/current`
only when the guest root is missing or empty.

Device seeds are not interchangeable:

- Odin2Portal / sobo → compatible `ayn,odin2portal`.
- Thor / bandai → compatible `ayn,thor`.

A missing, corrupt, or wrong-device seed fails closed: host recovery remains
available, but `rocknix-guest.service` will not start.

## Symptoms of a guest failure

- Black screen for more than 30 seconds after boot.
- Display shows the boot splash and never advances.
- Host SSH works, but `rocknix-guest.service` or
  `rocknix-guest-root-ensure.service` fails.

If host SSH still works, use the SSH recovery path first. If SSH is unavailable,
use the card-reader flag path.

## Recovery with SSH

```text
ssh root@<device>
touch /flash/rocknix.no-nspawn
reboot
```

The next boot routes to host recovery instead of Nix main-space.

## Recovery with card reader

1. Power off the device.
2. Mount the `/flash` partition on another machine.
3. Create the flag file:

   ```text
   touch /path/to/flash/rocknix.no-nspawn
   ```

4. Eject/reinstall the card or storage device.
5. Power on. Boot routes to host recovery.

The flag file is sticky and persists across reboots until removed.

## Recovery with one-boot cmdline

If the bootloader exposes a way to add kernel arguments, boot once with:

```text
rocknix.safe=1
```

That routes this boot to host recovery. The override clears on the next normal
reboot.

## Confirming recovery mode

```text
systemctl get-default                         # multi-user.target
systemctl is-active rocknix-guest.service     # inactive or not started
systemctl status rocknix-recovery-toggle      # shows which recovery trigger won
```

## Exiting recovery mode

```text
rm /flash/rocknix.no-nspawn
reboot
```

If you used `rocknix.safe=1`, exiting is automatic: reboot without that cmdline
argument.

## Explicit clean reseed

Normal updates do not overwrite an existing valid guest root. To force a clean
reseed from a staged seed, stop the guest and create the explicit reseed flag:

```text
systemctl stop rocknix-guest.service
touch /flash/rocknix.reseed-guest
reboot
```

On success, the old root is retained as
`/storage/nix-on-rock/rootfs/previous` and `/flash/rocknix.reseed-guest` is
cleared.

## Guest update/promotion logs

Image updates install packaged guest source under
`/usr/lib/rocknix-guest-substrate/guest`. `rocknix-guest-promote.service`
applies that source to the persistent guest rootfs at boot when revisions
differ.

Useful checks:

```text
cat /usr/lib/rocknix-guest-substrate/guest-revision
cat /usr/lib/rocknix-guest-substrate/guest-rootfs-seed.manifest
ls -lh /storage/nix-on-rock/images/seeds/
cat /storage/nix-on-rock/rootfs/current/etc/rocknix-guest-revision
cat /storage/nix-on-rock/rootfs/current/etc/rocknix-guest-root-seed-complete
journalctl -b -u rocknix-guest-root-ensure.service --no-pager
journalctl -b -u rocknix-guest-promote.service --no-pager
journalctl -b -u rocknix-guest.service --no-pager
```

## Legacy layout compatibility

For the migration window, the host migrates valid legacy paths from
`/storage/machines/rocknix-guest` and `/storage/.guest` into
`/storage/nix-on-rock` before first boot. The guest may still see the
host/guest exchange as `/storage/.guest`, but host-owned persistent state now
lives under `/storage/nix-on-rock`.

## Re-flashing

If recovery does not get you back to a working device, use the standard ROCKNIX
reflash/update flow. `/storage` holds ROMs, saves, configs, the staged seed, and
the persistent guest rootfs; a normal image update does not intentionally wipe
it. A hard factory reset reformats or deletes `/storage`, so the seed must be
copied again afterward.
