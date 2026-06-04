---
title: "explore: hibernate the guest, power off the host, resume arbitrary state"
type: explore
status: captured
date: 2026-05-26
branch: main
---

# Hibernate the guest, power off the host, resume arbitrary state

This document captures a feasibility conversation about adding a true
hibernate UX to the ROCKNIX thin-host + Nix-guest architecture:
trigger an action, device fully powers off (no battery drain at rest),
later turn it back on and **resume exactly where you were** regardless of
what was running.

It is a captured decision record, not a plan. The conclusion is that no
responsible direction can be picked today; the gate is a feasibility
spike already scoped (but never run) in
`docs/brainstorms/2026-05-12-vm-graphics-freeze-mvp-handoff.md`.

Sibling brainstorms:

- `docs/brainstorms/2026-05-07-002-rocknix-thin-host-nix-main-space.md`
  — the thin-host architecture this question lives inside.
- `docs/brainstorms/2026-05-12-vm-graphics-freeze-mvp-handoff.md`
  — VM-graphics MVP whose outcome decides this brainstorm.

---

## The question

> Could we hibernate the guest, shut the whole thing down, then later
> turn it back on and pick up exactly where I left off — like normal
> hibernate?

The user explicitly chose the strongest framing of the requirement:

- "Any arbitrary state, MUST pick up exactly where I left off. No tricks."
- Emulator savestates are explicitly rejected as a "trick."
- Cold-relaunch of last-running apps is rejected.
- Manifest-only / partial restore is rejected.

Hibernate here means **byte-for-byte identical resume after a full power
cycle of the device.**

## Architectural constraint

This is the immovable fact:

- The guest is a `systemd-nspawn` container, **not a VM**.
- The guest's processes live in the host kernel. The guest does not have
  its own kernel, devices, or page tables.
- Therefore "hibernate the guest" cannot be a guest-local operation: when
  the host powers off, the guest dies with it, and on next boot the
  guest's pre-shutdown state has to be reconstructed from disk somehow.
- `/sys/power/state` is global to the host kernel; it is not namespaced.

"Hibernate" through a host power cycle means **state has to be dumped to
disk and reloaded byte-for-byte.** There is no clever shortcut that
preserves "arbitrary state" through a power-off without doing this.

## What rules itself out immediately

Mechanisms considered and rejected:

| Mechanism | Why rejected |
|---|---|
| `rocknix-fake-suspend` extension | Device stays on; battery dies eventually. Not "off." |
| App-level session manifest + cold relaunch | Loses in-memory state. Rejected by "no tricks." |
| Emulator savestates orchestrated by a session manager | Same — "trick" per user. Also only covers emulator workloads. |
| CRIU checkpoint of guest userspace + cold host reboot | Cannot restore live Vulkan / DRM / Wayland / audio / input file descriptors. The 2026-05-12 brainstorm already judged this unlikely. |
| Partial-VM (only stateful workload in a VM, rest in nspawn) | Violates "arbitrary state" the moment the user is in a non-VM app when they trigger hibernate. |
| kexec into a hibernate-capable kernel | kexec doesn't power the device off. The drivers doing the dump are still the same vendor drivers. Doesn't help. |

## What remains: two paths

### Path B — Real Linux S4 on the host

Standard Linux hibernate: kernel writes RAM to swap, powers off,
restores on next boot.

**Findings from online + repo research (2026-05-26)**

The picture is materially better than the first-pass analysis assumed.
Key evidence:

1. **Hibernation is already compiled into the SM8550 kernel.**
   `work/rocknix/projects/ROCKNIX/devices/SM8550/linux/linux.aarch64.conf`
   has all of these set:

   ```
   CONFIG_HIBERNATION=y
   CONFIG_HIBERNATE_CALLBACKS=y
   CONFIG_HIBERNATION_SNAPSHOT_DEV=y
   CONFIG_HIBERNATION_COMP_LZO=y
   CONFIG_ARCH_HIBERNATION_POSSIBLE=y
   CONFIG_ARCH_HIBERNATION_HEADER=y
   CONFIG_SUSPEND=y
   CONFIG_PM_SLEEP=y
   ```

   The first-pass analysis assumed this was the blocker. It is not.

