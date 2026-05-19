# Guest PipeWire Has Only Dummy Sink When Staged Udev Misses Sound Records

Date: 2026-05-13

## Problem

On SM8550/Thor main-space, audio can fail even though the obvious services and device nodes look healthy:

- `rocknix-pipewire.service`, `rocknix-wireplumber.service`, and `rocknix-pipewire-pulse.service` are active.
- `/dev/snd/controlC0`, playback PCMs, and `/proc/asound/cards` are visible inside the guest.
- `pactl` / `wpctl` show only `auto_null` / `Dummy Output` and no real ALSA sinks.

## Root Cause

The host binds `/dev/snd` live into the guest, but binds `/run/udev` from a staged snapshot at `/run/.guest-udev`.

If `rocknix-guest-udev-stage` snapshots host `/run/udev` before the sound control record exists, the guest gets ALSA device nodes without matching udev metadata. WirePlumber then cannot discover/export the ALSA card and falls back to a dummy sink.

This is a timing bug in the host-side udev staging boundary, not a guest PipeWire service-liveness bug.

## Fast Diagnosis

Inside the guest:

```sh
cat /proc/asound/cards
ls -l /dev/snd
export XDG_RUNTIME_DIR=/run/user/0
export PIPEWIRE_RUNTIME_DIR=/run/user/0
export PULSE_SERVER=unix:/run/user/0/pulse/native
wpctl status
pactl list short sinks
udevadm info -q property -n /dev/snd/controlC0
```

If `/proc/asound/cards` and `/dev/snd/*` are present but `wpctl status` shows only `Dummy Output`, inspect the staged udev DB on the host:

```sh
ls -l /run/.guest-udev/data/c116:*
grep -E 'DEVNAME=/dev/snd/controlC|SUBSYSTEM=sound' /run/.guest-udev/data/c116:* 2>/dev/null
```

A missing or empty `c116:<control-minor>` record means WirePlumber has no usable udev sound metadata.

## Fix Shape

Fix the host-side staging helper, not guest PipeWire:

- Wait before snapshotting `/run/udev` until the sound control device has a udev record.
- Treat `E:DEVNAME=/dev/snd/controlC*` plus `E:SUBSYSTEM=sound` as sufficient readiness.
- Do **not** wait for `E:ALSA_CARD_NUMBER`; ROCKNIX udev records may not include it.

Live recovery, if the image already has the fixed helper or if manually testing:

```sh
rocknix-guest-udev-stage
systemctl restart rocknix-guest.service
# or, for quick validation inside the already-running guest namespace, restart the guest PipeWire/WirePlumber units after re-staging.
```

Expected healthy result:

```text
Audio
 ├─ Devices:
 │      Built-in Audio [alsa]
 ├─ Sinks:
 │      Built-in Audio Headphones Playback
 │  *   Built-in Audio Speaker playback
```

## Prevention

The soak checklist should not stop at "PipeWire is running". For guest-owned audio, assert that WirePlumber exported at least one non-dummy ALSA sink, or explicitly report `Dummy Output` as an audio discovery failure.
