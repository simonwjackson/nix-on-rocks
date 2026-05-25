---
title: Main-space PipeWire `/run/user/<uid>` socket wipe race on Rocknix SM8550 guest
date: 2026-05-24
category: runtime-errors
module: Layer 14 main-space guest (nix-on-rocks SM8550 substrate)
problem_type: runtime_error
component: tooling
symptoms:
  - "`/run/user/0/pipewire-0` and `/run/user/0/pulse/native` sockets disappear within ~1 s of cold boot"
  - "`main-space-pipewire`, `main-space-pipewire-pulse`, `main-space-wireplumber` services report active, processes are alive on orphaned inodes"
  - "`wpctl status` from a fresh login: `Cannot connect to PipeWire: No such file or directory`"
  - "moonlight-embedded streams die instantly with `SDL_OpenAudio: Audio subsystem is not initialized` and present a green frame until session is torn down"
  - "Workaround that hides the bug: restarting `main-space-pipewire{,-pulse,-wireplumber}` post-boot, after which sockets stay until next reboot"
root_cause: async_timing
resolution_type: code_fix
severity: high
related_components:
  - systemd-logind
  - user-runtime-dir@
  - pipewire
  - wireplumber
  - main-space-pipewire
  - main-space-session-dbus
  - main-space-sway-kiosk
  - main-space-hardware-button-handler
  - sm8550-substrate
tags: [pipewire, systemd, nspawn, main-space, sm8550, runtime-dir, async-timing, rocknix]
---

# Main-space PipeWire `/run/user/<uid>` socket wipe race on Rocknix SM8550 guest

## Problem

On SM8550 sobo (Ayn Odin 2 Portal) with the nix-on-rocks main-space guest,
the substrate's PipeWire and PulseAudio UNIX sockets under `/run/user/0/`
vanish a fraction of a second after the audio services write them at cold
boot. The `main-space-pipewire*` units stay `active`, the processes keep
running on now-orphaned inodes, and every audio-aware caller fails with
ENOENT until something restarts the audio chain.

The user-visible symptom that surfaced this was moonlight-embedded
green-framing on stream start and the temporary `MOONLIGHT_AUDIO_GATE=0` /
`SDL_AUDIODRIVER=dummy` workaround. The deeper symptom was a manual
"restart the audio services after boot" script (`TEMP-set-sobo-volume-20.sh`
in korri) that operators had to run every cold boot.

## Symptoms

- `ls -la /run/user/0/` ~30 s after boot: no `pipewire-0`, no `pulse/native`,
  but `bus` and `dbus-1/` present (because they were written by
  `main-space-session-dbus.service` which is ordered slightly later).
- `systemctl is-active main-space-pipewire main-space-pipewire-pulse
  main-space-wireplumber` → all `active`. The processes themselves are
  alive on orphaned inodes pointing into the masked filesystem; they don't
  know their socket vanished.
- `XDG_RUNTIME_DIR=/run/user/0 wpctl status` → `Cannot connect to PipeWire:
  No such file or directory`. Same with `pactl info`, `swaymsg ...` (sway
  itself is unaffected because its sockets live in a different path inside
  `/run/user/0/` written by its own service later, but anything that calls
  the audio sockets bites).
- moonlight-embedded launched from the kiosk: `SDL_OpenAudio: Audio
  subsystem is not initialized` followed by stream teardown within
  milliseconds; on-screen artifact is the GL clear-color (green) frame.
- Inode timestamps on the socket files at any post-boot time the operator
  restarted audio: the recreated sockets carry a `ctime` later than the
  boot moment — diagnostic signal that the bug is not "sockets were never
  written" but "sockets were written and then masked".

## What didn't work

- **Adding `ExecStartPre=install -d -m 0700 -o 0 -g 0 /run/user/0` to
  every consumer** (`main-space-pipewire`, `-pulse`, `-wireplumber`,
  `-sway-kiosk`, etc.). Each ExecStartPre ran successfully and the
  directory existed at the moment the consumer started — but it kept
  getting masked moments later. The repeated `install -d` calls suggested
  the bug was about "directory missing"; it was actually about a tmpfs
  *mount* happening on top of the still-extant directory.
- **Reordering consumers behind `main-space-session-dbus.service` more
  tightly.** session-dbus writes `/run/user/0/bus` cleanly because its
  start happens to land *after* logind's tmpfs mount. Pulling the audio
  units behind dbus made the symptom slightly less reproducible but did
  not eliminate the race — too narrow a fix for the underlying timing
  problem.
- **Suspecting `KillUserProcesses=yes` / `RemoveIPC=yes` in logind.**
  Standard NixOS logind defaults do reap user sockets when sessions die.
  But running `loginctl list-sessions` showed no session on uid 0 at any
  point, and the wipe was actually a *fresh tmpfs mount*, not a process
  kill. The diagnosis trace
  (`docs/thinking/SM8550/2026-05-24-main-space-runtime-dir-wipe-trace.md`)
  walked through this dead-end with `inotifywait -m -r /run/user/0/` and
  caught the actual `MOVED_FROM`/`UNMOUNT` event from the tmpfs mount.
