# moonlight-embedded ↔ Sunshine substrate failure modes on Sobo

**Captured:** 2026-05-22 (plan 003 U4 G1 first-stream attempt on Sobo
SM8550 + Sunshine on aka).

**Outcome:** five real failure modes between "pair succeeds" and
"video packets render". All cleared; sdl-platform stream confirmed
working end-to-end (199 inbound video packets captured via tcpdump,
moonlight window present in sway tree, "Received first video packet
after 0 ms" / "Received first audio packet after 400 ms" in launch.log).

This doc exists so the next operator hits these once, not five times.

---

## Test posture when this was captured

- Sobo (SM8550 handheld, ROCKNIX 25.x host + systemd-nspawn NixOS guest,
  guest on port 2222, rocknix-sway-kiosk.service running, PipeWire
  socket broken — see runtime-errors/guest-pipewire-dummy-sink-missing-
  udev-sound-records-rocknix-2026-05-13.md).
- Sunshine on aka (`192.168.1.117`, NixOS x86_64, AMD Radeon RX 7900 XT,
  Mesa 26.0.2, sway/Wayland session, sunshine-2025.924.154138).
- moonlight-embedded built with patch stack 0001/0001a/0002 (SM8550
  v4l2m2m closure: `/nix/store/jria9n2l...moonlight-embedded-2.7.1-sm8550-v4l2m2m`).

---

## Failure 1 — "Already paired" rejection on every pair attempt

### Symptom

```
$ moonlight pair 192.168.1.117
Connecting to 192.168.1.117...
Please enter the following PIN on the target PC: 6072
Failed to pair to server: Already paired
```

The PIN is printed and the rejection arrives within ~1 second, with no
chance for the operator to enter the PIN at the Sunshine web UI. The
Sobo-side keystore is empty (`/storage/.cache/moonlight/` and
`/root/.cache/moonlight/` both have no `client.p12`), so the client
genuinely has no pair state — yet the server thinks it does.

### Root cause

Sunshine matches incoming pair requests against `named_devices[].name`
in `~/.config/sunshine/sunshine_state.json`. Names default to the
hostname of the client. Two prior pair attempts had landed `"name":
"sobo"` entries in the registry. Any subsequent pair attempt from a
client identifying itself as "sobo" is rejected as a duplicate even
when the cert public key is brand new.

`sunshine_state.json` excerpt before cleanup:

```json
{
  "root": {
    "named_devices": [
      { "name": "usu",  "uuid": "3293D6B1-..." },
      { "name": "yuki", "uuid": "97D3215A-..." },
      { "name": "sobo", "uuid": "80C3CB60-..." },
      { "name": "sobo", "uuid": "93D6C549-..." }
    ]
  }
}
```

### Fix

The Sunshine version on aka (2025.924.154138) has no "Unpair" or
"Unpair All" button in its web UI. Edit the state file directly,
filtering out the stale entries, and restart sunshine:

```sh
# on the Sunshine host (aka), as the user that runs sunshine:
STATE=$HOME/.config/sunshine/sunshine_state.json
cp "$STATE" "$STATE.bak.$(date +%s)"
nix-shell -p jq --run \
  "jq '.root.named_devices |= map(select(.name != \"sobo\"))' $STATE > $STATE.new"
mv "$STATE.new" "$STATE"
systemctl --user restart sunshine
```

Confirm with `jq '.root.named_devices | map(.name)' "$STATE"` — should
no longer contain the orphan entry.

### What to do for plan 003

The Sunshine half-state is not our package's concern, but the symptom
is exotic enough that the operator hits it without warning. Add a
sentence to the streaming-launcher docstring pointing here.

---

## Failure 2 — "Too many options: No such file or directory" on stream

### Symptom

```
$ moonlight stream 192.168.1.117 "Desktop (Sway)" -platform sdl
Too many options: No such file or directory
```

But `moonlight pair 192.168.1.117` (no app arg) works, and
`moonlight list 192.168.1.117` works. The pair / list paths only take
the host as a positional; the failure is unique to `stream` and the
error message points nowhere useful.

### Root cause

`Usage: moonlight [action] (options) [host]`. The app is an **option**
(`-app <name>`), not the second positional. Passing it positionally
makes the second-positional parser stop at the host and then bail on
the next non-option token.

The U2-committed `start_moonlight_embedded_gamescope.sh` and
U5-committed `remote-moonlight-runner.sh` both made this mistake. The
fix lands in this same commit:

```sh
# wrong:
exec moonlight ... stream "$HOST" "$APP"
# right:
exec moonlight ... stream -app "$APP" "$HOST"
```

### Trace from `moonlight --help`

> `-app <app>          Name of app to stream`
> `Usage: moonlight [action] (options) [host] [-port <number>]`

The order is: action → options → host → optional port. App is an
option, not a positional.

---

## Failure 3 — "You must pair with the PC first" *after* a successful pair

### Symptom

```
$ moonlight pair 192.168.1.117     # via SSH shell
Connecting to 192.168.1.117...
Please enter the following PIN: 4244
Succesfully paired                  # (sic — the typo is in moonlight)

$ moonlight stream ... 192.168.1.117    # via swaymsg exec
Connecting to 192.168.1.117...
Generating certificate...done
You must pair with the PC first
```

Sunshine's `sunshine_state.json` shows the new client *is* paired
server-side. But the streaming attempt regenerates a fresh client cert
("Generating certificate...done"), proving moonlight is looking at a
keydir that has no prior pair state.

### Root cause

`moonlight-embedded`'s default keydir is `$XDG_CACHE_HOME/moonlight`
(falling back to `$HOME/.cache/moonlight`). The two surfaces use
different environments:

| Surface | `HOME` | `XDG_CACHE_HOME` | Default keydir |
|---|---|---|---|
| Plain SSH shell on the guest (root login) | `/root` | unset | `/root/.cache/moonlight` |
| Kiosk sway session (rocknix-sway-kiosk) | `/storage` | `/storage/.cache` | `/storage/.cache/moonlight` |
| Process invoked via `swaymsg exec` | inherits sway's env | inherits sway's env | `/storage/.cache/moonlight` |

Pair from SSH → cert lands under `/root/.cache/moonlight`. Stream from
the kiosk → moonlight looks under `/storage/.cache/moonlight`, finds
nothing, generates a fresh unpaired cert, fails the trust check.

### Fix

Pin `-keydir` explicitly on **both** sides so the env trap is removed:

```sh
moonlight -keydir /storage/.cache/moonlight pair 192.168.1.117
moonlight -keydir /storage/.cache/moonlight stream ... 192.168.1.117
```

The U2-committed streaming launcher already does this. The
U3-committed `pair-moonlight-embedded.sh` also passes `-keydir
"$MOONLIGHT_KEYDIR"` correctly. **The lesson is: don't bypass the
launcher scripts and call `moonlight pair` directly without
`-keydir`.**

### Manual recovery if you already hit this

If pair landed in `/root/.cache/moonlight` (because you ran the bare
`moonlight pair` command from SSH), copy the state to the
kiosk-visible path:

```sh
mkdir -p /storage/.cache/moonlight
cp /root/.cache/moonlight/* /storage/.cache/moonlight/
```

---

## Failure 4 — audio init failure cascades to video stream teardown

### Symptom

```
Initializing audio stream...done
Starting video stream...Using FFmpeg decoder: h264
done
Starting audio stream...Failed to open audio: Audio subsystem is not initialized
Audio stream start failed: -1
Stopping video stream...No video traffic was ever received from the host!
Received first video packet after 0 ms
done
```

The interleaving is misleading. moonlight DID receive the first video
packet ("Received first video packet after 0 ms"), but the audio
failure tore down the entire stream within milliseconds of "Starting
audio stream...". The video stream is collateral damage. The visible
artifact is a green-screen moonlight window that disappears within a
second.

### Root cause

Sobo's PipeWire is broken in this branch (rocknix-pipewire.service is
running, but the `/run/user/0/pipewire-0` socket is missing — see
runtime-errors/guest-pipewire-dummy-sink-missing-udev-sound-records-
rocknix-2026-05-13.md). SDL2's audio backend (pulse → fails;
alsa-pipewire-bridge → fails) cannot open any device. `SDL_OpenAudio`
returns "Audio subsystem is not initialized".