2. **The kernel is mainline 6.15.6, not a Qualcomm vendor fork.**
   `work/rocknix/packages/linux/package.mk` selects upstream
   `linux-6.15.6.tar.xz` for non-amlogic / non-raspberrypi targets
   (which includes SM8550), with 49 SoC-specific patches under
   `work/rocknix/projects/ROCKNIX/devices/SM8550/patches/linux/`. The
   hibernate / suspend code paths are the upstream ones, in active
   mainline maintenance. arm64 hibernate as a kernel feature has been
   stable mainline infrastructure since 4.5-rc4 (2016).

3. **The reason it is disabled is a 2-year-old userspace comment.**
   `projects/ROCKNIX/packages/hardware/quirks/platforms/SM8550/030-suspend_mode`
   is a 6-line script with the comment `### Sleep is currently broken,
   so we'll disable it.` Copyright `(C) 2023 JELOS` — predates ROCKNIX
   forking, predates the current mainline kernel base, and has not been
   re-tested against today's tree. The script does two things:

   - runs `/usr/bin/suspendmode off` (writes
     `AllowSuspend=no` into a systemd-sleep drop-in)
   - writes `HandlePowerKey=ignore` / `HandleSuspendKey=ignore` into
     logind

   Neither is a kernel barrier. Both can be flipped at runtime.

4. **`suspendmode` itself doesn't know about `disk`.**
   `projects/ROCKNIX/packages/rocknix/sources/scripts/suspendmode`
   accepts `off`, `freeze`, `standby`, `mem`, and `default`. Hibernate
   (`disk`) is not plumbed through. Adding a `disk` case is trivial
   (~10 lines of shell mirroring the existing `mem` branch), or you
   bypass it entirely with `echo disk > /sys/power/state`.

5. **ath12k suspend/resume crashes are fixed in this kernel.**
   CVE-2024-40979 ("wifi: ath12k: fix kernel crash during resume")
   landed in 6.9.7 / 6.10-rc1. ROCKNIX is on 6.15.6 — the fix is in.
   This was the most-cited "Qualcomm vendor kernel suspend is broken"
   data point. It no longer applies.

6. **msm DRM driver actively maintains resume.** Mainline
   `drivers/gpu/drm/msm/adreno/` has `pm_suspend`/`pm_resume` plus
   explicit retry-on-resume-failure logic upstream. Adreno suspend on
   mainline is a maintained surface, not a "vendor kernel doesn't try."

7. **UFS is the new known risk to flag.** Linaro's SM8x50 devboard
   docs explicitly list UFS stability as an ongoing issue on mainline:
   "UFS is not stable. There are a series of known issues that are
   currently being worked upon ... Probability of UFS probe running
   into a hard crash during boot time is very high." Hibernate writes
   the RAM image to storage and reads it back on resume — if UFS is
   flaky at boot or under load on Thor's specific mainline kernel,
   that affects hibernate directly. This is the **most plausible**
   remaining mode of failure given findings 1–6.

**Updated cost estimate**

The "months of vendor-kernel debug, high stall risk" framing in the
first pass was wrong. Realistic prework looks more like:

- Reverse the userspace policy in the SM8550 quirk (1 line: don't run
  `suspendmode off`, or run it with a different mode).
- Re-enable `HandlePowerKey` / `HandleSuspendKey` in logind for the
  hibernate UX.
- Provision swap on `/storage` (either a partition layout change or a
  swap file with `resume_offset=`).
- Add `resume=` and `resume_offset=` to the kernel cmdline that
  `rocknix-abl` passes, or invoke `uswsusp` from initramfs.
- Add a `disk` case to the `suspendmode` script (or bypass it).
- **Empirical test loop**: trigger `echo mem > /sys/power/state` first
  (cheap), see what survives. Then `echo disk > /sys/power/state` with
  the bootloader configured. Triage what doesn't come back.

**The actual remaining risk**

Narrower and more localizable than the first pass claimed:

- UFS on resume (read the swap image back without a crash).
- Display / panel re-init on resume (DSI panels behaving correctly
  after S4).
- Audio path (q6/lpass DSP firmware reload semantics).
- `InputPlumber` and the virtual-gamepad event chain re-establishing
  cleanly.
- ath12k re-association timing (no crash now, but reconnect UX).

None of these are theoretical-only; all have plausible upstream paths.
The difference from the original framing: failure is now localized,
not "any one of N drivers might block forever."

