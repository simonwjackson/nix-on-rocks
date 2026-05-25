# Acceptance: main-space PipeWire `/run/user/<uid>` ownership on sobo

- **Plan:** `docs/plans/2026-05-24-001-fix-main-space-pipewire-runtime-dir-plan.md`
- **Evidence (pre-fix):** `docs/thinking/SM8550/2026-05-24-main-space-runtime-dir-wipe-trace.md`
- **Target:** sobo (Odin 2 Portal, `ayn,odin2portal`)
- **Closure under test:** `/nix/store/8cp91hg2llmn89fpxilr9mz51v4szphi-nixos-system-sobo-25.11pre-git`
- **nix-on-rocks rev:** `bfe1923` (main)
- **Korri rev (`korri-rocknix-kiosk-odin2portal` config):** local checkout w/ `flake.lock` bumped to nix-on-rocks `bfe1923`
- **Soak date:** 2026-05-24
- **Soak windows used:** boot (T+~3s, from journal), T+~57s (first reach), T+5min (live re-check), warm-restart of anchor

## Verdict

```
[x] PASS — sockets present at all sampled windows, wpctl healthy,
          no MOONLIGHT_AUDIO_GATE workaround needed.
[ ] FAIL
```

## Deploy path used

```
[x] Fast loop driven from the workstation:
    1. Bump nix-on-rocks input in ../korri/flake.lock to bfe1923.
    2. NIX_SSHOPTS=... nixos-rebuild boot --flake ../korri#korri-rocknix-kiosk-odin2portal
         --target-host root@sobo --build-host simonwjackson@fuji
       (build runs natively on fuji, closure copied to sobo guest store).
    3. Copy the same toplevel into the SM8550 HOST nix store from fuji via
       NIX_SSHOPTS="-p 22" nix copy --to ssh-ng://root@sobo
         --substitute-on-destination --no-check-sigs
       (host's nix-daemon discovered via /proc/<pid>/exe of the running
       nix-daemon).
    4. On HOST (port 22):
         touch /storage/nix-on-rock/requests/manual-generation-hold
         rocknix-guest-generation-import --system /nix/store/8cp91hg2... \
           --source bfe1923-a-runtime-dir-fix
         rocknix-guest-generation-switch --to /nix/store/8cp91hg2... --no-restart
    5. systemctl reboot (full device cold boot, NOT just guest restart -- the
       race we are testing is the cold-boot tmpfs-mount-vs-socket-write race).
    6. Clear manual-generation-hold post-soak.

[ ] Production: Korri rootfs rebuilt importing nix-on-rocks-guest bumped
                to <commit-hash>; deployed via mountainous → sobo.
```

## Soak observations

### Boot ordering proof (the regression guard)

`systemd-analyze critical-chain main-space-pipewire.service` (recorded T+~70s):

```
main-space-pipewire.service                @2.117s
└─main-space-session-dbus.service          @2.114s
  └─main-space-runtime-dir.service @2.103s +8ms       ← new anchor
    └─user-runtime-dir@0.service   @2.061s +39ms      ← logind tmpfs mount
      └─systemd-logind.service     @1.913s +143ms
        └─nss-user-lookup.target   @1.909s
          └─...
```

Critical timing relationship at this boot:

| Event | T |
|---|---|
| `systemd-logind.service` ready | 2.056 s |
| `user-runtime-dir@0.service` starts | 2.061 s |
| `user-runtime-dir@0.service` finishes (tmpfs mounted on `/run/user/0`) | 2.100 s |
| `main-space-runtime-dir.service` (anchor) starts | 2.103 s |
| `main-space-runtime-dir.service` (anchor) finishes (oneshot exits) | 2.111 s |
| `main-space-session-dbus.service` starts | 2.114 s |
| `main-space-pipewire.service` starts (writes socket) | 2.117 s |

Pipewire writes its socket **17 ms after** the logind tmpfs is mounted. Pre-fix
the order was reversed by ~1 s and the mount masked the just-written socket
(see U1 trace).

Journal corroboration:

```
2026-05-24T21:51:13-04:00 sobo systemd[1]:
  Starting Main-space session runtime-dir anchor
  (orders after logind user-runtime-dir@0)...
2026-05-24T21:51:13-04:00 sobo systemd[1]:
  Finished Main-space session runtime-dir anchor
  (orders after logind user-runtime-dir@0).
```

### Boot + ~57 s (first reachable)

```
running closure:
/nix/store/8cp91hg2llmn89fpxilr9mz51v4szphi-nixos-system-sobo-25.11pre-git

anchor unit exists?  active
pipewire unit body (After= line):
After=main-space-runtime-dir.service main-space-session-dbus.service
Requires=main-space-runtime-dir.service
(no ExecStartPre=install -d /run/user/0 -- workaround removed)

sockets:
srw-rw-rw- 1 root root   0 May 24 21:51 bus
drwx------ 3 root root  60 May 24 21:51 dbus-1
srwxr-xr-x 1 root root   0 May 24 21:51 pipewire-0
-rw-r----- 1 root root   0 May 24 21:51 pipewire-0.lock
srwxr-xr-x 1 root root   0 May 24 21:51 pipewire-0-manager
-rw-r----- 1 root root   0 May 24 21:51 pipewire-0-manager.lock

uptime:  0:00 (fresh boot)
```

### Boot + ~70 s — anchor unit detail

```
ActiveState=active
SubState=exited
ActiveEnterTimestamp=Sun 2026-05-24 21:51:13 EDT
InvocationID=20bfc5d006d84d2c9f1b92a98fb730bf
Result=success
ExecMainStatus=0
```

(Oneshot + RemainAfterExit, clean exit 0.)

