---
title: "fix: Give main-space /run/user/<uid> a single owner so PipeWire sockets survive boot"
type: fix
status: completed
date: 2026-05-24
verify_command: "bash guest/scripts/static-checks.sh"
---

# fix: Give main-space `/run/user/<uid>` a single owner so PipeWire sockets survive boot

## Summary

Introduce one declared owner of `/run/user/<uid>` inside the nix-on-rocks
guest substrate (default uid `0`, parameterized for a future non-root
kiosk), and order every `main-space-*` session unit against that owner —
removing the six independent `ExecStartPre=install -d /run/user/0`
incantations that currently race default NixOS logind for control of
the kiosk runtime directory. Also fix the dev-env profile's
`main-space-sway-kiosk.service` ordering audit gap surfaced while
mapping the consumer call sites.

---

## Problem Frame

On sobo (SM8550, ROCKNIX-on-nspawn nix-on-rocks guest, kiosk runs as
root uid 0), `main-space-pipewire.service` and
`main-space-pipewire-pulse.service` start at boot and create their
listening sockets under `/run/user/0/`. Shortly after, those sockets
disappear from the filesystem (`ls /run/user/0/` shows neither
`pipewire-0` nor `pulse/native`), even though the PipeWire and
PipeWire-Pulse processes stay alive (`ss -lxn | grep -E
'pipewire|pulse'` still lists them as listening). Because the
processes are alive, the units never restart themselves — but every
userspace tool that opens `/run/user/0/pipewire-0` or
`/run/user/0/pulse/native` fails with `ENOENT`. Restarting both audio
units re-creates the sockets and they then persist for the remainder
of the session, proving the unit definitions can produce
durable sockets — something is wiping the directory once, shortly
after boot.

Today, six independent units each declare
`ExecStartPre=install -d -m 0700 -o 0 -g 0 /run/user/0` with no shared
owner (`guest/profiles/rocknix-guest-base.nix` ×1,
`guest/modules/audio.nix` ×3, `guest/profiles/main-space.nix` ×1,
`guest/profiles/dev-env.nix` ×1) and no `RuntimeDirectory=` declaration
anywhere in `guest/`. The host nspawn unit explicitly does NOT bind
anything into `/run/user/0/` (`patches/rocknix/0006-...patch`
contains a load-bearing `# NO /run/0-runtime-dir bind` comment), so
the race is guest-internal — default NixOS `systemd-logind` and its
`user-runtime-dir@0.service` template are the leading suspects. The
2026-05-08 Layer 14 cold-boot learning records that
`pam_systemd` does not function inside this nspawn guest, so any
`/run/user/<uid>` lifecycle that depends on real logind user sessions
is broken by construction here.

The downstream blast radius is documented in the moonlight-embedded
sobo substrate notes (2026-05-22): SDL2 audio init fails →
moonlight-embedded tears down the whole video stream within
milliseconds → user sees a green-frame window. The korri repo
currently carries `TEMP-set-sobo-volume-20.sh`, which restarts the two
audio units to paper over the symptom; the moonlight-embedded
launchers carry `MOONLIGHT_AUDIO_GATE=0` / `SDL_AUDIODRIVER=dummy` as
a parked workaround. Both want to retire once `/run/user/0/` is owned
and the sockets survive.

---

## Requirements

- R1. After a cold boot of sobo, `/run/user/0/pipewire-0` and
  `/run/user/0/pulse/native` are present and stay present across at
  least a 5-minute soak, without any manual `systemctl restart` of
  the audio units.
- R2. `XDG_RUNTIME_DIR=/run/user/0 wpctl status` succeeds from inside
  the guest at boot + 30 s, boot + 60 s, and boot + 5 min, with at
  least one non-dummy ALSA sink discovered (the unchanged baseline
  established by the 2026-05-13 dummy-sink learning).
- R3. Exactly one unit (the new owner) creates `/run/user/<uid>`
  inside the guest. No `main-space-*` consumer keeps its ad-hoc
  `ExecStartPre=install -d /run/user/0`.
- R4. Every consumer that previously assumed `/run/user/0` exists
  (`main-space-session-dbus`, `main-space-pipewire`,
  `main-space-pipewire-pulse`, `main-space-wireplumber`,
  `main-space-sway-kiosk` in both main-space and dev-env profiles)
  declares an explicit ordering dependency on the new owner.
- R5. The owner unit is parameterized on a single UID value
  (default `0`), so a future Korri downstream switch to a non-root
  kiosk user is a single configuration change, not a topology
  rewrite.
- R6. `guest/scripts/static-checks.sh` asserts the new shape
  (single owner declared, no remaining per-unit `install -d`,
  consumers ordered against the owner) so a future refactor cannot
  silently regress.
- R7. The dev-env profile's `main-space-sway-kiosk.service` no longer
  orders after `multi-user.target` (audit gap surfaced while
  enumerating consumers; the static-check assertion already forbids
  this for the main-space copy).
- R8. The layer-14 main-space contract (`docs/contracts/layer14-main-space-contract.md`)
  records that ROCKNIX-substrate-owned `XDG_RUNTIME_DIR=/run/user/<uid>`
  is now produced by a named substrate-owned unit, so downstream
  Korri composition knows what to depend on.

---

## Scope Boundaries

- Not migrating the kiosk to a non-root uid. Kiosk stays as uid 0;
  R5 only requires the design to support a future migration.
- Not patching `work/rocknix/` upstream. If diagnosis (U1) shows the
  wipe is host-side, the fix still lives in `guest/` and works around
  substrate behavior rather than upstreaming a patch.
