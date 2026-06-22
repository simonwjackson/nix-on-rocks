# Guest PipeWire Has Only Dummy Sink When Guest Udev Misses Sound Records

Date: 2026-05-13
Updated: 2026-06-22

## Problem

In a ROCKNIX systemd-nspawn guest, audio can fail even though the obvious
services and device nodes look healthy:

- `main-space-pipewire.service`, `main-space-wireplumber.service`, and
  `main-space-pipewire-pulse.service` are active.
- `/dev/snd/controlC*`, playback PCMs, and `/proc/asound/cards` are visible
  inside the guest.
- `pactl` / `wpctl` show only `auto_null` / `Dummy Output` and no real ALSA
  sinks.

This has been observed on SM8550 devices and RK3566/RG353M-style guests when
host-bound sound cards are visible in sysfs but card-level udev metadata is not
usable inside the guest.

## Root Cause

`/dev/snd` is not enough for WirePlumber. WirePlumber coldplugs ALSA cards via
udev properties, and a host-bound sound card can appear inside the guest with
only minimal sysfs data such as:

```text
DEVPATH=/devices/platform/sound/sound/card0
SUBSYSTEM=sound
```

When the guest lacks a corresponding `/run/udev/data/+sound:card*` record with
`SOUND_INITIALIZED=1` and stable path identity, WirePlumber cannot discover or
export the ALSA card and falls back to a dummy sink.

Older host-side staging could also snapshot `/run/udev` before sound records
existed. The durable substrate fix is guest-side: the guest owns its writable
`/run/udev` database and repairs missing host-bound sound-card records before
WirePlumber starts.

## Fast Diagnosis

Inside the guest:

```sh
cat /proc/asound/cards
ls -l /dev/snd
export XDG_RUNTIME_DIR=/run/user/0
export PIPEWIRE_RUNTIME_DIR=/run/user/0
export PULSE_SERVER=unix:/run/user/0/pulse/native
wpctl status
pactl list short cards
pactl list short sinks
udevadm info -q property -p /sys/class/sound/card0
```

If ALSA cards and `/dev/snd/*` exist but `pactl list short cards` is empty or
`wpctl status` shows only `Dummy Output`, inspect the card records:

```sh
for card in /sys/class/sound/card*; do
  echo "== $card =="
  udevadm info -q property -p "$card" | grep -E '^(SOUND_INITIALIZED|ID_PATH|ID_PATH_TAG|SUBSYSTEM)='
done
ls -l /run/udev/data/+sound:card* 2>/dev/null
```

A missing `SOUND_INITIALIZED=1` or missing path identity means WirePlumber does
not have enough card metadata to coldplug the device.

## Fix Shape

The guest base now provides `rocknix-sound-card-udev-hydrate.service`:

- runs after guest udev trigger/settle,
- tries normal `udevadm trigger` first,
- tolerates read-only sysfs `uevent` writes inside nspawn,
- synthesizes only boot-scoped `/run/udev/data/+sound:card*` records for cards
  that still lack `SOUND_INITIALIZED=1`,
- derives `ID_PATH` / `ID_PATH_TAG` from `udevadm test-builtin path_id` or the
  sysfs platform path instead of hard-coding a device such as `platform-sound`,
- orders before `main-space-wireplumber.service`.

The service is a substrate discovery repair. Device profiles still own route
policy separately via `rocknix.device.audio.route.*`:

- SM8550 UCM routes wait for the WirePlumber-created sink such as
  `alsa_output.platform-sound.HiFi__Speaker__sink`.
- RG353M currently keeps an explicit interim manual PCM route until a real
  RK817 UCM/headphone route is validated.

## Live Recovery

After deploying an image with the fix:

```sh
systemctl restart rocknix-sound-card-udev-hydrate.service main-space-wireplumber.service
pactl list short cards
pactl list short sinks
```

Expected healthy result is at least one real ALSA card and a non-`auto_null`
sink. For SM8550 speaker validation, the default route should be the declared
WirePlumber/UCM sink, for example:

```text
alsa_card.platform-sound
alsa_output.platform-sound.HiFi__Speaker__sink
```

## Prevention

The soak checklist should not stop at "PipeWire is running". For guest-owned
audio, assert that WirePlumber exported at least one non-dummy ALSA sink, or
explicitly report `Dummy Output` / `auto_null` as an audio discovery failure.
For handheld volume validation, products should adjust Pulse's
`@DEFAULT_SINK@` instead of hard-coding ALSA devices.