- **Suspecting host nspawn was binding into `/run/user/0/`.** Inspected
  `patches/rocknix/0006-rocknix-guest-substrate.patch` and confirmed the
  host does *not* touch `/run/user/0/` — the race is fully guest-internal.

## Solution

The actual race is between two systemd units owned by NixOS itself:

1. `user-runtime-dir@0.service` (a standard NixOS / systemd unit that
   logind activates per-uid to mount a tmpfs on `/run/user/<uid>/`).
2. `main-space-pipewire.service` (the substrate's pipewire instance that
   writes its socket at `/run/user/<uid>/pipewire-0`).

Both depend transitively on `systemd-logind.service`, but neither orders
itself relative to the other. On sobo the natural start order put
`main-space-pipewire` *before* `user-runtime-dir@0`, so pipewire wrote
its socket onto whatever directory existed at the time, then the
tmpfs mount immediately masked the entire directory tree — including
the just-written socket.

The fix is a thin oneshot anchor unit that orders cleanly behind
`user-runtime-dir@<uid>.service`, plus pulling every `/run/user/<uid>`
consumer behind the anchor.

### New unit: `main-space-runtime-dir.service`

Defined in `guest/modules/session.nix`. Parameterized on the new
`rocknix.session.runtimeDir.uid` option (default 0; flips the whole
chain mechanically if the kiosk ever moves to a non-root uid):

```nix
options.rocknix.session.runtimeDir = {
  uid = lib.mkOption {
    type = lib.types.int;
    default = 0;
    description = ''
      Uid that owns the main-space session runtime directory
      (/run/user/<uid>). All main-space-* consumers of the runtime
      directory are ordered after the logind user-runtime-dir@<uid>
      service via main-space-runtime-dir.service.
    '';
  };
};

config.systemd.services.main-space-runtime-dir = let
  uid = toString config.rocknix.session.runtimeDir.uid;
in {
  description = "Main-space session runtime-dir anchor "
              + "(orders after logind user-runtime-dir@${uid})";
  wantedBy = [ "multi-user.target" ];
  after    = [ "user-runtime-dir@${uid}.service" ];
  requires = [ "user-runtime-dir@${uid}.service" ];
  before   = [
    "main-space-session-dbus.service"
    "main-space-pipewire.service"
    "main-space-pipewire-pulse.service"
    "main-space-wireplumber.service"
    "main-space-sway-kiosk.service"
    "main-space-hardware-button-handler.service"
  ];
  serviceConfig = {
    Type = "oneshot";
    RemainAfterExit = true;
    ExecStart = "${pkgs.coreutils}/bin/test -d /run/user/${uid}";
  };
};
```

The unit body is deliberately minimal — `test -d` plus
`RemainAfterExit`. Logind has already mounted the tmpfs by the time
the anchor runs; the anchor just provides a stable ordering vertex
for the consumers and fails loud if the directory is somehow missing.

### Consumer rewiring

Every `main-space-*` unit that touches `/run/user/<uid>` now declares
`After=main-space-runtime-dir.service` (and `Requires=` where the
dependency is strong enough that the consumer cannot start without
the directory). The same change drops the six redundant
`ExecStartPre=install -d -m 0700 -o 0 -g 0 /run/user/0` lines that
the failed earlier attempts had scattered across consumers.

Affected files:

- `guest/modules/audio.nix` — pipewire, pipewire-pulse, wireplumber
- `guest/profiles/main-space.nix` — main-space-sway-kiosk (kiosk profile)
- `guest/profiles/dev-env.nix` — main-space-sway-kiosk (dev-env profile)
  + audit gap fix: drop `After=multi-user.target` (it was permitting the
  kiosk to never start while still letting the target reach `active`)
- `guest/modules/lid.nix` — main-space-hardware-button-handler
- `guest/profiles/rocknix-guest-base.nix` — main-space-session-dbus
  (and imports session.nix; dev-env.nix also imports it because it does
  not compose through rocknix-guest-base)

All four consumers also parameterize their environment triplet
(`XDG_RUNTIME_DIR`, `PULSE_SERVER`, `DBUS_SESSION_BUS_ADDRESS`,
`PIPEWIRE_RUNTIME_DIR`) from the same uid option so the future
non-root-kiosk migration is a one-config-change rather than a
substrate rewrite.

### Static-check assertions

`guest/scripts/static-checks.sh` gained guard rails so the fix cannot
silently regress:

- Anchor unit body exists in `session.nix`.
- Every consumer file references `main-space-runtime-dir.service`.
- No file keeps an `ExecStartPre=install -d /run/user/0` workaround.
- No file hardcodes `XDG_RUNTIME_DIR = "/run/user/0";` or
  `PULSE_SERVER = "unix:/run/user/0/...";` in a service `environment =
  { ... }` block (must parameterize).