- Not changing PipeWire / WirePlumber / PulseAudio configuration, UCM
  routing, bluez behavior, sink routing, or the `audioServiceEnvironment`
  triplet contents. Only the `/run/user/<uid>` lifecycle changes.
- Not changing host nspawn boundaries or `/run/.guest-udev` staging.
- Not re-investigating the dummy-sink failure mode covered by
  `docs/solutions/runtime-errors/guest-pipewire-dummy-sink-missing-udev-sound-records-rocknix-2026-05-13.md`.
  That bug is unrelated and already fixed; this plan only touches the
  socket-disappearance bug the 2026-05-22 moonlight-embedded doc
  misattributes to it.

### Deferred to Follow-Up Work

- Delete `TEMP-set-sobo-volume-20.sh` from the korri repo (separate
  PR in `simonwjackson/korri` after the next nix-on-rocks bump in
  `mountainous`).
- Flip `MOONLIGHT_AUDIO_GATE` back to its enabled default and drop
  the `SDL_AUDIODRIVER=dummy` gate from
  `guest/launchers/start_moonlight_embedded_gamescope.sh` and the
  moonlight remote runner (separate PR here once R1–R2 hold for ≥1
  week of real-use soak).
- Migrate kiosk to a non-root uid. Follow-up scope; this plan only
  unblocks it.
- Capture a `docs/solutions/runtime-errors/` learning when the fix
  lands and correct the 2026-05-22 misattribution. The plan's
  Documentation Plan section names the file; `se-compound` is the
  skill that authors it after the fix is verified, not during
  this work.

---

## Context & Research

### Relevant Code and Patterns

- `guest/modules/audio.nix` — three `main-space-pipewire*` /
  `main-space-wireplumber` services, each with their own
  `ExecStartPre=install -d ... /run/user/0` and the shared
  `audioServiceEnvironment` constant.
- `guest/profiles/rocknix-guest-base.nix` —
  `main-space-session-dbus.service` (the current de-facto session
  anchor; `Before=main-space-sway-kiosk.service korri-kiosk.service`).
  Natural home for the new owner unit so downstream Korri kiosks
  inherit it by importing `rocknix-guest-base`.
- `guest/profiles/main-space.nix` — `main-space-sway-kiosk.service`
  with its own `install -d`; ordering rule asserted by static checks
  (must NOT order after `multi-user.target`).
- `guest/profiles/dev-env.nix` — sibling profile with a duplicated
  `main-space-sway-kiosk.service` definition. Currently includes
  `after = [ "multi-user.target" "systemd-user-sessions.service" ]`;
  same rule must apply.
- `guest/modules/lid.nix:383-388` — the only existing
  `services.logind.settings.Login` site (lid/power-key ignores).
  Logical home for any new `services.logind` knobs the fix needs
  (`KillUserProcesses`, `RemoveIPC`) so logind config stays
  consolidated.
