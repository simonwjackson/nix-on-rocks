# SM8550 Thor / bandai install runbook

Date: 2026-05-22
Device: `bandai` / AYN Thor (`ayn,thor`)
Plan: `docs/plans/2026-05-21-001-feat-sm8550-thor-device-acceptance-plan.md`

This runbook covers the narrow Phase 5–style acceptance: install the
Thor-pinned update tar through `/storage/.update/` and capture
`DeviceAccepted` evidence.

## Pre-flight on bandai

Before staging the update tar, capture the current state for the acceptance
record:

```sh
ssh root@bandai '
  echo "--- compatible ---"
  tr "\000" "\n" </proc/device-tree/compatible | sed "/^$/d"

  echo "--- /etc/os-release BUILD_ID ---"
  grep "^BUILD_ID=" /etc/os-release

  echo "--- mounts ---"
  mount | grep -E "/flash|/storage"

  echo "--- guest substrate state ---"
  systemctl get-default
  systemctl is-active rocknix-guest.service
  systemctl is-active rocknix-guest-promote.service
  ls /storage/nix-on-rock 2>/dev/null && cat /storage/nix-on-rock/rootfs/current/etc/rocknix-guest-revision 2>/dev/null
  cat /storage/nix-on-rock/rootfs/current/etc/rocknix-guest-root-seed-complete 2>/dev/null

  echo "--- existing seed directory ---"
  ls -lh /storage/nix-on-rock/images/seeds/ 2>/dev/null

  echo "--- failed units ---"
  systemctl --failed --no-legend

  echo "--- abl checksums (pre-install) ---"
  sha256sum /dev/disk/by-partlabel/abl_a /dev/disk/by-partlabel/abl_b 2>/dev/null
'
```

The expected `compatible` first entry on bandai is `ayn,thor`. If anything
other than `ayn,thor` appears first, stop — we may be on the wrong device.

## Stage the Thor seed if needed

The Phase 5 host package only ships the seed manifest, not the seed bytes
(the seed is too large for `SYSTEM`). The update tar carries the seed under
`target/seed/`, and `scripts/image` on the device's initramfs stages it under
`/storage/nix-on-rock/images/seeds/` before `rocknix-guest-root-ensure`
runs.

If `/storage/nix-on-rock/images/seeds/` already contains the Thor seed
`rocknix-guest-rootfs-thor-d5d00fe4b588.tar.zst` and its SHA256 matches
`<TBD_after_CI>` then nothing further is needed before the update reboot.

If the seed is missing or has the wrong SHA256, the install reboot will fail
closed at `rocknix-guest-root-ensure`. Manual recovery path:

```sh
# from a host that has the artifact (the same one that ran the local payload
# verification step described below):
scp rocknix-guest-rootfs-thor-d5d00fe4b588.tar.zst \
    root@bandai:/storage/nix-on-rock/images/seeds/

ssh root@bandai '
  sha256sum /storage/nix-on-rock/images/seeds/rocknix-guest-rootfs-thor-d5d00fe4b588.tar.zst
'
```

## Local artifact verification (before any device write)

After the image-only workflow run completes, download the artifact bundle and
run:

```sh
cd <artifact-extract-dir>
scripts/verify-sm8550-payloads work/rocknix/target
sha256sum -c *.sha256
# spot-check seed contents of the update tar:
tar tf ROCKNIX-SM8550.aarch64-<date>.tar | grep target/seed/
```

Both checks must pass before touching `bandai`. Expected payload entries:

- `target/SYSTEM`
- `target/KERNEL`
- `target/seed/rocknix-guest-rootfs-thor-d5d00fe4b588.tar.zst`

## Install through `/storage/.update/`

This is the normal ROCKNIX update path. Do not touch Android, firmware, or
bootloader partitions.

```sh
scp ROCKNIX-SM8550.aarch64-<date>.tar \
    ROCKNIX-SM8550.aarch64-<date>.tar.sha256 \
    root@bandai:/storage/.update/

ssh root@bandai '
  cd /storage/.update/
  sha256sum -c ROCKNIX-SM8550.aarch64-<date>.tar.sha256
  ls -lh
'

ssh root@bandai reboot
```

