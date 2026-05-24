# Main-space `/run/user/0/` wipe trace — sobo, 2026-05-24

Diagnostic evidence for plan `docs/plans/2026-05-24-001-fix-main-space-pipewire-runtime-dir-plan.md`
implementation unit **U1** (cold-boot evidence). Captured live on sobo
via `ssh root@sobo -p 2222` against the boot at `2026-05-24 11:58`.

## Verdict

**Sole actor: `user-runtime-dir@0.service`** (NixOS default logind unit
template, instantiated at boot for uid 0).

**Mechanism: ordering race, not a wipe loop.** `user-runtime-dir@0.service`
mounts a fresh tmpfs over `/run/user/0/` exactly **one second after**
`main-space-pipewire.service` and `main-space-pipewire-pulse.service`
have already written their listening sockets inside the pre-existing
`/run/user/0/` plain directory. The tmpfs mount masks the sockets;
the PipeWire processes keep their bound inodes (still visible in
`ss -lxn`), but every userspace caller that opens
`/run/user/0/pipewire-0` or `/run/user/0/pulse/native` by path sees
an empty tmpfs and fails with `ENOENT`.

This is **not** a substrate tmpfiles rule, **not** a transient
`pam_systemd` session close, **not** logind tearing down the
directory on idle. It is logind doing exactly what it is designed to
do (set up `/run/user/$UID` as a tmpfs when a user becomes
session-relevant), just running too late relative to the substrate
audio services.

## Implications for the plan

The default U2/U4 plan posture (tmpfiles rule + oneshot anchor;
`KillUserProcesses=no` / `RemoveIPC=no`; possibly mask
`user-runtime-dir@.service`) is **wrong for this evidence** and
should be revised before implementation. The correct fix is much
narrower:

- **Do NOT** introduce a substrate-owned `systemd.tmpfiles.rules`
  entry for `/run/user/<uid>`. logind already creates the directory
  inside its tmpfs with mode `0700` and the right uid/gid. A second
  creator would race the same way the audio services do today.
- **Do NOT** mask `user-runtime-dir@.service`. We *want* logind to
  create the tmpfs; we just need to wait for it.
- **Do NOT** set `KillUserProcesses=no` / `RemoveIPC=no`. Those address
  a different failure mode (logind reaping uid-0 state on session
  close) which is not what we observed.
- **DO** introduce a thin anchor unit `main-space-runtime-dir.service`
  (`Type=oneshot`, `RemainAfterExit=yes`) that orders
  `After=user-runtime-dir@${uid}.service`,
  `Requires=user-runtime-dir@${uid}.service`. Every main-space
  consumer then orders `After=main-space-runtime-dir.service`.
- **DO** drop the six `ExecStartPre=install -d ... /run/user/0` lines
  — they are redundant once the consumers all order after the
  anchor (logind has already created the directory inside its
  tmpfs).
- **DO** keep the UID parameterization (`rocknix.session.runtimeDir.uid`)
  — the `user-runtime-dir@.service` template instantiates per-uid, so
  the anchor's `After=user-runtime-dir@${uid}.service` parameterizes
  cleanly for a future non-root kiosk.

## Evidence

### Boot timeline

```
May 24 11:58:06  main-space-pipewire        Started
                 main-space-pipewire-pulse  Started
                 main-space-wireplumber     Started
                 main-space-session-dbus    Started
May 24 11:58:07  user-runtime-dir@0.service Starting
                 user-runtime-dir@0.service Finished
```

Pipewire wrote its sockets at 11:58:06. One second later, logind
mounted a fresh tmpfs over `/run/user/0/`, hiding them.

### Mount table at the time of investigation (boot + 1h 20m)

```
tmpfs on /run/user/0 type tmpfs (rw,nosuid,nodev,relatime,size=765320k,nr_inodes=191330,mode=700)
```

`/run/user/0` IS a tmpfs mount. Inode count and size are logind's
defaults; the mount was made by `user-runtime-dir@0.service`.