- `guest/modules/input.nix` — establishes the "compose two compositor
  owners" idiom (`before = [ "main-space-sway-kiosk.service"
  "korri-kiosk.service" ]`). The new owner unit follows the same
  shape.
- `guest/scripts/static-checks.sh` — every structural invariant in
  this repo lands here as `grep -q '<substring>' || fail "..."` /
  `! grep -q ... || fail "..."`. Existing audio block ends around
  the `! grep -q 'module-alsa-sink'` line.
- `docs/contracts/layer14-main-space-contract.md:172` — names
  `XDG_RUNTIME_DIR=/run/user/0` as a substrate invariant; needs a
  one-line addition about which unit owns the directory.

### Institutional Learnings

- `docs/solutions/best-practices/rocknix-layer14-main-space-cold-boot-autostart-2026-05-08.md`
  — establishes the invariant that PAM/logind user sessions do not
  function inside this nspawn guest. The fix design must NOT assume
  `user-runtime-dir@.service` will be triggered by a real login.
- `docs/solutions/runtime-errors/guest-pipewire-dummy-sink-missing-udev-sound-records-rocknix-2026-05-13.md`
  — closest prior PipeWire diagnosis on this stack. Different failure
  mode (dummy sink vs. missing socket); preserves the
  `XDG_RUNTIME_DIR=/run/user/0` /
  `PULSE_SERVER=unix:/run/user/0/pulse/native` env contract
  verbatim — this plan must too.
- `docs/solutions/integration-issues/moonlight-embedded-sobo-substrate-2026-05-22.md`
  — surfaces the present bug; misattributes it to the 2026-05-13
  dummy-sink doc. Correcting the misattribution is in the deferred
  compound learning, not this plan.
- `docs/solutions/runtime-errors/rocknix-layer10-stale-running-state-2026-05-06.md`
  — verification posture: liveness of a unit is not proof its contract
  is alive. Acceptance must check `test -S` on the sockets, not just
  `systemctl is-active`.

### External References

External research was not dispatched. The fix is bog-standard systemd
runtime-directory ownership in a documented-invariant nspawn
environment; local patterns and the systemd documentation already in
the user's working knowledge are sufficient.

---

## Key Technical Decisions

- **Owner home: `guest/profiles/rocknix-guest-base.nix`** (not a new
  module). The profile already owns `main-space-session-dbus.service`
  as the session-anchor primitive; the runtime-dir owner is a closely
  related anchor and gains no value from a separate module. Korri
  inherits it by importing `nixosModules.rocknix-guest-base`.
- **Owner shape: a `systemd.tmpfiles.rules` entry plus a thin
  `main-space-runtime-dir.service` oneshot anchor** (not
  `RuntimeDirectory=` on each consumer, not a `@.service` template
  yet).
  - `tmpfiles.rules` creates `/run/user/<uid>` at early boot with
    `0700 <uid> <uid>` and persists for the lifetime of the boot —
    matches the "no logind session" invariant.
  - A `Type=oneshot RemainAfterExit=yes` service is the anchor
    consumers `After=`/`Requires=` against; the tmpfiles rule alone
    has no unit name for ordering.
  - This shape avoids `RuntimeDirectory=user/<uid>` on each consumer
    — systemd would attempt to remove the directory whenever the
    last referencing unit stopped (modulo `RuntimeDirectoryPreserve=yes`
    everywhere), and any inconsistency across the six consumers would
    reintroduce the same class of bug.
- **UID parameterization via a single NixOS option** at
  `rocknix.session.runtimeDir.uid` (default `0`), defined alongside
  the new owner unit in `rocknix-guest-base.nix`. The
  `audioServiceEnvironment` triplet in `guest/modules/audio.nix`
  reads the same option to build `XDG_RUNTIME_DIR=/run/user/${uid}`,
  so a future Korri override is one assignment. Not a `@.service`
  template — only one uid is live at a time and the template form
  adds complexity without enabling anything today.
- **Logind interaction is diagnosis-gated.** U1 captures cold-boot
  evidence (`auditctl` / `inotifywait` on `/run/user/0/`, journal,
  `mount`) to disambiguate "logind tears it down" vs. "substrate
  tmpfiles re-creates it" vs. "transient pam_systemd session
  closes". The default plan assumption: set
  `services.logind.settings.Login = { KillUserProcesses = "no";
  RemoveIPC = "no"; }` and rely on the tmpfiles entry to win the
  ordering race; mask `user-runtime-dir@.service` only if U1 shows
  logind actively wiping the directory.
- **Drop, don't keep, the per-unit `ExecStartPre=install -d
  /run/user/0` lines.** Six redundant creators are a candidate root
  cause in their own right (any one of them recreating the directory
  after a wipe re-races the next wipe). The new owner is the single
  source of truth.
- **dev-env audit gap fixed in the same change** that touches its
  kiosk service (one extra line edit, removes the static-check
  divergence between the two profiles, costs nothing to do now).
- **Korri rebuild is the deploy path.** Live iteration on sobo is
  fine for U1 evidence and U2/U3 prototype validation, but the final
  shipped artifact reaches sobo only when Korri rebuilds its rootfs
  importing the updated `nixosModules.rocknix-guest-base`. The plan
  documents this in U6 verification.

---

## Open Questions

### Resolved During Planning

- **Kiosk stays as uid 0 today; design must allow mechanical
  non-root migration.** Resolved with the user before research.
- **External research?** Skipped — the fix is documented-systemd
  territory and the codebase already shows the absent-pattern shape
  the fix needs.

### Deferred to Implementation

- **Exact logind treatment** — `KillUserProcesses=no` /
  `RemoveIPC=no` only, or also mask `user-runtime-dir@.service`, or
  disable `services.logind` entirely. Resolved by U1's evidence run
  on sobo; plan default is the least invasive of those that work.
- **Whether `services.logind.settings.Login` lands in
  `rocknix-guest-base.nix` or extends the existing block in
  `guest/modules/lid.nix`.** Both work; preference is `lid.nix`
  (one logind-config site in the repo), but if U1 shows logind
  needs to be tied to runtime-dir lifecycle, `rocknix-guest-base.nix`
  is the colocated home. Decided in U4.
- **Whether the static-check assertions key on the new owner unit
  name as a literal substring** (cheap, brittle to rename) **or a
  regex permitting a follow-up rename to `main-space-user-runtime-dir`**.
  Plan default: literal substring matching the unit name chosen in
  U2.

---

## High-Level Technical Design

> *This illustrates the intended approach and is directional guidance
> for review, not implementation specification. The implementing
> agent should treat it as context, not code to reproduce.*

Topology of the new ordering, with the owner unit as the single
session-runtime-dir anchor every other main-space-* unit waits on:

```mermaid
graph TD
  tmpfiles[systemd-tmpfiles-setup.service<br/>creates /run/user/${uid}<br/>mode 0700, uid:uid]
  owner[main-space-runtime-dir.service<br/>Type=oneshot RemainAfterExit=yes<br/>anchor for After=/Requires=]
  dbus[main-space-session-dbus.service]
  pw[main-space-pipewire.service]
  pwp[main-space-pipewire-pulse.service]
  wp[main-space-wireplumber.service]
  sway[main-space-sway-kiosk.service]
  korri[korri-kiosk.service<br/>downstream]
  btn[main-space-hardware-button-handler.service]

  tmpfiles -->|After=| owner
  owner -->|Before=/After= consumer| dbus
  owner -->|Before=/After= consumer| pw
  pw --> pwp
  pw --> wp
  dbus --> sway
  dbus --> korri
  owner -->|Before=/After= consumer| sway
  owner -->|Before=/After= consumer| korri
  pw -.->|existing| btn
  wp -.->|existing| btn
```

Logind interaction (default plan posture, refined by U1):

```
default NixOS logind
  └── user-runtime-dir@0.service (template)
        ── neutralized by: KillUserProcesses=no + RemoveIPC=no
        ── (if U1 shows it actively wipes /run/user/0/: mask the
           template unit so logind never instantiates it)
