---
id: task-028
title: Enable gamescope on RG353M (Mali-G52 / RK3566)
status: To Do
priority: high
labels:
  - rg353m
  - rk3566
  - graphics
  - gamescope
  - mali-g52
  - panvk
  - libmali
  - vulkan
created: 2026-06-06
source: se-debug
---

# Enable gamescope on RG353M (Mali-G52 / RK3566)

## Why it matters

Gamescope is required by the Korri product on RG353M (per user direction); the previous "ship with gamescope disabled" stance is rejected. Today gamescope-korri aborts at startup on this device because the only enumerable Vulkan device is llvmpipe (CPU), and gamescope hard-requires VK_EXT_physical_device_drm on the selected device. PanVK refuses to enumerate Mali-G52 Bifrost-v7 even with PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1. No runtime flag (`--allow-deferred-backend`, `--backend headless|sdl|wayland`, etc.) bypasses the DRM-modifier check. The fix is a build-level change. Two real options exist; either unblocks the RG353M product story and lets us ship gamescope-wrapped sessions (Korri's launcher composes its launch spec around gamescope, so this is load-bearing for launch behaviour, input policy, FPS limiting, FSR/integer scaling, and the kiosk surface contract).

## Acceptance Criteria

- [ ] gamescope-korri starts successfully on RG353M wrapping a libretro launch (e.g. Super Mario Advance via mgba) and produces a visible game surface composited inside gamescope.
- [ ] Korri library config global.gamescope.enabled = true on RG353M results in a working gamescope launch path end-to-end (Korri UI → press A → gamescope → RetroArch → game).
- [ ] InputPlumber virtual Xbox 360 pad continues to drive gamescope-hosted launches (face buttons + D-pad + Start, matching the autoconfig that already works direct-to-Wayland).
- [ ] Whichever path is chosen (gamescope patch vs libmali swap) is shipped as a Nix derivation change in nix-on-rocks RG353M guest module — not as a /run/ drop-in.
- [ ] The RG353M guest module documents the choice (patched gamescope vs libmali stack) and the reasoning so a future maintainer can revisit when upstream PanVK matures.

## Related

- `guest/modules/rk3566.nix`
- `guest/profiles/devices/rg353m.nix`
- `docs/plans/2026-06-04-001-feat-rg353m-rk3566-support-plan.md`
- `backlog/task-021 - bring-up-rg353m-display-touchscreen-and-controls.md`
- `backlog/task-013 - bring-up-rk3566-rk817-audio-in-guest.md`
- `/var/lib/korri-server/.local/share/korri/library/library.yaml (runtime, RG353M)`
- `/nix/store/x4ihdjn1r61q9553ljdrqrinclj6rclv-gamescope-korri-3.16.23-korri (current build)`
- `/nix/store/m79y8q4yspfa48gdckyc6p808yir7swa-mesa-25.2.6 (current Mesa)`

## Notes

Two paths surfaced; pick at promotion time.

PATH A — Patch gamescope-korri to relax VK_EXT_physical_device_drm
  - Convert the hard check in gamescope's Vulkan init to a warn + texture-copy fallback (no DRM dmabuf zero-copy).
  - Ship as an RG353M-specific patch in the gamescope-korri derivation.
  - Runs gamescope on llvmpipe (CPU Vulkan) compositing 640x480. Probably playable for 2D/GBA-era titles; 3D likely unviable.
  - ~1 day engineering, all Nix, reversible.

PATH B — Swap RG353M graphics stack from Mesa Panfrost to ARM libmali (Vulkan + GLES)
  - libmali r45p0+ provides Mali-G52 Vulkan with VK_EXT_physical_device_drm and Wayland WSI.
  - Replaces Mesa Panfrost for BOTH GLES (Sway, RetroArch, korri-desktop) and Vulkan (gamescope).
  - Requires verifying a Vulkan-capable libmali variant for G52 actually ships (chip=g52, WSI=wayland-gbm, ABI=glibc-aarch64).
  - Requires verifying the RG353M kernel has mali_kbase (Rockchip BSP) and NOT only upstream panfrost. If only panfrost, a kernel rebuild is in scope.
  - 3–7 working days; closed-source blob; affects every GLES app on device.

PATH C — Wait for upstream PanVK to support Mali-G52 v7 + DRM ext. No estimated date, not actionable.

Recommended sequence: do PATH-B feasibility check first (does a Vulkan-capable libmali variant exist for G52? does this kernel run panfrost or mali_kbase?). If both green, PATH B. If either red, PATH A as the actual ship path.

Diagnostic evidence captured on-device today:
  - vulkaninfo confirms VK_KHR_wayland_surface IS exposed (rev 6) on both lvp_icd and panfrost_icd. WSI is built into Mesa 25.2.6.
  - panvk loads with PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1 but enumerates 0 devices ("WARNING: panvk is not well-tested on v7 ... VK_ERROR_INCOMPATIBLE_DRIVER").
  - llvmpipe enumerates but lacks VK_EXT_physical_device_drm → gamescope `[Error] vulkan: physical device doesn't support VK_EXT_physical_device_drm` → SIGABRT (exit 134).
  - gamescope-korri binary contains no env/flag to skip the check (grepped).
  - `--allow-deferred-backend` retries device selection in a loop, still fails the same check.

Runtime workaround currently in place: library.yaml has gamescope.enabled=false; RetroArch renders direct-to-Wayland (Sway) and works fine. That workaround is acceptable as a stopgap but is NOT the intended product behaviour.

### Deploy / rebuild lane

**Payload re-render + fast (guest-promote).** The gamescope-korri patches live in ../korri (committed 2804f46, 263f554) → they reach the device via `scripts/render-product-payload` (Korri payload) + redeploy. The PanVK enablement env (`PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1`, `MESA_VK_VERSION_OVERRIDE=1.2`, `VK_DRIVER_FILES=...panfrost_icd.aarch64.json`) and the "run gamescope as the primary DRM compositor (LIBSEAT_BACKEND=builtin), not nested in Sway" session-architecture change live in the guest session units → `guest/modules/rk3566.nix` / sessiond → **fast guest-promote**. No **full image rebuild** is needed (Mesa/PanVK is already on the device); a full rebuild is only required if Mesa itself must be patched/bumped. NOTE: the clean product launch path also depends on task-029 (the sessiond home→game transition).

### Clean-baseline root cause (2026-06-07): nested vblank has no free-running fallback

Reproduced on a clean Sway baseline with the corrected build
(0001 render-only + 0002 explicit-sync-disable + 0003 precompile-disable;
GAMESCOPE_DISABLE_EXPLICIT_SYNC=1, GAMESCOPE_DISABLE_PIPELINE_PRECOMPILE=1,
PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1, MESA_VK_VERSION_OVERRIDE=1.2).

Behaviour: gamescope+RetroArch START, PRESENT, and PLAY for a while
(ra_utime ~7.5s CPU before lock), then DEADLOCK. So the corrected build
genuinely works initially; the freeze is a residual time-based stall.

gdb ground truth at lock:
- RetroArch main thread:
    ppoll -> wl_display_poll -> wl_display_dispatch_queue ->
    flush_wayland_fd -> input_wl_poll -> core_input_state_poll_late -> retro_run
  i.e. blocked waiting for ANY event (its frame callback) from gamescope.
- gamescope main (gamescope-wl): idle in poll() waiting for the host.

ROOT CAUSE: gamescope's nested Wayland vblank is FEEDBACK-DRIVEN. In
vblankmanager.cpp the timerfd path: CVBlankTimer::OnPollIn fires, sets
m_PendingVBlank, DISARMS, and does NOT re-arm. Re-arm only happens via
CVBlankTimer::MarkVBlank(.., true), which is called from
CWaylandPlane::Wayland_PresentationFeedback_Presented. So the nested
vblank only keeps ticking while the host (Sway) keeps sending
presentation feedback. When Sway's output goes idle (wlroots stops
repainting when nothing else damages the scene -- which is the steady
state once the kiosk hides every other surface for a fullscreen game),
feedback stops, the vblank never re-arms, gamescope stops sending the
game frame callbacks, and the whole chain deadlocks. There is NO
free-running fallback timer in the nested backend.

