# Guest Moonlight Sees No v4l2m2m Decoder When Host Substrate Misses /dev/video Passthrough

Date: 2026-05-22

## Problem

On SM8550 (Ayn Odin 2 Portal `sobo`), Moonlight running inside the NixOS guest
never enumerates a hardware H.264 / HEVC decoder, even though the host kernel
has the right device tree node, the right driver, and the right firmware:

- `/proc/device-tree/soc@0/video-codec@aa00000/compatible = qcom,sm8550-iris`.
- Host kernel reports `[drm] Loaded GMU firmware v4.1.9` (firmware loader works).
- Host `/sys/class/video4linux/video0,video1` exist as registered v4l2 nodes
  (the iris driver finished probe).
- Host `/dev/video0` (major 81 minor 0) and `/dev/video1` (major 81 minor 1)
  exist as character devices.

Inside the guest:

- `/dev/video*` does not exist.
- Moonlight's `h264_v4l2m2m` / `hevc_v4l2m2m` decoder enumeration returns
  empty and the client silently falls back to software decode, which on
  SM8550 stalls or starves under 1080p HEVC Main 10 streams.

This is easy to misdiagnose as missing firmware because the guest's
`/lib/firmware/` is empty, the dmesg log inside the container is short, and
ROCKNIX upstream ships a kernel-overlay tree under
`/usr/lib/kernel-overlays/base/lib/firmware/qcom/{vpu,sm8550}/` that *would*
matter on a non-nspawn install. None of that matters here: firmware loading
happens in the host kernel namespace, the host already has its firmware tree
populated, and the iris driver has already registered usable v4l2m2m nodes.

## Root Cause

The Nix-on-Rocks host substrate (`rocknix-guest-substrate` package, owned by
this repo via `patches/rocknix/0006-rocknix-guest-substrate.patch`) intentionally
enumerates an explicit bind list and an explicit `DeviceAllow` list rather
than passing through host `/dev` wholesale. The list covered DRI, ALSA, input,
uhid, uinput, tty, rfkill, and tun — but not video4linux.

The container therefore got an empty `/dev/video*` and a cgroup BPF program
that denied `char-video4linux` (major 81) access regardless of whether nodes
appeared.

## Fast Diagnosis

From the laptop, with both SSH ports reachable
(host on 22, guest on 2222):

```sh
# Host view: kernel + driver + device nodes.
ssh -p 22 root@<device> '
  ls /sys/class/video4linux/
  ls -l /dev/video*
  grep video /proc/devices
  systemctl show rocknix-guest.service -p DeviceAllow | tr " " "\n" | grep -i video
'

# Guest view: what the container actually sees.
ssh -p 2222 root@<device> '
  ls -la /dev/video*
  nix-shell -p v4l-utils --run "v4l2-ctl --list-devices" 2>/dev/null
'
```

Signature of this bug:

- Host has `/sys/class/video4linux/video0` etc. *and* `/dev/video0` etc.
- Host `rocknix-guest.service` has no `DeviceAllow` entry mentioning video.
- Guest `/dev/video*` is missing entirely.

## Fix Shape

Fix the host nspawn substrate, not guest firmware:

1. Add `DeviceAllow=char-video4linux rwm` to `rocknix-guest.service`'s static
   allow list. Use the class form because the kernel can register multiple
   v4l2 nodes and the bind step enumerates them at runtime.
2. In `rocknix-guest-start`, iterate over `/dev/video[0-9]*` and emit one
   `--bind=...` per node the host actually exposes, and emit a single
   `emit_device_allow "DeviceAllow=char-video4linux rwm"` (companion to the
   static entry; both are needed because the script applies a runtime
   `set-property` that overwrites the static allow list with its own).
3. Extend `tests/guest-substrate-static-checks.sh` and
   `tests/guest-substrate-runtime-smoke.sh` to assert the new bind loop and
   DeviceAllow entry exist.

Why iterate rather than hardcode `video0` + `video1`:

- The v4l2 framework assigns ordinals at driver-probe time, in the order
  drivers register. ROCKNIX kernel revisions or vendor patches can shift the
  ordinals (a second codec or webcam appearing earlier would push iris to
  video2/video3).
- The bind loop mirrors the existing `emit_safe_block_binds` runtime
  enumeration pattern used for game/media storage.

## Live Validation Path

Before committing the patch, validate the diagnosis with no rebuild:

```sh
# On host:
systemctl set-property rocknix-guest.service \
  DeviceAllow='char-video4linux rwm'

# On guest:
mknod /dev/video0 c 81 0
mknod /dev/video1 c 81 1
chmod 660 /dev/video0 /dev/video1

# On guest, confirm with v4l2-ctl:
nix-shell -p v4l-utils --run 'v4l2-ctl -d /dev/video0 --info; \
  v4l2-ctl -d /dev/video0 --list-formats-out; \
  v4l2-ctl -d /dev/video0 --list-formats'
```

Expected output (2026-05-22 on `sobo`):

```
Card type        : Iris Decoder
Capabilities     : 0x84204000
  Video Memory-to-Memory Multiplanar
  Streaming
  Extended Pix Format

Video Output Multiplanar:
  [0]: 'H264' (H.264, compressed, dyn-resolution)
  [1]: 'HEVC' (HEVC, compressed, dyn-resolution)
  [2]: 'VP90' (VP9, compressed, dyn-resolution)
  [3]: 'AV01' (AV1 OBU Stream, compressed, dyn-resolution)

Video Capture Multiplanar:
  [0]: 'NV12'
  [1]: 'Q08C' (QCOM Compressed 8-bit Format)
```

This covers HEVC Main 10 (Korri Stream's default).

The live patch is non-persistent: the `set-property` reverts on
`systemctl daemon-reload` or service restart, and the mknod entries vanish
on container restart. Persist by shipping the substrate patch and rebuilding.

## Where the Persistent Fix Lives

- `patches/rocknix/0006-rocknix-guest-substrate.patch` — the only patch
  touched by this fix.

## Related

- `docs/solutions/runtime-errors/guest-pipewire-dummy-sink-missing-udev-sound-records-rocknix-2026-05-13.md`
  — same shape, different subsystem: the host substrate's bind/staging policy
  was the bug, not the guest service.
- The handoff that triggered this investigation incorrectly identified the
  root cause as missing firmware (the empty guest `/lib/firmware/` was a red
  herring). Future agents working on similar Sobo issues should verify
  `/sys/class/video4linux/` and the host `/dev/` view before assuming a
  firmware-shipping fix is required.

## Not a Fix For

This change does not address the independent Moonlight Qt-Wayland stall on
sway (the "Failure A" described in the originating handoff). That requires a
moonlight-side workaround (`QT_QPA_PLATFORM=xcb` + XWayland, gamescope wrap,
or a custom moonlight build with `CONFIG+=embedded`). Track separately.