```

---

## Implementation Units

### U1. Capture cold-boot evidence on sobo to fix logind-vs-substrate ambiguity

**Goal:** Disambiguate which actor wipes `/run/user/0/` shortly after
boot — default NixOS logind via `user-runtime-dir@0.service`, a
ROCKNIX substrate tmpfiles/oneshot, or a transient `pam_systemd`
session — so U2's owner unit and U4's logind treatment are chosen
against evidence, not guess. This unit produces a diagnosis note,
not a code change.

**Requirements:** Informs R1, R3, R4 (settles which actor U2 must
defeat).

**Dependencies:** None. Live access to sobo via `ssh root@sobo -p 2222`.

**Files:**
- Create: `docs/thinking/SM8550/2026-05-24-main-space-runtime-dir-wipe-trace.md`
  (capture journal excerpts, `mount` output, `auditctl` / `inotifywait`
  trace, and a one-paragraph verdict).

**Approach:**
- Cold-boot sobo. Within the boot window, capture:
  - `journalctl -b --grep='user-runtime-dir|pam_systemd|/run/user/0|main-space-pipewire'`
  - `mount | grep run/user` (to confirm whether `/run/user/0` is a
    tmpfs mount or a plain directory inside the guest's mount
    namespace).
  - `inotifywait -m -r /run/user/0/` started as early as possible
    after multi-user.target, run for ≥2 minutes.
  - `systemctl list-units '*user-runtime-dir*'` and
    `systemctl status user-runtime-dir@0.service` if present.
  - The exact `ss -lxn | grep -E 'pipewire|pulse'` vs. `ls
    /run/user/0/` discrepancy at the moment it manifests.
- Write a one-paragraph verdict naming the responsible actor and
  the system-call sequence that wipes the directory (rmdir, umount,
  fresh tmpfs mount over the existing dir, etc.).
- Confirm the verdict explains the "processes alive, sockets gone"
  fingerprint — if it doesn't, repeat with broader tracing
  (`bpftrace` on `inode_unlink` / `do_mount`) before continuing.

**Execution note:** Diagnosis-first. Do not skip to U2 with a guess —
the choice between "set logind knobs" and "mask `user-runtime-dir@.service`"
depends on this verdict, and getting it wrong delays the next
recovery.

**Patterns to follow:**
- `docs/thinking/SM8550/` already holds device-specific evidence
  notes; match the existing date-prefixed kebab-slug shape.
- The 2026-05-13 dummy-sink doc's `## Fast Diagnosis` section is the
  style template — one command block per check, no prose explaining
  what each command does beyond a single line of context.

**Test scenarios:**
- Test expectation: none — this unit produces evidence, not code or
  behavior. Verification is "the verdict identifies a single
  responsible actor and explains the fingerprint."

**Verification:**
- A markdown note exists at the path above containing: the trace
  excerpts, the responsible-actor verdict, and a recommendation
  paragraph that tells U2 whether the default plan posture
  (tmpfiles + oneshot anchor + `KillUserProcesses=no` /
  `RemoveIPC=no`) is sufficient or U4 must mask
  `user-runtime-dir@.service`.

---

### U2. Add the `/run/user/<uid>` owner unit and the UID-parameterized option

**Goal:** Introduce exactly one substrate-owned creator of
`/run/user/<uid>` inside the guest, parameterized on a single UID
value so a future non-root migration is mechanical.

**Requirements:** R3, R5, R8.

**Dependencies:** U1 (its verdict refines the implementation, but
the default plan posture is implementable without waiting if U1
confirms the default).

**Files:**
- Modify: `guest/profiles/rocknix-guest-base.nix`
  - Declare `options.rocknix.session.runtimeDir.uid = mkOption {
    type = types.int; default = 0; ... }`.
  - Add `systemd.tmpfiles.rules = [ "d /run/user/${toString cfg.uid}
    0700 ${toString cfg.uid} ${toString cfg.uid} -" ]`.
  - Add `systemd.services.main-space-runtime-dir` as `Type=oneshot`,
    `RemainAfterExit=yes`, `User=root`, `wantedBy = [
    "multi-user.target" ]`, with an `ExecStart=` that idempotently
    verifies (not recreates) the directory — `${pkgs.coreutils}/bin/test
    -d /run/user/<uid>` or equivalent. The tmpfiles rule is the
    creator; this service is the ordering anchor.
  - Order existing `main-space-session-dbus.service` After=/Requires=
    the new owner (so U3's pattern is already set in this file).
- Modify: `docs/contracts/layer14-main-space-contract.md`
  - One-line addition near the existing
    `XDG_RUNTIME_DIR=/run/user/0` mention noting that the
    substrate-owned `main-space-runtime-dir.service` produces the
    directory.
- Test: assertions land in U5 (`guest/scripts/static-checks.sh`)
  rather than as separate unit tests; this is Nix configuration
  with no in-process test surface.

**Approach:**
- Use `mkIf cfg.enable` or equivalent only if needed; the option
  default of `uid = 0` is the live value and no enable gate is
  required.
- Keep the option name in the `rocknix.session.*` namespace (matches
  the contract language; no prior `rocknix.session.*` option exists,
  so this also opens that namespace deliberately).
- Owner unit name: `main-space-runtime-dir.service` (matches the
  `main-space-*` naming convention; no `@.service` template form
  today).
- The service body should NOT include `ExecStartPre=install -d
  /run/user/0` — that would defeat the point of replacing six such
  lines with one anchor. The tmpfiles rule is the creator.

**Execution note:** Apply U1's verdict before committing this unit's
exact `After=` / `Conflicts=` set. If U1 shows `user-runtime-dir@.service`
is the wiper, the owner unit needs `Conflicts=user-runtime-dir@0.service`
plus a corresponding mask in U4 — those edits land here in U2's
unit definition so the owner ships complete in one change.

**Patterns to follow:**
- `guest/modules/input.nix`'s tmpfiles rule (`c /dev/uinput ...`) for
  the tmpfiles syntax already in use here.
- `main-space-session-dbus.service`'s shape (already in this same
  file) for the systemd service shape — same `Type/User/Restart`
  posture, same `Before=` style for consumers.