The device reboots, initramfs applies the update, the seed is staged, and the
guest starts.

## Post-reboot evidence

Wait ~60 seconds after the reboot, then collect:

```sh
ssh root@bandai '
  echo "--- hostname / BUILD_ID / compatible ---"
  hostname
  grep "^BUILD_ID=" /etc/os-release
  tr "\000" "\n" </proc/device-tree/compatible | sed "/^$/d" | head -1

  echo "--- system state ---"
  systemctl is-system-running
  systemctl --failed --no-legend

  echo "--- guest services ---"
  systemctl is-active rocknix-guest.service
  systemctl is-active rocknix-guest-promote.service
  systemctl is-active rocknix-guest-root-ensure.service

  echo "--- update consumed ---"
  ls /storage/.update/

  echo "--- guest substrate state ---"
  cat /usr/lib/rocknix-guest-substrate/guest-revision
  cat /usr/lib/rocknix-guest-substrate/guest-rootfs-seed.manifest
  cat /storage/nix-on-rock/rootfs/current/etc/rocknix-guest-revision
  cat /storage/nix-on-rock/rootfs/current/etc/rocknix-guest-root-seed-complete

  echo "--- audit ---"
  rocknix-guest-activation-audit --quiet && echo "audit passed" || echo "audit FAILED"

  echo "--- abl checksums (post-install) ---"
  sha256sum /dev/disk/by-partlabel/abl_a /dev/disk/by-partlabel/abl_b 2>/dev/null
'
```

Expected:

- `hostname` is `bandai` (Thor profile sets `networking.hostName = "bandai"`).
- `BUILD_ID` matches the SHA of `nix-on-rocks` that produced the image.
- `compatible` first entry is `ayn,thor`.
- `systemctl is-system-running` is `running`.
- `rocknix-guest.service` is `active`.
- `rocknix-guest-promote.service` is `inactive`.
- `/storage/nix-on-rock/rootfs/current/etc/rocknix-guest-revision` is
  `d5d00fe4b58822da8ab0a0c21ea4306a92c65c2a` (same rev as sobo).
- The seed manifest contains `seed_compatible=ayn,thor` and the matching SHA.
- `rocknix-guest-activation-audit --quiet` passes.
- `abl_a` and `abl_b` checksums are unchanged from the pre-install capture
  (safety-gated update boundary).

## Runtime smoke

```sh
ssh root@bandai '
  ROCKNIX_GUEST_LIVE_SMOKE=1 \
    /usr/lib/rocknix-guest-substrate/tests/guest-substrate-runtime-smoke.sh
'
```

Expected: passed.

## Soak

```sh
ssh root@bandai '
  ROCKNIX_REQUIRE_HOST_ESSWAY=no \
    rocknix-guest-soak --hours 1 --interval-seconds 1
'
```

Expected: `soak passed: <N> samples, zero alarms`.

## Cold reboot

```sh
ssh root@bandai reboot
# wait, then re-collect minimal evidence:
sleep 90
ssh root@bandai '
  hostname
  systemctl is-system-running
  systemctl is-active rocknix-guest.service
  systemctl --failed --no-legend
'
```

## Recording acceptance

Once all checks pass, paste the captured output into
`docs/acceptance/sm8550-device-acceptance-2026-05-22-thor.md` following the
2026-05-19 / -20 sobo doc layout, scoped explicitly to `ayn,thor` / bandai.
Update the "Latest accepted evidence" list in `docs/acceptance/sm8550-acceptance.md`.

## Fall-back paths

If the install reboot does not produce an active `rocknix-guest.service`:

- Host SSH should remain available. Check `journalctl -b -u rocknix-guest-root-ensure.service --no-pager` for seed-staging errors.
- If the seed is missing or fails the SHA check, the recovery path documented in `docs/contracts/HOW-TO-FALL-BACK.md` applies (stage the seed manually under `/storage/nix-on-rock/images/seeds/`, optional `/flash/rocknix.reseed-guest`).
- If host services fail to start, `touch /flash/rocknix.no-nspawn && reboot` routes to host recovery.
- ABL/firmware partitions must not be touched as part of this acceptance.
