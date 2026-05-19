# Layer 14 soak checklist

The soak validates the current SM8550 Nix main-space path: ROCKNIX boots the
NixOS guest by default, the guest owns product UX, and ROCKNIX remains reachable
as the recovery/update substrate.

Read this checklist alongside:

- `/var/log/rocknix-guest-soak.log`
- `/var/log/rocknix-guest-soak-summary.log`
- `journalctl -b -u rocknix-guest.service`
- `journalctl -b -u rocknix-guest-promote.service`

## Pre-soak setup

- [ ] Device booted from the latest SM8550 image.
- [ ] Host default target is `rocknix-main-space.target`.
- [ ] Host SSH on `root@thor:22` is responsive.
- [ ] `/storage/nix-on-rock/rootfs/current/` exists.
- [ ] `/storage/nix-on-rock/staging/guest-exchange/` exists and is writable (guest-visible as `/storage/.guest` during the compatibility window).
- [ ] `/usr/lib/rocknix-guest-substrate/guest-revision` exists.
- [ ] Packaged guest source static checks pass:

  ```text
  /usr/lib/rocknix-guest-substrate/guest/scripts/static-checks.sh
  ```

- [ ] Guest promotion marker is current or promotion has completed:

  ```text
  cat /usr/lib/rocknix-guest-substrate/guest-revision
  cat /storage/nix-on-rock/rootfs/current/etc/rocknix-guest-revision
  cat /storage/nix-on-rock/rootfs/current/etc/rocknix-guest-system-path
  ```

## Start the run

```text
systemctl start rocknix-guest.service
systemctl start rocknix-guest-promote.service
sleep 10
rocknix-guest-soak --hours 24 \
  > /var/log/rocknix-guest-soak-stdout.log 2>&1 &
disown
```

For a faster iteration pass:

```text
rocknix-guest-soak --hours 4 --interval-seconds 600
```

## During the run

- [ ] First sample line shows `guest outer=N inner=M` with both values non-zero.
- [ ] First sample logs no `ALARM:` lines.
- [ ] `rocknix-sway-kiosk.service` is active inside the guest.
- [ ] `rocknix-hardware-button-handler.service` is active inside the guest.
- [ ] `rocknix-pipewire.service`, `rocknix-wireplumber.service`, and
      `rocknix-pipewire-pulse.service` are active inside the guest.
- [ ] Host SSH remains responsive while guest services are active.

## Pass criteria

- [ ] Sample 1: zero alarms.
- [ ] Midpoint sample: zero alarms.
- [ ] Final sample: zero alarms.
- [ ] Final summary line reports all samples passed with `alarms=0`.
- [ ] No failed units in the host or guest:

  ```text
  systemctl --failed
  # inside guest namespace:
  systemctl --failed
  ```

## Common alarms and their meaning

| Alarm | What it tells you |
|------|------------------|
| `resolv.conf ownership marker missing` | `rocknix-guest-prep` did not run or the guest rootfs marker was deleted. |
| `guest /etc/resolv.conf clobbered by host resolvconf` | The unit accidentally leaked host DNS state or the guest network module regressed. |
| `guest /run/current-system not seeded` | The guest system profile or prep helper did not seed the current generation correctly. |
| `guest PATH contains raw /usr/bin or /usr/sbin` | Host `/usr` leaked into the guest. Re-check the nspawn bind list. |
| `no sway process anywhere on system` | Guest compositor failed or never started. Check guest journal. |
| `no pipewire process` | Guest audio stack failed. Check `modules/audio.nix` and guest journal. |
| `host SSH on :22 not responsive to BatchMode probe` | Host substrate is no longer reachable; stop and investigate before continuing. |
| `MemAvailable dropped by N kB > budget` | Possible memory leak; capture `/proc/meminfo` and process snapshots. |

## Post-soak

- [ ] Archive `/var/log/rocknix-guest-soak*.log` to
      `/storage/rocknix-guest-soak-runs/YYYY-MM-DD-NNN/`.
- [ ] Record the image commit, guest revision, and system path:

  ```text
  cat /usr/lib/rocknix-guest-substrate/guest-revision
  cat /storage/nix-on-rock/rootfs/current/etc/rocknix-guest-revision
  cat /storage/nix-on-rock/rootfs/current/etc/rocknix-guest-system-path
  ```

- [ ] Note `PASS` or `FAIL` in the operator journal.

## Sign-off

```text
Soak completed: ____-__-__   Hours run: ____   Alarms: ____
Operator: ____               Outcome: PASS / FAIL
```