- The 2026-05-23 steam runtime capsule plan's approach to introducing
  a new option in `rocknix.*` namespace, for the option-declaration
  shape.

**Test scenarios:**
- Happy path: with default `rocknix.session.runtimeDir.uid = 0`,
  `nix eval .#nixosConfigurations.<host>.config.systemd.services.main-space-runtime-dir`
  succeeds and the service's wantedBy includes `multi-user.target`.
- Happy path: tmpfiles rule renders to a string containing
  `d /run/user/0 0700 0 0` when uid is 0.
- Edge case: overriding `rocknix.session.runtimeDir.uid = 1000`
  re-renders to `d /run/user/1000 0700 1000 1000` and the service
  body references `/run/user/1000` consistently with no remaining
  hardcoded `/run/user/0`. Confirms the parameterization is real
  (covers R5).
- Edge case: a downstream profile setting the option to a non-default
  uid does not break the `main-space-session-dbus.service` ordering
  introduced in this unit.

**Verification:**
- `nix eval` of the new service and tmpfiles rule produces the
  expected strings for `uid = 0` and `uid = 1000`.
- `guest/scripts/static-checks.sh` (assertions added in U5) passes.
- The layer-14 contract diff is a single inline mention of the new
  unit; the rest of the contract is byte-identical.

---

### U3. Order consumers against the new owner and drop per-unit `install -d`

**Goal:** Make every consumer of `/run/user/<uid>` order explicitly
against `main-space-runtime-dir.service` and remove the six redundant
`ExecStartPre=install -d /run/user/0` lines.

**Requirements:** R3, R4, R7.

**Dependencies:** U2 (the owner unit must exist for `After=`/`Requires=`
to resolve).

**Files:**
- Modify: `guest/profiles/rocknix-guest-base.nix`
  (`main-space-session-dbus.service` — drop `ExecStartPre`; the
  `After=` was added in U2).
- Modify: `guest/modules/audio.nix`
  (three services: `main-space-pipewire`, `main-space-pipewire-pulse`,
  `main-space-wireplumber`. Drop `ExecStartPre` from each. Add
  `After = [ ... "main-space-runtime-dir.service" ]`,
  `Requires = [ ... "main-space-runtime-dir.service" ]` where
  appropriate. Update the `audioServiceEnvironment` triplet to read
  `XDG_RUNTIME_DIR = "/run/user/${toString config.rocknix.session.runtimeDir.uid}"`
  etc., so R5 holds.)
- Modify: `guest/profiles/main-space.nix`
  (`main-space-sway-kiosk.service` — drop `ExecStartPre`; add
  `After = [ ... "main-space-runtime-dir.service" ]`,
  `Requires = [ "main-space-session-dbus.service"
  "main-space-runtime-dir.service" ]`. Update the `environment` block's
  `XDG_RUNTIME_DIR` to use the option value.)
- Modify: `guest/profiles/dev-env.nix`
  (dev-env's `main-space-sway-kiosk.service` — same drop +
  `After=`/`Requires=` additions as main-space. Also fix the audit
  gap: remove `multi-user.target` from `after = [...]` so this matches
  the main-space rule already asserted by static checks; R7.)
- Test: assertions in U5; no in-process test surface.

**Approach:**
- Touch one file at a time, in dependency order:
  `rocknix-guest-base.nix` → `audio.nix` → `main-space.nix` →
  `dev-env.nix`. Each intermediate state should still be
  `nix flake check`-clean.
- Keep the `audioServiceEnvironment` triplet, the
  `PULSE_SERVER = "unix:/run/user/0/pulse/native"` static-check
  invariant (rendered string equals the same when uid=0), and the
  `environment.variables` system-wide export unchanged in shape —
  only the source of the uid value changes.
- The hardware-button handler in `lid.nix` already orders after the
  audio triplet; do NOT add another `After=` there. The existing
  chain (`button-handler After= pipewire / pipewire-pulse /
  wireplumber After= runtime-dir`) transitively enforces ordering.

**Execution note:** Verify the rendered `PULSE_SERVER` and
`XDG_RUNTIME_DIR` strings byte-for-byte against the existing
static-check invariant before committing. Changing the source of
the uid value must not change the rendered output when `uid = 0`.

**Patterns to follow:**
- The existing `audioServiceEnvironment` `let` block in
  `guest/modules/audio.nix` for the templated-env idiom.
- `guest/modules/input.nix`'s `before = [
  "main-space-sway-kiosk.service" "korri-kiosk.service" ]` for the
  multi-compositor ordering idiom (here we're on the After= side,
  but the shape is the same).

**Test scenarios:**
- Happy path: `nix eval .#nixosConfigurations.<host>.config.systemd.services.main-space-pipewire.serviceConfig`
  shows no `ExecStartPre` referencing `install -d /run/user/0`.
- Happy path: each of the six touched services has
  `main-space-runtime-dir.service` in its `After=` list.
- Happy path: the rendered `audioServiceEnvironment` for default
  `uid = 0` is byte-identical to the pre-change rendered value.
- Edge case: overriding the uid option to 1000 propagates into
  every consumer's `XDG_RUNTIME_DIR` / `PIPEWIRE_RUNTIME_DIR` /
  `PULSE_SERVER` env variable, with no `/run/user/0` literal
  surviving in any consumer's environment block (R5 trace).
- Integration: with U2 + U3 applied, `nix build --dry-run
  .#nixosConfigurations.<host>.config.system.build.toplevel`
  succeeds for both `main-space` and `dev-env` consumer profiles.

**Verification:**
- `guest/scripts/static-checks.sh` (with U5 assertions) passes.
- `git grep 'install -d.*/run/user/0' guest/` returns no results.
- `nix flake check --no-build` reports no evaluation errors.