Confirmed dead ends:
- "/sys writable in nspawn": NOT the cause (sys read-only is fine; the
  virtual Xbox pad is created with sys ro). Was a test-harness artifact.
- "re-arm vblank on Discarded": kept gamescope's host-facing loop ticking
  but did NOT unfreeze the game, and re-committing on every discard risks
  a discard-storm. Reverted.
- Dropping explicit-sync patch: REGRESSION -- explicit-sync MUST be
  disabled for nested PanVK to present at all (else Sway discards 100% of
  frames: 0 presented confirmed via WAYLAND_DEBUG). Restored.

PROPOSED REAL FIX (next focused pass): give the nested vblank a
free-running fallback. Either (a) re-arm the timerfd in OnPollIn so it
free-runs at the target refresh and let feedback only CORRECT timing
(MarkVBlank), or (b) add a watchdog that re-arms ArmNextVBlank if no
presentation feedback arrives within ~2-3 refresh intervals. This makes
gamescope keep generating vblanks (and thus game frame callbacks) even
when the host output is idle. Must be tested iteratively on a CLEAN boot
(tonight's manual launches/scratchpad moves/service restarts contaminated
the session and gave inconsistent lock times: 4s/6s/80s). Capture the
real sessiond launch with WAYLAND_DEBUG to confirm Presented stops at the
lock, then validate the fallback keeps the loop alive.

