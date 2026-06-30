# SM8550 Thor DRM Coldplug Boot Gate — 2026-06-30

## Purpose

This acceptance gate proves the SM8550 guest substrate no longer triggers a
synthetic DRM coldplug after the guest compositor has taken KMS through
logind/libseat. The original failure mode on Bandai/Thor was not a generic
input failure: Sway owned `/dev/dri/card0`, then the host-side
`rocknix-guest-coldplug` post-start helper ran, libseat/logind device accounting
went out of sync, and wlroots began failing atomic commits with `EACCES`.

This document is an evidence template. Fill it during the first controlled boot
of an image that includes `af3bd00 fix(sm8550): avoid post-start DRM coldplug in
guest substrate` or a descendant with the same invariant.

## Source invariant

The image under test must satisfy all of these before device rollout:

- `patches/rocknix/0018-substrate-coldplug-guest-uevents.patch` is in
  `patches/rocknix/series`.
- `scripts/verify-sm8550-contract` passes.
- The patched `rocknix-guest.service` has no
  `ExecStartPost=.*/rocknix-guest-coldplug` wiring.
- Writable guest `uevent` binds remain limited to the early substrate setup path
  needed before guest PID 1 and the compositor start.

## Pre-boot record

Fill before the reboot:

```text
nix_on_rocks_commit=
patch_series_sha256=
product_selector=thor
product_payload_rev=
product_payload_lock_sha256=
artifact_run=
artifact_name=
artifact_sha256_tar=
artifact_sha256_img_gz=
rocknix_artifact_verify=PASS/FAIL
fat_label=ROCKNIX
fat_logical_block_size=4096
```

## Live-state cleanup precondition

Before judging the rebuilt image, remove or disable known live diagnostics that
can mask or reintroduce the old failure independently of the image contents.
Record the action and evidence here:

```text
/storage/.config/system.d/rocknix-guest.service.d/90-live-uevent-rw-test.conf=ABSENT/REMOVED/LEFT_PRESENT_WITH_REASON
/storage/.cache/rocknix-guest-start-uevent-rw-test=ABSENT/REMOVED/LEFT_PRESENT_WITH_REASON
/storage/nix-on-rock/requests/manual-generation-hold=ABSENT/REMOVED/LEFT_PRESENT_WITH_REASON
```

Do not use compositor/session restarts as acceptance proof. The gate is a clean
boot gate.

## Evidence commands

Run after the fixed host boots and SSH is available. These commands are intended
for observation and log collection; device mutation still requires operator
approval in the rollout procedure.

```sh
ssh -p 22 root@bandai 'cat /etc/os-release; uname -a'
ssh -p 22 root@bandai 'systemctl status rocknix-guest.service --no-pager'
ssh -p 22 root@bandai 'journalctl -b -u rocknix-guest.service --no-pager'
ssh -p 22 root@bandai 'journalctl -b --no-pager | grep -E "rocknix-guest-coldplug|Device not taken|DRM_IOCTL_MODE_ATOMIC|Atomic commit failed|Page-flip failed|Failed to disable CRTC" || true'
ssh -p 22 root@bandai 'systemctl --failed --no-pager'
ssh -p 2222 korri@bandai 'systemctl --failed --no-pager'
ssh -p 2222 korri@bandai 'swaymsg -t get_outputs || true'
```

## Pass criteria

- `rocknix-guest.service` reaches the expected active state for normal main-space
  boot.
- The boot journal contains no post-start invocation of
  `rocknix-guest-coldplug`.
- After Sway/compositor startup, the boot journal contains no libseat/logind
  close failure matching `Could not close device: Device not taken`.
- After Sway/compositor startup, the boot journal contains no repeated wlroots
  DRM `Permission denied` storm, including:
  - `DRM_IOCTL_MODE_ATOMIC failed: Permission denied`
  - `connector DSI-2: Atomic commit failed: Permission denied`
  - `connector DP-1: Atomic commit failed: Permission denied`
  - `Page-flip failed on output DSI-2`
  - `Failed to disable CRTC`
- The internal panels continue updating after boot without a compositor/session
  restart.
- Guest input works through the normal logind-backed compositor path.

## Failure handling

If any pass criterion fails:

1. Do not restart `korri-compositor.service`, `korri-sessiond.service`, or
   `korri-steam-gamescope.service` as proof of success.
2. Preserve the boot journal and unit state.
3. Record whether `/flash/rocknix.no-nspawn` or `rocknix.safe=1` recovery was
   needed.
4. Treat DP hotplug as unproven until a separate live unplug/replug run passes.

## Result

```text
status=NOT_RUN/PASS/FAIL
operator=
date=
host_os_version=
host_build_id=
kernel=
guest_current_system=
notes=
```