### Boot + ~70 s — `wpctl status`

```
PipeWire 'pipewire-0' [1.4.9, root@sobo, cookie:1544277641]
 └─ Clients:
        33. WirePlumber                         [1.4.9, root@sobo, pid:256]
        34. pipewire                            [1.4.9, root@sobo, pid:255]
        47. WirePlumber [export]                [1.4.9, root@sobo, pid:256]
        54. wpctl                               [1.4.9, root@sobo, pid:623]

Audio
 ├─ Devices:
 │      48. Built-in Audio                      [alsa]
 │
 ├─ Sinks:
 │      49. Built-in Audio Headphones Playback  [vol: 1.00]
 │  *   50. Built-in Audio Speaker playback     [vol: 0.20]
```

R2 check (no dummy-sink regression): two real ALSA sinks present, no "Dummy
Output" sink. ✅

### Boot + 5 min (T+5:22 from boot)

```
Sun May 24 09:56:35 PM EDT 2026
 21:56:35  up   0:05,  0 users,  load average: 0.98, 0.76, 0.37

OK at +5min
srw-rw-rw- 1 root root   0 May 24 21:51 bus
srwxr-xr-x 1 root root   0 May 24 21:51 pipewire-0
srwxr-xr-x 1 root root   0 May 24 21:51 pipewire-0-manager
...

wpctl still healthy (PipeWire 'pipewire-0' header returned cleanly).
```

All socket inode timestamps are still `21:51` (the boot-time creation moment).
Pre-fix evidence note observed pipewire's socket inode timestamp drifting
hours after boot (i.e., it had to be re-created by manual workaround). No
drift here.

### Warm restart of anchor

```
$ systemctl restart main-space-runtime-dir.service
$ sleep 2
$ test -S /run/user/0/pipewire-0 && test -S /run/user/0/pulse/native \
    && echo OK || echo SOCKETS-LOST
OK after anchor warm restart
```

Sockets persist across an anchor restart. Note: because `main-space-pipewire.
service` declares `Requires=main-space-runtime-dir.service`, restarting the
anchor *does* cascade-restart pipewire (new `InvocationID` for pipewire after
the anchor restart). The dependents re-create their sockets cleanly because
the underlying tmpfs is no longer being wiped mid-init. This is correct
behavior for the dependency strength we chose; `Wants=` would avoid the
cascade but would also let pipewire start without an existing anchor and
re-introduce the race. Trading the cascade for race-resilience is the right
call here.

### Host activation audit (post-cleanup)

```
rocknix-guest-activation-audit: selected=/nix/store/8cp91hg2...-nixos-system-sobo-25.11pre-git
rocknix-guest-activation-audit: running =/nix/store/8cp91hg2...-nixos-system-sobo-25.11pre-git
rocknix-guest-activation-audit: init    =/nix/store/8cp91hg2.../init
rocknix-guest-activation-audit: sbin_init=/nix/store/8cp91hg2.../init
rocknix-guest-activation-audit: applied_rev=d5d00fe4b58822da8ab0a0c21ea4306a92c65c2a
rocknix-guest-activation-audit: manual_generation_hold=absent
rocknix-guest-activation-audit: proof_marker=/nix/store/8cp91hg2.../etc/rocknix-stage10-proof-marker
rocknix-guest-activation-audit: audit complete
```

`selected = running = init = sbin_init` — all aligned to the new closure.
The `/init` symlink drift that briefly existed between switch-time and
boot-time self-resolved at boot. No host-side cleanup required.

### Moonlight integration smoke (R1 → R2 downstream blast radius)

Not run in this soak — moonlight-embedded validation is owned by a separate
acceptance lane and the deferred PR that flips `MOONLIGHT_AUDIO_GATE` back to
its enabled default has not landed yet. The soak above establishes that the
socket layer is stable; the moonlight green-frame symptom should no longer
reproduce, but that claim wants its own runtime check before the
`SDL_AUDIODRIVER=dummy` gate is removed.

```
[ ] Moonlight handshake completes, video + audio stream for ≥30 s.
[ ] Green-frame symptom did not reproduce.
[ ] Deferred PR (flip MOONLIGHT_AUDIO_GATE default, drop
    SDL_AUDIODRIVER=dummy) is unblocked.
```

## Deferred cleanup unblocked by this soak

Now that the verdict is PASS:

1. **korri**: delete `TEMP-set-sobo-volume-20.sh`. No other references to
   clean up.
2. **nix-on-rocks**: flip `MOONLIGHT_AUDIO_GATE` back to its enabled default
   in `guest/launchers/start_moonlight_embedded_gamescope.sh` and the remote
   moonlight runner; drop the `SDL_AUDIODRIVER=dummy` gate. Separate PR;
   gate the merge on the runtime moonlight smoke above.
3. **nix-on-rocks**: `se-compound` capture under
   `docs/solutions/runtime-errors/guest-main-space-pipewire-runtime-dir-socket-vanish-rocknix-2026-05-24.md`.
   Correct the 2026-05-22 moonlight-embedded substrate doc's misattribution
   to the 2026-05-13 dummy-sink doc.
4. **nix-on-rocks plan flip**: `docs/plans/2026-05-24-001-fix-main-space-pipewire-runtime-dir-plan.md`
   `status: active → completed`.

## Notes for next deploy via mountainous/Korri OTA

The deploy path used here was the host-side
`rocknix-guest-generation-import`/`-switch` pair driven manually. The standard
Korri OTA path was not exercised in this soak. The plan's `status: completed`
flip should not block on OTA validation, but a subsequent OTA-driven boot of
the same closure on sobo is a useful corroborating check that no
substrate-side activation surprises (paths, signatures, manifest entries)
were masked by the manual deploy.