Tools left on device for the next pass: gdb (wwn0x2r5...), strace
(bvccqb78...). Reproduce via the actual sessiond/UI launch, not a manual
gamescope invocation (manual harness reproduced a DIFFERENT occlusion
failure: webview-on-top -> 100% discarded).

### Free-running vblank fix ATTEMPTED and FAILED (2026-06-07)

Implemented the proposed free-running vblank fallback (korri patch 0004,
GAMESCOPE_NESTED_FREERUN_VBLANK env, OnPollIn inline re-arm). Verified on
device: patch compiled into the running ELF, env set, build confirmed —
RetroArch STILL locked at ~10s. So re-arming the nested vblank is NOT
sufficient; the deadlock is DOWNSTREAM of the vblank (steamcompmgr
composite / present-completion / buffer-release). Patch reverted.

That's THREE failed reasoned-from-source fixes (/sys, discard-rearm,
freerun-vblank). Hard blocker on further progress: the gamescope-korri
builds are STRIPPED, so gdb on the locked process yields only ?? frames —
cannot observe what the compositor is actually blocked on. Inferring from
source has failed three times.

NEXT REAL STEP (not another blind patch):
1. Build gamescope-korri with debug symbols (separateDebugInfo / dontStrip,
   -g, debug enableDebugging) so gdb gives real frames.
2. Reproduce the lock via the actual sessiond launch on a CLEAN boot.
3. gdb the locked gamescope main/composite threads -> identify the exact
   wait (Vulkan fence? buffer release? host present ack?).
4. Fix that specific wait. Consider filing upstream (ValveSoftware/gamescope)
   with the PanVK/Sway nested repro.
Known-good fallback for users meanwhile: library.yaml gamescope.enabled=false
(RetroArch direct-to-Sway, stable all session).

### SOLVED (2026-06-07): run the game over Xwayland, not native Wayland

After exhaustive instrumentation (debug-symbol gamescope build + gdb + per-commit
tracing), the freeze was NOT a gamescope bug. gamescope's per-frame pipeline is
healthy: IMPORT -> SIGNAL(fence) -> DONE(receivedDoneCommit) -> FRAMEDONE are all
balanced every frame, the vblank timer stays armed, and it composites via PanVK
on Mali-G52 fine. The game ran a clean 60fps for 1000-1500 frames, then RetroArch
(a NATIVE-WAYLAND client) intermittently wedged in its own wl_display_dispatch_queue
input poll and stopped committing. Sending/flushing frame-done callbacks (tried:
immediate flush, end-of-loop flush, per-vblank frame-callback heartbeat) did NOT
wake it -> the deadlock is inside RetroArch's native-Wayland event dispatch, not
gamescope.

FIX: run the game through gamescope's Xwayland (X11) path -- gamescope's primary,
battle-tested use case -- instead of native Wayland. Concretely: unset
WAYLAND_DISPLAY for the game child so RetroArch uses X11 via gamescope's Xwayland.

Proof: clean gamescope (patches 0001 render-only + 0002 explicit-sync-disable +
0003 precompile-disable) + `gamescope ... -- env -u WAYLAND_DISPLAY retroarch ...`
ran 200s+ with ZERO stalls (alive=40/40 samples, 12000+ frames, ra_utime climbing
steadily), vs every native-Wayland run locking at 25-80s.

Required env for the gamescope wrapper (unchanged): PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1,
MESA_VK_VERSION_OVERRIDE=1.2, VK_DRIVER_FILES=<mesa>/share/vulkan/icd.d/panfrost_icd.aarch64.json,
GAMESCOPE_DISABLE_PIPELINE_PRECOMPILE=1, GAMESCOPE_DISABLE_EXPLICIT_SYNC=1.

Dead ends (do not retry): wlserver flush-frame-callbacks patch, end-of-loop
client flush, per-vblank frame-callback heartbeat, free-running vblank, stuck-fence
watchdog, /sys writability. All ruled out empirically; reverted. gamescope stays
at the 3 proven patches.

NEXT: persist `env -u WAYLAND_DISPLAY` (or equivalent X11-forcing) into the Korri
game-launch command for the RK3566/RG353M product so it survives reboots and the
real sessiond launch path.