---

### U4. Apply logind treatment per U1 verdict

**Goal:** Stop default NixOS logind from wiping or tmpfs-mounting
over `/run/user/<uid>` after the owner unit has created it.

**Requirements:** R1, R2 (the owner unit alone is necessary but may
not be sufficient — logind racing it is the leading suspect for the
original wipe).

**Dependencies:** U1 (verdict), U2 (owner unit exists to
order/conflict against).

**Files:**
- Modify (default posture): `guest/modules/lid.nix`
  (extend the existing `services.logind.settings.Login` block with
  `KillUserProcesses = "no"; RemoveIPC = "no";` so logind keeps
  hands off the uid-0 runtime dir even if it transiently sees a
  session opening/closing).
- Possibly modify (only if U1 verdict says so): `guest/profiles/rocknix-guest-base.nix`
  (add `systemd.units."user-runtime-dir@.service".enable = false;`
  or equivalent masking knob to neutralize the wiper directly).

**Approach:**
- Start with the least invasive setting (the lid.nix extension). If
  U1's evidence shows logind actively unlinking the sockets or
  tmpfs-mounting after the owner runs, escalate to masking
  `user-runtime-dir@.service`.
- Do NOT disable `services.logind` entirely. The lid module already
  depends on logind's lid/power knobs being honored; disabling
  logind unrelated to this fix is out of scope and would break
  the hardware-button handler boundary.

**Execution note:** This is the unit most likely to need a second
pass after live testing. Build in a fast iteration loop on sobo:
edit `lid.nix` (or `rocknix-guest-base.nix`), rebuild rootfs
in-place, `systemctl daemon-reload`, cold-boot, run U6's soak
check. Expect 1–2 cycles.

**Patterns to follow:**
- The existing `services.logind.settings.Login = { HandleLidSwitch =
  "ignore"; ... }` block in `lid.nix:383-388` for the settings shape.
- Static-check assertion style (positive grep) for the new knobs
  added by this unit; U5 handles the assertions.

**Test scenarios:**
- Happy path: with the lid.nix extension applied,
  `systemctl show systemd-logind | grep -E 'KillUserProcesses|RemoveIPC'`
  reports `no` for both on a deployed sobo build.
- Edge case (only if U1 demanded masking): `systemctl status
  user-runtime-dir@0.service` reports the unit as masked, and an
  attempt to start it manually fails fast rather than wiping
  `/run/user/0/`.
- Integration: the full chain (`main-space-runtime-dir.service`
  Active → `main-space-pipewire.service` Active → socket present
  → still present after 5 min) holds on cold boot. Covered in U6,
  measured here as "the U6 soak check passes after this unit's
  treatment is in place."

**Verification:**
- After applying this unit's edits and rebooting sobo,
  `ls /run/user/0/` shows `pipewire-0` and `pulse/native` continuously
  for ≥5 minutes with no `systemctl restart` intervention.

---

### U5. Lock the new shape into `guest/scripts/static-checks.sh`

**Goal:** Codify the new invariants so a future refactor cannot
silently regress to per-unit `install -d` racing.

**Requirements:** R6, R7.

**Dependencies:** U2, U3, U4 (assertions can only be added after the
shape they assert is in place).

**Files:**
- Modify: `guest/scripts/static-checks.sh`
- Test: this file IS the test surface; no separate test file.

**Approach:**
- Positive assertions:
  - `systemd.services.main-space-runtime-dir` exists in
    `guest/profiles/rocknix-guest-base.nix`.
  - `systemd.tmpfiles.rules` referencing `/run/user/` is present in
    `guest/profiles/rocknix-guest-base.nix`.
  - `options.rocknix.session.runtimeDir.uid` (or the chosen final
    option path) is declared in
    `guest/profiles/rocknix-guest-base.nix`.
  - Each of `modules/audio.nix`, `profiles/rocknix-guest-base.nix`,
    `profiles/main-space.nix`, `profiles/dev-env.nix` contains the
    string `main-space-runtime-dir.service` in an `After=` or
    `Requires=` context.
  - The dev-env audit-gap fix: assert the same
    `! grep -q 'after = \[ "multi-user.target"'`-style rule that
    already exists for `main-space.nix`, applied to `dev-env.nix`'s
    `main-space-sway-kiosk` service (R7).
- Negative assertions:
  - `! grep -q 'install -d.*-m 0700.*-o 0.*-g 0.*/run/user/0'`
    across the four touched files (rocknix-guest-base, audio,
    main-space, dev-env) plus a recursive guest catch-all. One
    assertion per file or catch-all, matching existing assertion
    style.
  - `! grep -q 'ExecStartPre.*/run/user/0'` on the same file set.
- Preserve the existing `PULSE_SERVER = "unix:/run/user/0/pulse/native"`
  invariant (it must still render correctly with `uid = 0`).

**Execution note:** Run the static-checks script after each
assertion added, to catch typos in the assertion grep patterns
themselves (the script's failure surface is "grep didn't match
anything we thought it would," which silently passes only when
the regex matches existing literal source).

**Patterns to follow:**
- Existing assertion blocks in `guest/scripts/static-checks.sh` for
  `audio.nix` (positive checks) and the
  `! grep -q 'module-alsa-sink'` style (negative checks). Group
  the new assertions with the audio block.

**Test scenarios:**
- Happy path: with U2/U3/U4 applied, `bash guest/scripts/static-checks.sh`
  exits 0.
- Edge case: revert any one of the changes from U2/U3/U4 (e.g.,
  reintroduce an `ExecStartPre=install -d /run/user/0` line in
  `audio.nix`); the static-check script exits non-zero with the
  expected failure message naming the violated invariant.