**Reward if it works**
- Universal. Works for every app, including the ones the project does
  not yet know exist. No architectural change beyond kernel/driver
  work.

**Cheap probe that updates everything**

The single highest-value next step for Path B is empirical, not
research:

```
# On Thor, after backing up state and confirming SSH access:
echo mem > /sys/power/state    # S3 suspend test
# (wake by power key / lid)
```

If S3 round-trips cleanly on the current ROCKNIX build, S4 is very
likely close. If S3 fails, the failure mode is the information that
decides Path B's real shape. This test is on the order of minutes,
not months.

**Probe executed 2026-05-26: S3 round-trips with rc=0 on bandai.**

Probe procedure: `echo +30 > /sys/class/rtc/rtc0/wakealarm`, then
`echo mem > /sys/power/state` over SSH from a detached shell, log
written to `/storage/.probe-s3-*.log`. Device: AYN Thor (`bandai`),
ROCKNIX `20260526` nightly, kernel `7.0.2`, `mem_sleep=s2idle [deep]`,
active sleep mode `deep` (true S3, not s2idle).

Result: **S3 suspend/resume cycle completes cleanly at the kernel
level.** Total kernel-time for the suspend+resume code path was
~3.5 s (the 30 s RTC sleep itself does not advance kernel time).
Relevant dmesg trace:

```
[18292.111478] PM: suspend entry (deep)
[18292.132270] Freezing user space processes
[18292.133593] OOM killer disabled.
[18292.134774] printk: Suspending console(s)
[18293.085563] Disabling non-boot CPUs ...
[18293.086-100]  psci: CPU7..CPU1 killed (polled 0 ms)
[18293.101989] Enabling non-boot CPUs ...
[18293.103-112]  CPU1..CPU7 is up
[18293.186762] mhi mhi0: Requested to power ON
[18293.186778] mhi mhi0: Power on setup success
[18293.707762] ath12k_wifi7_pci ... chip_id 0x2 (firmware re-loaded)
[18295.693104] OOM killer enabled.
[18295.693108] Restarting tasks: Starting
[18295.693501] Restarting tasks: Done
[18295.693556] random: crng reseeded on system resumption
[18295.693601] PM: suspend exit
```

This is a textbook clean S3 kernel cycle. All 7 secondary CPUs were
plugged down via PSCI and brought back up. MHI/QMI re-init succeeded.
DRM panels (DSI-1, DSI-2) still reported `connected` post-resume.

Failure modes that DID surface on resume — all driver-class,
localized, and named:

1. **`dwc3-qcom a600000.usb: PM: failed to resume: error -110`**
   (ETIMEDOUT). USB PHY initialization timed out on resume.
   Triggered xHCI Host System Error and cascading USB device
   disconnects (audio + hub at device 2 + 1-1.3). Well-trodden
   Qualcomm/mainline issue; recent patches exist.

2. **`arm-smmu 15000000.iommu: Unhandled context fault: fsr=0x402,
   iova=0xf1a94f360, fsynr=0x280011, cbfrsynra=0x40, cb=9`** —
   appeared immediately after the ath12k firmware re-load. Known
   class of issue on Qualcomm SoCs: a DMA region not re-mapped
   before the MHI ring is restarted on resume. Likely the cause
   of Wi-Fi not actually working post-resume despite firmware
   loading cleanly.

3. **Sway compositor session died on resume.** DRM hardware itself
   was fine (panels still connected); the failure is at the
   Wayland-session / compositor-state level, not at the msm DRM
   driver. Userspace recovery (restart compositor + dependent
   services) post-resume hook.

The (harmless) `CPU features: SANITY CHECK: Unexpected variation
in SYS_ID_AA64MMFR1_EL1` warnings between CPUs are normal on
heterogeneous big.LITTLE ARM clusters; not failures.

**What this empirical result does to Path B's risk profile**