moonlight-embedded does not treat audio failure as a degraded-mode
trigger. Its design is: video + audio + control are co-equal streams;
if any fails to start, the whole session aborts. There is no `-noaudio`
flag, and `-localaudio` ("play audio on the host") still calls
client-side `SDL_OpenAudio` (it only changes what the *server* does
with the audio stream, not the client's init path).

### Fix

SDL has a built-in `dummy` audio driver that always succeeds and
produces no actual audio output. Setting `SDL_AUDIODRIVER=dummy`
bypasses the failing real backend entirely.

The streaming launcher gains a `MOONLIGHT_AUDIO_DRIVER` env knob in
this commit; setting it exports `SDL_AUDIODRIVER`. The runner
auto-defaults to `dummy` when `MOONLIGHT_AUDIO_GATE=0` (the
video-only smoke posture plan 003 U4 G5a uses), so operators in
degraded mode don't have to remember.

```sh
# explicit video-only smoke posture:
MOONLIGHT_AUDIO_DRIVER=dummy start_moonlight_embedded_gamescope.sh aka Desktop

# via the runner -- audio gate parked, defaults to dummy:
MOONLIGHT_AUDIO_GATE=0 \
  remote-moonlight-runner.sh aka "Desktop (Sway)"
```

### When this becomes obsolete

Plan 003 U6 G5b fixes the PipeWire substrate. When it does, the audio
gate flips back on by default and `MOONLIGHT_AUDIO_DRIVER` is no
longer set. The `dummy` posture remains available for future degraded
modes (e.g. headless smoke runs from CI).

---

## Failure 5 — "Waiting for IDR frame" forever

### Symptom

```
Waiting for IDR frame
Waiting for IDR frame
(... repeated ~40+ times ...)
Reached consecutive drop limit
IDR frame request sent
Waiting for IDR frame
```

The moonlight window IS created (visible in `swaymsg -t get_tree`),
but no decoded frames are presented. CPU usage on moonlight stays
below 1%.

### Root cause

Subsumed by Failure 4. With the audio cascade tearing down the stream
within milliseconds, no IDR (I-frame / keyframe) ever has time to
arrive on the video socket. The "Waiting for IDR frame" loop is
moonlight's video decoder asking the network thread for the first
keyframe; the network thread never gets one because the control
stream has already been torn down.

Once `SDL_AUDIODRIVER=dummy` clears Failure 4, video packets arrive
within ~50ms ("Received first video packet after 0 ms") and the IDR
loop completes immediately.

### What this looked like visually

User reported the moonlight window stayed visible as a solid green
frame. That's the SDL2 GL framebuffer's initial clear color — no
decoded frame ever overwrote it. After the Failure 4 fix, the green
disappears.

---

## Bonus gotcha — `moonlight pair` doesn't survive SSH abort

`moonlight pair <host>` blocks interactively on `read(stdin)` waiting
for the PIN to be entered at the server. When the SSH session that
launched it is aborted (which the tooling here does on long-running
interactive commands), the moonlight client is killed mid-pair —
*after* the server has accepted the PIN and updated
`sunshine_state.json`, but *before* the client writes `client.p12` to
its keydir. The result is the half-paired state of Failure 1: server
thinks you're paired, client thinks you're not, and Failure 1 blocks
the recovery path.

Pair under `setsid` with stdin redirected so the process survives the
SSH disconnect:

```sh
ssh ... 'setsid moonlight pair 192.168.1.117 \
  </dev/null >/tmp/pair.log 2>&1 &
  echo $! > /tmp/pair.pid
  disown
  cat /tmp/pair.log  # tail until PIN appears
'

# operator enters PIN at Sunshine web UI

ssh ... 'cat /tmp/pair.log; ls -la /storage/.cache/moonlight/'
```

The `pair-moonlight-embedded.sh` script (U3) doesn't need this
because it stays attached — but its assumption is "interactive operator
in a stable terminal". For automation harnesses, the detached form is
mandatory.

---

## Evidence captured during this session

- `/storage/.guest/runs/20260523-001119-sdl-probe8-tcpdump/`
  - `launch.log`: full moonlight verbose output showing the working
    handshake.
  - `cap.pcap`: 200-packet pcap on `eth0` filtered to `host
    192.168.1.117`. 199 inbound (UDP video + audio), 1 outbound
    (initial control). Decodes cleanly in `tcpdump -r`.

- aka sunshine log around the working session:
  ```
  Info: Executing [Desktop]
  Info: New streaming session started [active sessions: 1]
  Info: CLIENT CONNECTED
  Info: Setting default sink to: [sink-sunshine-stereo]
  Info: Opus initialized: 48 kHz, 2 channels, 96 kbps (total), LOWDELAY
  Info: CLIENT DISCONNECTED      # only because the operator killed moonlight
  ```

---

## Open questions, next session

1. v4l2m2m platform end-to-end (plan 003 U4 G1+). Substrate now
   validated for sdl; everything from "moonlight connects to Sunshine"
   onward applies identically to v4l2m2m. The novel failure modes
   should be limited to EGL/V4L2 territory.

2. Audio substrate (plan 003 U4 G5b / U6). The `dummy` driver gets us
   past the audio-cascade gate, but a real ship needs PipeWire fixed.
   Out of scope for this learning doc.

3. The "green screen" the operator observed could be reproduced
   deliberately as a regression test for the audio-cascade behaviour:
   point moonlight at any unreachable Sunshine and confirm the window
   stays green until the audio teardown kills it.