- Edge case: rename `main-space-runtime-dir.service` to anything
  else; positive assertions fail fast with a clear message.

**Verification:**
- `bash guest/scripts/static-checks.sh` exits 0 after U2/U3/U4 are
  applied.
- Manually editing the source to reintroduce any of the dropped
  `install -d` lines reproduces a failure with a recognizable
  message.

---

### U6. Sobo soak verification and acceptance note

**Goal:** Prove the fix holds on cold boot, warm restart, and a
5-minute idle soak; record the evidence so a future regression has
something to compare against.

**Requirements:** R1, R2.

**Dependencies:** U2, U3, U4, U5. Requires a Korri rootfs rebuild
that imports the updated `nixosModules.rocknix-guest-base`, or a
fast-iteration in-place edit on sobo with `systemctl daemon-reload`.

**Files:**
- Create: `docs/acceptance/main-space-pipewire-runtime-dir-sobo-2026-05-XX.md`
  (record the cold-boot + soak evidence).

**Approach:**
- Build the artifact path that reaches sobo:
  - Fast loop: edit the rootfs in place on sobo, `systemctl
    daemon-reload`, `systemctl restart main-space-runtime-dir
    main-space-session-dbus main-space-pipewire{,-pulse}
    main-space-wireplumber main-space-sway-kiosk`.
  - Shipped artifact: rebuild Korri's product rootfs importing the
    updated `nixosModules.rocknix-guest-base`, deploy via the
    normal nix-on-rocks-bump → mountainous → sobo pipeline.
- Soak procedure on sobo (`ssh root@sobo -p 2222`):
  - Cold boot. At boot + 30 s: `test -S /run/user/0/pipewire-0 &&
    test -S /run/user/0/pulse/native` (both must hold).
  - At boot + 60 s: same test plus `XDG_RUNTIME_DIR=/run/user/0
    wpctl status` returns successfully and lists ≥1 non-dummy ALSA
    sink.
  - At boot + 5 min: re-run both checks.
  - Warm cycle: `systemctl restart main-space-runtime-dir` and
    confirm the dependent units stay healthy or restart cleanly.