- The dev-env sway kiosk does not order after `multi-user.target`
  (audit-gap parity with the main-space copy).
- Negative assertion: the fix does NOT introduce
  `KillUserProcesses=` or `RemoveIPC=` knobs in logind config (those
  were the dead-end the diagnosis ruled out; an inattentive future
  pass might add them as "defense in depth" and quietly cause new
  shutdown races).

## Why this works

systemd's tmpfs mount for `/run/user/<uid>/` happens at the moment
`user-runtime-dir@<uid>.service` starts (it's the unit's `ExecStart`
side-effect). Before the fix, the relative ordering of
`user-runtime-dir@0` vs `main-space-pipewire` was undefined because
neither knew about the other; on sobo it consistently ran pipewire
*first*, which is exactly the worst order.

`After=user-runtime-dir@${uid}.service` on the anchor + `Before=`
every consumer turns the previously-undefined ordering into a strict
partial order. The critical-chain proof from the post-fix cold boot:

```
main-space-pipewire.service       @2.117s
└─main-space-session-dbus.service @2.114s
  └─main-space-runtime-dir.service @2.103s +8ms       ← anchor (oneshot)
    └─user-runtime-dir@0.service   @2.061s +39ms      ← tmpfs mount finishes
      └─systemd-logind.service     @1.913s +143ms
```

Pipewire writes its socket at T+2.117 s; the tmpfs mount finished at
T+2.100 s. The race window is now 17 ms on the wrong side of the
mount instead of ~1 s on the right side. There's no further mount
event that can mask the socket later, so it stays for the lifetime
of the boot.

The "process alive on orphaned inode" symptom is also explained by
the original ordering: pipewire opened its file descriptor on the
socket, then the mount obscured the path, but the open FD kept the
inode reachable. The process kept running happily; only *new* path
lookups (from `wpctl`, `pactl`, SDL, anyone who tried to `connect()`
after boot) failed.

## Prevention

- **`Before=`/`After=` is a strict partial order**, not "best effort."
  When a unit's side-effect must happen before another unit reads it,
  declare the relationship explicitly. Trust nothing transitive.
- **Anchor units are cheap** and worth the extra unit when you have
  multiple consumers depending on the same precondition. Six
  `Before=` edges from one oneshot are clearer (and easier to test
  for in static checks) than six `After=` edges duplicated across six
  consumers.
- **Static-check the anti-patterns you proved didn't work**, not just
  the new pattern. The `! grep` guards in `static-checks.sh` cover
  the `install -d /run/user/0` ExecStartPre regression and the
  `KillUserProcesses` / `RemoveIPC` "defense in depth" pitfall. If
  someone re-attempts those in good faith later, the static check
  catches it and points at this doc.
- **When a socket "disappears" but the owning process stays alive,
  suspect a mount event over the directory rather than a delete.**
  `inotifywait -m -r` distinguishes them: `DELETE` for a removed
  socket, `UNMOUNT`/`MOVED_FROM` for a mount masking it. Mount-mask
  events are easy to miss with naive `ls`-based debugging.
- **Parameterize uid even when current default is 0.** Future
  non-root migrations are one of the few "we'll fix this later" items
  that actually does get worked on; making the option mechanical
  (single value flip) keeps that future migration from becoming a
  cross-substrate refactor.

## Related issues

- `docs/plans/2026-05-24-001-fix-main-space-pipewire-runtime-dir-plan.md`
  — the plan that implemented this fix in 6 atomic commits (U1
  diagnosis, U2 anchor + option, U3 consumer rewiring, U6 cold-boot
  soak; U4/U5 collapsed into U2/U3 once U1 ruled out logind).
- `docs/thinking/SM8550/2026-05-24-main-space-runtime-dir-wipe-trace.md`
  — live diagnostic trace on sobo, including the `inotifywait` capture
  that nailed the tmpfs mount as the wiper.
- `docs/acceptance/main-space-pipewire-runtime-dir-sobo-2026-05-24.md`
  — cold-boot soak PASS evidence (T+57 s, T+5 min, warm anchor restart,
  host activation audit).
- `docs/contracts/layer14-main-space-contract.md` — substrate contract,
  updated to describe the anchor and its consumers.
- `docs/solutions/runtime-errors/guest-pipewire-dummy-sink-missing-udev-sound-records-rocknix-2026-05-13.md`
  — **distinct** audio failure on the same substrate (auto_null /
  dummy sink because guest udev snapshot missed sound records). Easy
  to conflate with this bug because both surface as "moonlight has no
  audio"; the 2026-05-22 substrate doc originally misattributed this
  runtime-dir race to that 2026-05-13 dummy-sink case. See the
  Failure 4 section in
  `docs/solutions/integration-issues/moonlight-embedded-sobo-substrate-2026-05-22.md`
  for the corrected attribution.
- Related substrate work that touches the same units but is
  orthogonal: the `rocknix-guest-substrate/package.mk` cross-repo
  contract-doc cp that was unblocked in commit `bfe1923`.