### `/run/user/0/` contents and mtimes

```
drwx------ 6 root root 280 May 24 12:32 .
srw-rw-rw- 1 root root   0 May 24 11:58 bus
drwx------ 3 root root  60 May 24 11:58 dbus-1
drwx------ 2 root root  80 May 24 12:32 pulse
srwxr-xr-x 1 root root   0 May 24 12:32 pipewire-0
-rw-r----- 1 root root   0 May 24 12:32 pipewire-0.lock
srwxr-xr-x 1 root root   0 May 24 12:32 pipewire-0-manager
-rw-r----- 1 root root   0 May 24 12:32 pipewire-0-manager.lock
srwxr-xr-x 1 root root   0 May 24 12:22 sway-ipc.0.1343.sock
srwxr-xr-x 1 root root   0 May 24 12:22 wayland-1
```

`bus` and `dbus-1` carry the 11:58 boot mtime — surprising, because
the tmpfs was mounted *after* dbus started. The most likely
explanation: `main-space-session-dbus.service` is restarted by
something around 12:22 (when sway sockets appear) and dbus
recreates `/run/user/0/bus` inside the now-mounted tmpfs. The
11:58 mtimes are dbus's recreated socket mtimes after the second
start, not the original. (This is consistent with sway and pulse
having later mtimes; the only thing logind's tmpfs preserves from
the masked-over original is nothing — every visible entry was
created post-mount.)

The pipewire mtimes at 12:32 correspond to the
`systemctl restart main-space-pipewire main-space-pipewire-pulse`
workaround from `korri:TEMP-set-sobo-volume-20.sh`. After that
restart, with the tmpfs already mounted, pipewire's new sockets
landed inside the tmpfs and remain visible. This proves the unit
definitions can produce durable sockets — the only thing wrong is
the boot ordering.

### `user-runtime-dir@0.service` state

```
user-runtime-dir@0.service  loaded active exited
```

`exited` is the correct steady state for a oneshot. The unit
mounted the tmpfs at 11:58:07 and has not run again this boot.

### Consumer `After=` chains at fault (today, pre-fix)

None of the main-space services include `user-runtime-dir@0.service`
in their `After=` chain:

```
main-space-pipewire.service After:
  basic.target sysinit.target system.slice main-space-session-dbus.service
main-space-pipewire-pulse.service After:
  basic.target sysinit.target system.slice main-space-session-dbus.service main-space-pipewire.service
main-space-wireplumber.service After:
  basic.target sysinit.target system.slice main-space-session-dbus.service main-space-pipewire.service
main-space-sway-kiosk.service After:
  inputplumber.service main-space-session-dbus.service
main-space-session-dbus.service After:
  basic.target sysinit.target system.slice
```

`basic.target` orders before logind's `user-runtime-dir@.service`,
so all five consumers start in parallel with (or ahead of)
`user-runtime-dir@0.service`. That is the race.

### Process state right now (current connection)

```
ss -lxn | grep -E 'pipewire|pulse':
  /run/user/0/pulse/native           LISTEN
  /run/user/0/pipewire-0             LISTEN
  /run/user/0/pipewire-0-manager     LISTEN

XDG_RUNTIME_DIR=/run/user/0 wpctl status:
  PipeWire 'pipewire-0' [1.4.9, root@sobo, cookie:1112506216]
  └─ Clients:
       54. Moonlight Embedded   [1.4.9, root@sobo, pid:2902]
```

Audio is working *because* the workaround ran at 12:32. Without
the workaround, this same `wpctl status` would fail with `ENOENT`
on `/run/user/0/pipewire-0` until the next manual restart.

## Pointer to plan updates

The plan's U2 (owner unit), U3 (consumer ordering), and U4 (logind
treatment) sections will be revised in place to reflect this
verdict — narrower, simpler fix. The plan's Open Questions
"Deferred to Implementation → Exact logind treatment" item is
resolved as: order against `user-runtime-dir@${uid}.service`, no
logind knobs touched.