- Capture into the acceptance note:
  - The exact commands and their full outputs.
  - Snippet from `journalctl -u main-space-runtime-dir.service -b`.
  - One paragraph confirming the moonlight green-frame symptom no
    longer reproduces with `MOONLIGHT_AUDIO_GATE` flipped back on
    (do this validation, but do not commit the gate flip in this
    plan; it's a separate PR per the Scope Boundaries).

**Execution note:** Liveness is not the contract. Every check uses
`test -S` on socket paths, not `systemctl is-active`, per the Layer
10 stale-running-state learning.

**Patterns to follow:**
- Recent `docs/acceptance/*-sobo-2026-05-23.md` entries for the
  acceptance-note shape (problem statement, command + output blocks,
  pass/fail verdict, soak duration).

**Test scenarios:**
- Happy path: cold boot, sockets present at +30 s / +60 s / +5 min,
  `wpctl status` healthy, ≥1 non-dummy sink. Covers R1, R2.
- Edge case: `systemctl restart main-space-runtime-dir.service`
  while the kiosk is running — sockets remain present (the oneshot
  + tmpfiles design preserves the directory through the restart).
- Failure path: if U4's default treatment was insufficient and
  sockets disappear during soak, the acceptance note records the
  failure, U4 is reopened, and the soak repeats. Do not mark the
  acceptance note pass until ≥1 5-minute soak survives unmodified.
- Integration: a launch of moonlight-embedded with audio gating
  flipped back on (`MOONLIGHT_AUDIO_GATE=1`, no
  `SDL_AUDIODRIVER=dummy`) completes its handshake and streams
  video for ≥30 s without the green-frame symptom.

**Verification:**
- Acceptance note exists, contains the three soak-window
  observations, and reports pass.
- The plan's frontmatter `status:` flips from `active` to
  `completed` only after this verification.

---

## System-Wide Impact

- **Interaction graph:** `main-space-runtime-dir.service` becomes
  the new most-upstream dependency in the main-space session graph,
  before `main-space-session-dbus.service`. Hardware-button handler
  in `lid.nix` is transitively ordered behind it via its existing
  `After=` on the audio triplet. The Korri-owned
  `korri-kiosk.service` is implicitly ordered the same way through
  its existing `After=main-space-session-dbus.service`; the new
  owner sits in front of dbus, so no Korri-side change is required.
- **Error propagation:** If the new owner unit fails (e.g., tmpfiles
  rule can't render because the option's uid is invalid), all five
  consumers refuse to start with a clear `Requires=` failure rather
  than starting and silently producing missing sockets later.
  Failure mode flips from "alive but broken" to "fails fast at
  boot" — strictly better diagnostic posture.
- **State lifecycle risks:** `/run/user/<uid>` no longer disappears
  mid-boot. Existing partial-write or cache concerns are unchanged
  — the directory's contents (sockets, sway-ipc, wayland-1) are
  owned by their respective services as before; only the directory's
  parentage changes.
- **API surface parity:** The `audioServiceEnvironment` rendered
  strings (`XDG_RUNTIME_DIR`, `PULSE_SERVER`, etc.) are byte-identical
  when `uid = 0`. The layer-14 contract's substrate-invariant clause
  (`XDG_RUNTIME_DIR=/run/user/0`) holds; the contract gets one
  sentence of clarification about ownership.
- **Integration coverage:** Cross-layer scenario the static check
  alone won't prove — moonlight-embedded streaming with audio
  enabled completing handshake on sobo. Covered in U6 integration
  scenario.
- **Unchanged invariants:** All existing
  `services.pipewire.{enable,alsa,pulse,wireplumber}` toggles,
  the `audioServiceEnvironment` triplet shape and contents,
  `services.dbus.enable`, `hardware.bluetooth` configuration,
  the lid module's hardware-button handler, the
  `main-space-session-dbus.service` definition body, the
  layer-14 contract's substrate ownership list. Korri does not need
  to change anything to consume the new shape; importing
  `nixosModules.rocknix-guest-base` inherits the new owner unit
  automatically.

---

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| U1's evidence is ambiguous (e.g., both logind and a substrate tmpfiles fire, hard to tell which is decisive). | Broaden tracing (`bpftrace` on `inode_unlink` / `do_mount` per U1 execution note) before guessing. The cost of one extra evidence cycle is far smaller than the cost of an under-treated fix that re-races silently. |
| `services.logind` settings interact with the lid module's existing logind config in unexpected ways. | The new knobs (`KillUserProcesses`, `RemoveIPC`) are independent of the lid/power knobs already set in `lid.nix`. U6 validates lid behavior (sleep, wake, power button) is unchanged. |
| Korri rootfs rebuild is needed to deploy the fix to sobo, lengthening the iteration loop. | Use the fast in-place edit + `systemctl daemon-reload` loop for U1–U4 prototyping; only the final acceptance soak in U6 needs a real Korri rootfs. |
| Renaming `main-space-runtime-dir.service` later breaks static-check assertions added in U5. | The assertions use literal substrings (cheapest, brittlest by design). A rename is a deliberate operation that the assertion failures will surface immediately, with the message pointing at exactly the lines to update. |
| Option name `rocknix.session.runtimeDir.uid` opens a new `rocknix.session.*` namespace that future work might want to populate differently. | Namespace is deliberate (matches the contract language). If a follow-up needs a different shape, refactoring this single option is a one-grep change. |
| `RemoveIPC = "no"` retains SysV IPC across sessions in environments where this matters. | The kiosk has no SysV IPC consumers. Documented in U4 as an accepted side effect. |

---

## Documentation Plan

- `docs/contracts/layer14-main-space-contract.md`: one-line addition
  in the substrate-invariant paragraph, naming
  `main-space-runtime-dir.service` as the owner of
  `/run/user/<uid>`. Edited inline as part of U2.
- `docs/thinking/SM8550/2026-05-24-main-space-runtime-dir-wipe-trace.md`:
  diagnostic evidence note created in U1.
- `docs/acceptance/main-space-pipewire-runtime-dir-sobo-2026-05-XX.md`:
  acceptance soak note created in U6.
- **Deferred to follow-up (compound learning):**
  `docs/solutions/runtime-errors/guest-main-space-pipewire-runtime-dir-socket-vanish-rocknix-2026-05-XX.md`,
  to be authored by `se-compound` after this plan completes.
  Should correct the 2026-05-22 moonlight-embedded substrate doc's
  misattribution to the 2026-05-13 dummy-sink learning.

---

## Operational / Rollout Notes

- **Live iteration on sobo** during U2–U4 uses the fast in-place
  edit + `systemctl daemon-reload + restart` loop. No rootfs rebuild
  needed for the diagnose-design-verify cycle.
- **Shipped artifact** reaches sobo only when Korri rebuilds its
  product rootfs importing `nixosModules.rocknix-guest-base`.
  Sequence after this plan lands in nix-on-rocks:
  1. Bump `nix-on-rocks-guest` input in
     `simonwjackson/mountainous` flake (`hosts/sobo/default.nix`
     imports the module).
  2. Korri rebuilds + deploys.
  3. Sobo cold-boot validation reruns the U6 acceptance soak on
     the deployed artifact.
  4. After ≥1 week of clean soak, the deferred PRs land
     (delete `TEMP-set-sobo-volume-20.sh` in korri; flip
     `MOONLIGHT_AUDIO_GATE` back to default and remove
     `SDL_AUDIODRIVER=dummy` from moonlight launchers).
- **Rollback**: revert the merge in nix-on-rocks; Korri's next
  rebuild restores the previous shape. The `TEMP-set-sobo-volume-20.sh`
  workaround in korri is untouched by this plan and remains
  available as a manual recovery if the deferred flip lands too
  early.

---

## Sources & References

- Handoff context (no prior brainstorm doc): scope and root-cause
  hypothesis carried in from the prior session's handoff.
- Related code: `guest/modules/audio.nix`,
  `guest/profiles/rocknix-guest-base.nix`,
  `guest/profiles/main-space.nix`,
  `guest/profiles/dev-env.nix`,
  `guest/modules/lid.nix`,
  `guest/scripts/static-checks.sh`,
  `docs/contracts/layer14-main-space-contract.md`.
- Host nspawn substrate (read-only context): `patches/rocknix/0006-rocknix-guest-substrate.patch`.
- Related learnings:
  - `docs/solutions/best-practices/rocknix-layer14-main-space-cold-boot-autostart-2026-05-08.md`
  - `docs/solutions/runtime-errors/guest-pipewire-dummy-sink-missing-udev-sound-records-rocknix-2026-05-13.md`
  - `docs/solutions/integration-issues/moonlight-embedded-sobo-substrate-2026-05-22.md`
  - `docs/solutions/runtime-errors/rocknix-layer10-stale-running-state-2026-05-06.md`
- Adjacent recent plans (for refactor / runtime-dir / option-namespace
  precedent):
  - `docs/plans/2026-05-23-003-refactor-steam-runtime-capsule-plan.md`
  - `docs/plans/2026-05-11-002-refactor-sm8550-guest-owned-audio-plan.md`
    (referenced; in-repo path may differ — research surfaced it as
    the audio-policy-into-guest move).