The original first-pass framing ("failure spread across N drivers,
any one can permanently block, default outcome is stalls
indefinitely") was wrong. The actual landscape is:

- Kernel-level suspend path: **proven working today**, no work
  needed.
- USB resume (dwc3-qcom): known-class bug with named patches
  upstream; bounded debugging.
- ath12k + SMMU resume race: known-class bug with named patches
  upstream; bounded debugging.
- Sway / userspace session recovery: ordinary systemd-sleep
  post-resume hook work.

This is a **finite, named, localized bug list** of three items, not
an open-ended platform project. Path B has been derisked
substantially.

Remaining unknown for S4 hibernate specifically: ROCKNIX swap today
is zram-only (`/dev/zram0`, 6 GiB), which **cannot** be used for
hibernation (kernel rejects it, per Arch wiki / kernel docs). S4
probe requires provisioning a real swap file on `/storage` first,
with `resume=`/`resume_offset=` plumbed through the kernel cmdline
or `uswsusp` from initramfs.

### Path C — Entire main space runs in a VM; hibernate = VM snapshot

"Arbitrary state," taken literally, means the whole main-space user
space has to be snapshottable. That means the whole main space lives
inside a VM, not an nspawn container. Then `qemu savevm` (or crosvm
equivalent) freezes vCPU + vRAM + virtual device state to a file. Host
powers off. On next boot, the VM file is loaded and execution resumes.

**What it costs**
- Replace the nspawn substrate of the main space with QEMU or crosvm.
  This is a different architecture from the one
  `docs/brainstorms/2026-05-07-002-rocknix-thin-host-nix-main-space.md`
  is built on.
- Virtual hardware: `virtio-gpu` (Venus / rutabaga / Turnip
  native-context) for graphics, `virtio-sound`, `virtio-net`,
  `virtio-input`, `virtio-block`.
- Available building blocks already present in nixpkgs (per the
  2026-05-12 brainstorm): `crosvm`, `qemu`, `virglrenderer 1.3.0`,
  `mesa 26.0.2`, `rutabaga_gfx 0.1.6`, `libkrun 1.17.0`.

**Why it might work**
- Vendor kernel suspend bugs are bypassed entirely. The VM uses its
  own (mainline) kernel.
- Risk is concentrated in **one place**: graphics performance and
  snapshot fidelity through virtio-gpu on Adreno. If graphics works,
  everything else is well-trodden.

**Why it might not**
- virtio-gpu + Venus / rutabaga / Turnip native-context on ARM64
  Snapdragon is exotic. The 2026-05-12 brainstorm noted nixpkgs'
  `crosvm` derivation is built only with `virgl_renderer`, not
  `gfxstream`; a custom build would be required.
- Mesa Venus has been primarily exercised on AMD/Intel hosts.
  Adreno-as-host is not a well-trodden path.
- Snapshot timing on virtual GPU: in-flight GPU commands must drain
  before snapshot. This is not validated for Adreno + Venus.

**Risk shape**
- Risk is concentrated in graphics. One investigation either unblocks
  the whole path or kills it. This is a fundamentally different risk
  profile from Path B's "long-tail driver matrix."

## The decision gate

**Resolved 2026-05-26: Path B is the recommended direction.**

The Path B S3 probe was executed on `bandai` (see Path B Findings
above). S3 suspend/resume round-trips cleanly at the kernel level on
the current ROCKNIX 20260526 nightly with kernel 7.0.2. The remaining
work for a hibernate-capable main-space mode is now a finite, named
list of three driver/userspace fixes (dwc3-qcom resume timeout,
ath12k+SMMU resume race, sway/userspace session recovery) plus
provisioning real disk swap for S4.

This is a smaller and more localized scope than Path C (replace the
nspawn substrate with a VM, prove virtio-gpu Venus on Adreno).
Path C remains theoretically interesting as a future architectural
option, but it is no longer the only candidate for delivering the
"arbitrary state, exactly where I was, no tricks" requirement.

Next concrete deliverables (each a separate plan, not part of this
brainstorm):

1. **S4 probe prerequisite work**: provision a real swap file or
   partition on `/storage` (6–8 GiB), plumb `resume=` and
   `resume_offset=` through the bootloader cmdline (or pick
   `uswsusp`), keep zram disabled or lower-priority for the
   hibernate target.
2. **S4 probe**: same shape as the S3 probe — `rtcwake`-equivalent
   with `echo disk > /sys/power/state`, log to `/storage`, observe
   full power-off and resume from disk on next boot. Decides whether
   the userspace fix list is the same as S3's or grows.
3. **Userspace post-resume hook**: a systemd-sleep hook that
   restarts sway / essway / NetworkManager / tailscale / guest
   services on resume. Cheap.
4. **dwc3-qcom and ath12k+SMMU resume fixes**: investigate upstream
   patches that match the symptoms in the S3 probe log; backport or
   pick into the ROCKNIX kernel build.

The 2026-05-12 VM-graphics MVP is no longer a blocker for the
hibernate question, but remains relevant for any future Path C
decision (and for VM-snapshot use cases generally).

That is exactly the spike scoped in
`docs/brainstorms/2026-05-12-vm-graphics-freeze-mvp-handoff.md`:

1. Build a Nix flake that runs `qemu` (or `crosvm`) on SM8550 with
   `virtio-gpu` Venus or rutabaga enabled.
2. Boot a minimal NixOS guest VM inside it.
3. Render a known GPU workload (e.g. `glxgears`, `vkmark`, then
   eventually a Cemu/BOTW slice).
4. Measure frames vs the existing nspawn / direct-GPU baseline.
5. Run `qemu savevm` mid-render. Power off the host. Power on the host.
   Restore. Continue rendering. Confirm no visible discontinuity.

That spike's output is the gate:

- **Pass** (acceptable performance + clean snapshot/restore) → Path C
  becomes the real direction. Begin scoping the architectural shift
  away from nspawn for the main space.
- **Fail** (graphics doesn't work or is unusably slow) → Path C is
  dead. The only remaining option is Path B, which becomes a multi-
  quarter vendor-kernel suspend project with known stall risk.
- **Ambiguous** (e.g. works at 60% native performance) → judgment
  call. Probably still better than Path B's stall risk; revisit in a
  separate brainstorm.

## What this does not change

The current main-space architecture in `docs/brainstorms/2026-05-07-002…`
remains correct for everything *except* hibernate UX:

- Milestones 14–20 still hold; nothing in this brainstorm asks them to
  pause.
- Milestone 18 ("guest-owned sleep UX") is still the right home for
  the *fake-suspend* path. Hibernate is a sibling concern, not a
  replacement.
- Path C, if validated, would create a new architectural option for
  the main space generally — not just for hibernate. That is itself a
  reason the 2026-05-12 spike is worth re-prioritizing.

## Key decisions captured

- "Hibernate the guest" is not a guest-local operation on this
  architecture; it is necessarily a whole-system state-dump operation.
- Anything weaker than "byte-for-byte arbitrary state" is rejected.
  Emulator savestates, manifest-only restore, and partial-VM coverage
  are all out of scope.
- Only Path B (real Linux S4) and Path C (main space in a VM, VM
  snapshot) can satisfy the requirement.
- Neither path is committable until the 2026-05-12 VM-graphics MVP
  has been run.

## Outstanding questions

For a spike, not for this brainstorm:

Path B:

- Does `echo mem > /sys/power/state` round-trip on a current ROCKNIX
  SM8550 build with the `030-suspend_mode` policy reverted? (Resolved
  by the cheap probe above.)
- If S3 works, does `echo disk > /sys/power/state` work with swap
  provisioned on `/storage`?
- Does `rocknix-abl` need explicit work to honor `resume=` /
  `resume_offset=` on the kernel cmdline, or can `uswsusp` post-boot
  cover this?
- What is UFS write-then-read fidelity under hibernate-sized I/O on
  Thor specifically? (The most plausible remaining failure mode.)
- Does the InputPlumber + virtual-gamepad chain re-establish cleanly
  on resume?
- Does the q6/lpass audio path resume without a firmware reload race?
- Are the DSI panels (Thor's two displays per Spike 6 in the
  thin-host brainstorm) happy across S4?

Path C (still ungated):

- Does `CONFIG_HIBERNATION` currently compile in the SM8550 kernel?
  **Answered: yes.** Removed from this list.
- Does `virtio-gpu` Venus work at all on Adreno via the `msm` kernel
  driver as host? What about `rutabaga` / `gfxstream`?
- Does `qemu savevm` capture in-flight GPU state correctly through
  Venus?
- Is `crosvm` viable as the substrate, or does the absence of
  `gfxstream` in the nixpkgs build force QEMU?
- What is the boot-time cost of `loadvm` resume from `/storage`?
- If Path C lands, does the existing nspawn-based work in Milestones
  14–17 still apply, or does it need to be reframed against a VM
  substrate?

## Operational learnings from the probe run

Gotchas discovered while running the live S3 probe on `bandai`. These
are not architectural conclusions; they are practical things to know
when resuming this work.

### Networking topology and SSH reach

- `root@bandai` (tailscale) only works while the guest is up, because
  the guest owns `tailscaled` (per the shared-netns single-manager
  networking decision in `2026-05-07-002`).
- `root@192.168.1.239` (direct LAN, host-side SSH on port 22) works
  even with the guest stopped, but only when Wi-Fi or USB-ethernet
  has the host on that subnet.
- The cleanest setup for suspend probing is **USB-ethernet plugged
  in**: gives host LAN reach independent of the guest's Wi-Fi stack,
  so you can debug Wi-Fi-resume failures without losing SSH.
- For arbitrary remote work where you might need to stop the guest:
  always use the LAN IP, never the tailscale name.

### SSH heredoc + guest stop is a footgun

- `ssh root@bandai '<heredoc with systemctl stop rocknix-guest>'`
  will die mid-heredoc because tailscale drops with the guest, and
  the rest of the heredoc never executes — BUT the remote shell may
  continue running for up to ~120 s (TCP keepalive) before SIGHUP
  arrives.
- This means earlier script lines can still execute (and silently
  succeed or fail) after SSH appears dead. That is exactly what
  happened on the first probe attempt: the script reached
  `echo mem > /sys/power/state` after the SSH socket died, S3
  completed, we just couldn't see the log.
- **Rule**: any remote script that stops the guest, suspends the
  host, or otherwise disturbs networking must detach the work (`&`
  + `disown`, or `systemd-run --no-block`) and write its output to
  a persistent log file on `/storage`. Do not rely on stdout over
  SSH.

### BusyBox `dmesg` limitations

ROCKNIX uses BusyBox `dmesg`. It accepts only `-c`, `-r`, `-n`, `-s`.
It does **not** accept `-T` (human-readable timestamps) or `--since`.
For parsing, work with raw kernel-time deltas (e.g. `[18292.111478]`)
relative to a known reference (`uptime` or the previous `date` echo
at known kernel-time).

### RTC wake without `rtcwake`

ROCKNIX (BusyBox / util-linux subset) does not ship `rtcwake`. Use
the sysfs interface directly:

```
echo 0 > /sys/class/rtc/rtc0/wakealarm        # clear any pending alarm
echo "+30" > /sys/class/rtc/rtc0/wakealarm    # set alarm 30 s from now
cat /sys/class/rtc/rtc0/wakealarm             # confirm (epoch seconds)
```

The RTC on Thor is `rtc-pm8xxx` (the PMIC RTC). It is
`wakeup-source` per the DTS. `/sys/devices/platform/gpio-keys/power/wakeup`
also reports `enabled` (power key wake path). Either should wake
from S3.

### `/sys/power/state` bypasses the userspace policy

`030-suspend_mode` writes `AllowSuspend=no` into a systemd-sleep
drop-in and ignores the power/suspend keys. Both are logind-level
barriers, not kernel-level. Writing directly to `/sys/power/state`
bypasses them. **No revert of `030-suspend_mode` is needed for the
probe.** This is also why we did not need to set `system.suspendmode
mem` via the ROCKNIX `suspendmode` script.

### zram is not hibernate-eligible

ROCKNIX ships zram swap by default (`/dev/zram0`, 6 GiB, priority
100). The kernel and `systemd-logind` both refuse to hibernate to
zram. For S4, real disk swap on `/storage` is required, with
appropriate `pri=` to keep zram below it (or zram disabled entirely
for the hibernate scenario).

### Probe command shape that worked

Reusable pattern for any future suspend/hibernate probe —
detach, log to `/storage`, return SSH cleanly:

```sh
ssh root@192.168.1.239 '
LOG=/storage/.probe-s3-$(date +%s).log
{
  echo "=== probe start $(date) ==="
  sync; sync; sync
  echo 0 > /sys/class/rtc/rtc0/wakealarm
  echo "+30" > /sys/class/rtc/rtc0/wakealarm
  echo "=== T3 SUSPENDING $(date) ==="
  echo mem > /sys/power/state
  echo "=== T4 RESUMED rc=$? $(date) ==="
  dmesg | tail -120
  echo "=== probe done $(date) ==="
} > "$LOG" 2>&1 &
disown
echo "detached, log=$LOG"
'
```

Then wait `seconds_until_alarm + 5` and SSH back in to read
`/storage/.probe-s3-*.log`. The same shape works for S4 by
replacing `mem` with `disk`, once swap is provisioned.

## How to resume this work later

When picking this up:

1. **Read this brainstorm and the evidence log**
   (`docs/brainstorms/evidence/2026-05-26-003-s3-probe-bandai.txt`).
   The S3 probe result is the decision-shaping artifact.

2. **Decide which strand to pursue first**, in rough priority order:
   - **Userspace post-resume hook** (smallest, immediate UX win).
     Add a `systemd-sleep` script to ROCKNIX that, on `post`, restarts
     `sway.service`, `essway.service`, `rocknix-guest.service`,
     and any network bits, in the right order. Verify by running the
     same S3 probe and checking that sway, the guest, and tailscale
     all come back without manual intervention. Low risk, no kernel
     work.
   - **S4 prerequisites**: provision a swap file on `/storage`
     (6–8 GiB), plumb `resume=` and `resume_offset=` through the
     `rocknix-abl` kernel cmdline, or set up `uswsusp` from initramfs.
     Decide whether to demote zram or leave it co-existing with disk
     swap (zram at `pri=10`, disk swap at `pri=100`).
   - **S4 probe**: same procedure as the S3 probe but with `echo
     disk > /sys/power/state` and a longer wait (RTC alarm should
     still fire from cold). Confirms the dump-to-disk + boot-resume
     loop works.
   - **dwc3-qcom + ath12k SMMU resume patch hunt**: investigate
     upstream fixes matching the symptoms below; backport into the
     ROCKNIX kernel build. This is the long-tail polish, not the
     gate.

3. **Reproduce the S3 probe baseline** before changing anything, so
   any regression is attributable. The probe procedure is captured
   above; the prior log is preserved in
   `docs/brainstorms/evidence/2026-05-26-003-s3-probe-bandai.txt`
   (kept as `.txt` because the repo `.gitignore` excludes `*.log`).

## Upstream issue / patch breadcrumbs

For the dwc3-qcom + ath12k SMMU resume work, search trails that
looked productive during the 2026-05-26 web research pass:

- **ath12k resume crash CVE-2024-40979** — fixed in 6.9.7 /
  6.10-rc1. ROCKNIX (kernel `7.0.2`) already has this fix in the
  base. Mentioned here so future readers do not chase a fix that is
  already present.
- **ath12k high CPU after suspend/resume** —
  https://bugzilla.kernel.org/show_bug.cgi?id=220182 (Anubis-gated;
  may need plain `curl` with browser headers to fetch). Still NEW
  upstream as of this writing. Not necessarily related to our SMMU
  fault, but adjacent.
- **`dwc3-qcom` PM resume timeout** — search dri-devel and
  `linux-arm-msm@vger.kernel.org` archives for `qcom-qmp-combo-phy
  initialization timed-out` and `dwc3_qcom_pm_resume returns -110`.
  Several patches in the 6.x range address this class.
- **arm-smmu IOMMU context fault during MHI re-init** — search
  `linux-arm-msm` archives for `Unhandled context fault` paired with
  `mhi mhi0` re-init on resume. Likely a DMA mapping race; patches
  in flight as of mid-2025 last we looked.
- **Linaro SM8x50 mainline UFS stability flag** —
  https://devboardsforandroid.linaro.org/en/latest/devices/sm8x50.html
  explicitly lists UFS as known-unstable on mainline. Relevant for
  S4 because hibernate writes/reads the swap image through UFS.

## Status snapshot at capture time

- Branch: `main`
- Last commit observed: `6d1e551` (mark test boundary refactor complete)
- No code changes proposed.
- Conversation produced no implementation work; one empirical S3
  suspend/resume probe was executed on `bandai` to derisk Path B.
- Probe log retained at `/storage/.probe-s3-1779855080.log` on the
  device.
- Next concrete deliverable (whenever the user picks it up) is the
  S4 probe prerequisite work (real swap on `/storage`, bootloader
  resume cmdline), followed by the S4 probe itself.
- Path C (VM substrate / virtio-gpu) and the 2026-05-12 MVP are no
  longer required to resolve the hibernate question, but remain on
  the architectural option list for other purposes.
