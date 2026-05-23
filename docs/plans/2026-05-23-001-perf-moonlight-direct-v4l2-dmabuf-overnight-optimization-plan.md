---
title: 'perf: Drive Moonlight direct V4L2 dma-buf CPU as low as practical overnight'
type: perf
status: completed
date: 2026-05-23
origin: direct user request after Stage 2 color-correct dma-buf proof
verify_command: "guest/scripts/static-checks.sh"
---

# perf: Drive Moonlight direct V4L2 dma-buf CPU as low as practical overnight

## Summary

Optimize the experimental Moonlight Embedded SM8550 direct V4L2 + dma-buf GL path for the lowest practical Sobo process CPU while preserving correctness. The work starts from the color-correct Stage 2 path:

```text
MOONLIGHT_V4L2M2M_DIRECT=1
MOONLIGHT_V4L2M2M_DMABUF=1
```

Current best validated result:

| Variant | Process CPU | System busy | RSS |
|---|---:|---:|---:|
| direct V4L2 + SDL NV12 upload | 12.7% | 6.4% | 314.7 MiB |
| direct V4L2 + color-correct dma-buf GL | 11.7% | 6.2% | 312.7 MiB |

The goal is not literal 0% CPU. Moonlight still pays for network receive/reassembly, protocol/control, V4L2 ioctls, GL draw/swap, input/audio threads, and scheduler overhead. A successful overnight run should push the color-correct dma-buf path toward single-digit process CPU if possible, with evidence good enough to separate real wins from benchmark noise.

## Problem Frame

Stage 2 proved zero-copy presentation in the important sense: VPU-owned V4L2 CAPTURE dma-bufs can be exported, imported into EGL, sampled as two GL textures, color-converted explicitly with the BT.709 NV12 shader, and presented through SDL's GL window under Wayland. The path is still research-only because it is submit-thread-driven and does per-frame EGL work. That leaves obvious avoidable CPU/RSS overhead before the architecture is worth promoting to longer soak testing.

The user wants unattended overnight progress. The plan therefore prioritizes changes that are reversible, env-gated, measurable, and safe to iterate without new product decisions.

## Requirements

- R1. Keep the shipping default unchanged: plain `-platform v4l2m2m` remains FFmpeg `hevc_v4l2m2m`/`h264_v4l2m2m` -> NV12 AVFrame -> SDL NV12 renderer.
- R2. Keep all direct/optimized work behind env gates. Existing gates stay meaningful:
  - `MOONLIGHT_V4L2M2M_DIRECT=1`
  - `MOONLIGHT_V4L2M2M_DMABUF=1`
- R3. Do not regress color correctness. The accepted Stage 2 color path is explicit Y (`DRM_FORMAT_R8`) + UV (`DRM_FORMAT_GR88`) plane imports with the BT.709 NV12 shader. Whole-NV12 implicit conversion is not acceptable as a final result.
- R4. Do not regress geometry. Sobo's 1280x720 stream into 960x540/960x517 Wayland output must remain aspect-fit, crop-free, and resize-aware.
- R5. Every candidate must have evidence under `/storage/.guest/runs/` with logs, sample CSVs, screenshots, signal counts, exact binary path, and exact env gates.
- R6. Report medians/ranges when time permits. Do not declare a win from a single noisy 30s run unless it is only a quick smoke.
- R7. Prefer lower CPU only when stream correctness remains green: no `Network dropped`, no `Unrecoverable`, no EGL/GL errors, no persistent V4L2 starvation, and visually correct screenshots.
- R8. Use dummy audio for this optimization lane; real PipeWire/audio repair remains separate.
- R9. Commit in atomic units. Each commit should leave the default path intact and the experimental path either green or clearly documented as a failed/deferred spike.
- R10. Pause only for irreducible decisions that would change default behavior, require rootfs/profile wiring, or risk losing the known-good Stage 2 path.

## Scope Boundaries

- No change to the default `v4l2m2m` shipping path.
- No rootfs/profile/kiosk wiring.
- No real audio/PipeWire repair.
- No Sunshine host app/config changes except continuing to use the existing `Desktop (Sway)` workload.
- No permanent power caps as part of the feature; power/thermal data may be sampled only as benchmark context.
- No hand-wavy "0% CPU" claim. The plan optimizes and measures, but keeps conclusions bounded by evidence.

## Context and Research

### Current implementation surface

- `packages/moonlight-embedded/patches/0002-add-v4l2m2m-sdl-nv12-platform.patch` — core C patch, exported from the upstream scratch checkout.
- Scratch checkout pattern: `scripts/moonlight-embedded-dev-checkout.sh` materializes upstream under `/tmp/moonlight-embedded-dev/7754442/`; edit `src/video/v4l2m2m.c` there, amend/export patch, copy back.
- `guest/launchers/remote-moonlight-runner.sh` and `guest/launchers/remote-moonlight-runtime-ab.sh` — existing evidence harness shape, but not yet enough for repeated direct-SDL/direct-dma-buf CPU experiments.
- `docs/acceptance/moonlight-embedded-direct-v4l2-stage1-sobo-2026-05-23.md` — Stage 1 direct decoder proof.
- `docs/acceptance/moonlight-embedded-direct-v4l2-dmabuf-stage2-sobo-2026-05-23.md` — Stage 2 color-correct dma-buf proof.
- `docs/solutions/integration-issues/moonlight-embedded-v4l2m2m-nv12-sdl-renderer-sobo-2026-05-23.md` — prior lesson: SDL solved Wayland sizing/aspect-fit; custom GL must preserve that behavior.

### Research synthesis

Local research and learnings agree on the likely optimization order:

1. Stabilize benchmark evidence before chasing micro-wins.
2. Cache per-CAPTURE-buffer EGLImages/textures instead of creating/destroying two EGLImages per frame.
3. Remove the direct path's double copy into V4L2 OUTPUT buffers.
4. Tune V4L2 queue depths after instrumentation rather than keeping `DIRECT_OUT_BUFS=32` blindly.
5. Attempt a dedicated V4L2 poll/dequeue thread only after lower-risk wins, and keep it separately gated.

## Key Technical Decisions

- **Optimize the env-gated Stage 2 path, not the default.** The FFmpeg-wrapper + SDL renderer remains the safe product path. Overnight work is research to lower direct path CPU.
- **Benchmark first.** Prior 30s measurements varied enough that a reusable harness is a prerequisite for credible conclusions.
- **Cache imported resources per CAPTURE buffer.** The highest-confidence waste is per-frame `eglCreateImageKHR`/`eglDestroyImageKHR` for Y and UV planes. CAPTURE buffer indices are stable, and dma-buf fds live until cleanup, so per-index caching is the natural design.
- **Keep explicit color conversion.** Whole-NV12 import was faster-looking but visibly wrong. The optimizer must use the two-plane BT.709 path unless a later path proves identical color.
- **Defer risky threading until after caching/copy wins.** A poll thread can reduce jitter but can also add wakeups, locks, and deadlocks. It belongs late and behind a new env gate.
- **Use Sobo as the source of truth.** Compile-clean on Fuji is necessary, but all performance decisions require Sobo evidence.

## Implementation Units

### U1 — Commit a reusable direct-path benchmark harness

**Goal:** Replace ad hoc `/tmp/bench-*.sh` usage with a committed, repeatable benchmark harness for direct V4L2 renderer variants.

**Files:**

- Modify: `guest/launchers/remote-moonlight-runner.sh` and/or `guest/launchers/remote-moonlight-runtime-ab.sh`
- Or create: `guest/launchers/remote-moonlight-direct-ab.sh`
- Update docs as needed: `docs/acceptance/moonlight-embedded-direct-v4l2-dmabuf-stage2-sobo-2026-05-23.md`

**Approach:**

- Support named variants at least:
  - `direct_sdl`: `MOONLIGHT_V4L2M2M_DIRECT=1`, no dma-buf gate.
  - `direct_dmabuf`: `MOONLIGHT_V4L2M2M_DIRECT=1 MOONLIGHT_V4L2M2M_DMABUF=1`.
  - later candidates such as `direct_dmabuf_cached` or `direct_poll_thread` via env passthrough.
- Capture per-second samples: process ticks, RSS, thread count, system CPU total/idle, max thermal.
- Capture signal counts: `Network dropped`, `Waiting for IDR`, `Unrecoverable`, `no free OUTPUT`, EGL/GL errors, first import success, presentation count.
- Capture screenshot after presentation.
- Write `evidence.md` summarizing each run.

**Execution posture:** characterization-first. Establish current baseline before optimizing.

**Test scenarios:**

- Running the harness for `direct_sdl direct_dmabuf` produces two run dirs and a top-level `evidence.md`.
- A missing Moonlight binary fails clearly.
- `MOONLIGHT_AUDIO_GATE=0` / dummy audio remains visible in evidence.
- Signal counts are present even when count is zero.
- `guest/scripts/static-checks.sh` passes.

**Verification:**

- Static checks pass.
- Sobo run dir contains CSV samples, launch logs, screenshots, and evidence summary.
- Baseline numbers roughly match current documented range before implementation units proceed.

### U2 — Cache EGLImages and GL textures per V4L2 CAPTURE buffer

**Goal:** Remove per-frame two-plane EGL import/destruction overhead from the color-correct dma-buf path.

**Files:**

- Modify: `packages/moonlight-embedded/patches/0002-add-v4l2m2m-sdl-nv12-platform.patch` via scratch `src/video/v4l2m2m.c`
- Update: `docs/acceptance/moonlight-embedded-direct-v4l2-dmabuf-stage2-sobo-2026-05-23.md`

**Approach:**

- Extend direct CAPTURE buffer state or add side arrays keyed by CAPTURE index:
  - `EGLImageKHR img_y`, `img_uv`
  - `GLuint tex_y`, `tex_uv`
  - cached import dimensions/stride/uv offset
  - `bool gl_ready`
- On first display of a CAPTURE index, import Y/UV EGLImages once and bind them to textures once.
- On subsequent displays of the same index, only bind cached textures, update quad/geometry if needed, draw, and swap.
- Destroy cached GL textures/EGLImages while the GL context is current during cleanup, before closing dma-buf fds or unmapping V4L2 buffers.
- Preserve the existing no-overwrite display queue behavior so CAPTURE buffers are not requeued before `SDL_GL_SwapWindow` completes.

**Execution posture:** test/measure before and after. Keep the previous non-cached Stage 2 path easy to recover in git if caching misbehaves.

**Test scenarios:**

- First use of each CAPTURE index logs one import/cache creation, not one per frame.
- Subsequent frames render without repeated `eglCreateImageKHR` logs.
- Screenshot colors match the corrected Stage 2 path.
- No plane import errors, `glEGLImageTargetTexture` errors, or `glDrawArrays` errors.
- Resize/aspect-fit still logs correct `presentation(direct-dmabuf)` geometry.
- A/B benchmark shows median process CPU and RSS relative to U1 baseline.

**Verification:**

- Fuji build succeeds.
- Sobo smoke renders correct-color screenshot.
- Repeated benchmark shows no correctness regression and records CPU delta.

### U3 — Remove direct-path double copy into OUTPUT buffers

**Goal:** Avoid copying decode units into `nal_buf` and then into V4L2 OUTPUT buffers for the direct decoder.

**Files:**

- Modify: `packages/moonlight-embedded/patches/0002-add-v4l2m2m-sdl-nv12-platform.patch` via scratch `src/video/v4l2m2m.c`

**Approach:**

- For `direct_v4l2_submit()`, acquire a free OUTPUT buffer before coalescing.
- Use `du->fullLength` for size checks.
- Copy `PLENTRY` fragments directly into `direct_out[out_index].addr`.
- Keep `nal_buf` for FFmpeg-wrapper path only.
- Set `planes[0].bytesused` to the exact copied byte count.

**Execution posture:** small, low-risk optimization; verify with smoke and benchmark.

**Test scenarios:**

- Direct SDL and direct dma-buf paths still receive first frame.
- No `decode unit too large` false positives.
- No increase in `Waiting for IDR`, `Network dropped`, or `no free OUTPUT`.
- Benchmark records CPU delta versus cached-EGL baseline.

**Verification:**

- Fuji build succeeds.
- Sobo smoke renders correct screenshot.
- Harness evidence shows equal or lower process CPU without signal regressions.

### U4 — Tune direct V4L2 queue depths with evidence

**Goal:** Reduce RSS and possibly CPU/cache pressure without causing starvation or stutter.

**Files:**

- Modify: `packages/moonlight-embedded/patches/0002-add-v4l2m2m-sdl-nv12-platform.patch` via scratch `src/video/v4l2m2m.c`
- Update: acceptance/performance docs with matrix results.

**Approach:**

- Sweep conservative queue-depth candidates after U2/U3:
  - OUTPUT: 8, 12, 16, 24, 32
  - CAPTURE: 8, 12
- Prefer compile-time constants for initial sweep; only add env knobs if the sweep proves useful enough to keep.
- Reject any candidate that increases `no free OUTPUT`, `Waiting for IDR`, drops, or visible stutter.
- Optimize for correctness first, process CPU second, RSS third.

**Execution posture:** measurement-driven.

**Test scenarios:**

- Each candidate produces evidence with queue depths recorded.
- Best candidate does not regress screenshot correctness or signal counts.
- Lower RSS is documented if achieved.

**Verification:**

- Best queue-depth candidate has repeatable evidence.
- Patch constants reflect the selected candidate, or the default remains unchanged if no safe win appears.

### U5 — Optional env-gated V4L2 poll/dequeue thread

**Goal:** Explore whether moving V4L2 queue servicing out of the submit callback reduces CPU/jitter or improves stability.

**Files:**

- Modify: `packages/moonlight-embedded/patches/0002-add-v4l2m2m-sdl-nv12-platform.patch` via scratch `src/video/v4l2m2m.c`
- Update docs if accepted or rejected.

**Approach:**

- Add a new gate if attempted, e.g. `MOONLIGHT_V4L2M2M_POLL_THREAD=1`.
- Poll thread blocks on `poll(direct_fd, POLLIN|POLLOUT|POLLPRI)` and drains OUTPUT, events, and CAPTURE.
- Submit path only queues OUTPUT and applies bounded backpressure.
- Preserve stateful lifecycle: CAPTURE setup only after source-change.
- Preserve no-deadlock rule: never free/drop pending frames while holding `direct_mtx` in a path that can re-enter via capture requeue.

**Execution posture:** high-risk spike. Only attempt after U2/U3/U4 if time remains and the current best is stable.

**Test scenarios:**

- Poll thread exits cleanly on cleanup.
- No deadlocks on stream stop.
- No spin loop: system busy does not increase materially.
- Correct screenshot, no GL/V4L2 errors.
- Benchmark shows lower CPU or smoother signals; otherwise reject and keep gated/off.

**Verification:**

- If accepted, evidence proves improvement over non-poll best.
- If rejected, document the reason and leave disabled or revert the code.

### U6 — Final overnight report and recommendation

**Goal:** Leave a clear morning handoff with best result, exact commits, run dirs, and next recommended action.

**Files:**

- Update: `docs/acceptance/moonlight-embedded-direct-v4l2-dmabuf-stage2-sobo-2026-05-23.md`
- Create if useful: `docs/solutions/performance-issues/moonlight-embedded-direct-v4l2-dmabuf-cpu-optimization-sobo-2026-05-24.md`
- Maybe update: `packages/moonlight-embedded/patches/README.md`

**Approach:**

- Summarize each candidate and why it was accepted/rejected.
- Record final best process CPU/system/RSS, duration, repetitions, and run dirs.
- State whether the best path is still research-only or ready for longer soak testing.
- Commit documentation separately from code if the code unit is already committed.

**Test scenarios:**

- Morning reader can find the exact store path and Sobo run dirs.
- Docs clearly distinguish default shipping path from experimental optimized path.
- Docs include color-correctness and geometry caveats.

**Verification:**

- Static checks pass.
- `git status` is clean or only contains intentionally uncommitted scratch/evidence files.
- Final commit log is atomic and readable.

## Overnight Execution Strategy

1. Run U1 first; establish a credible baseline.
2. Implement U2; this is the highest-confidence CPU win.
3. Implement U3; low-risk copy reduction.
4. Run U4 matrix only if U2/U3 are stable.
5. Attempt U5 only if there is enough runway and the best path is still above the likely floor.
6. Always finish with U6 documentation, even if U5 is abandoned.

## Stop / Pause Conditions

Pause for the user only if:

- A change would make the experimental path default.
- A change requires rootfs/profile/kiosk wiring.
- A change would discard the known-good color-correct Stage 2 path.
- Sobo/Sunshine pairing breaks in a way that cannot be recovered with the known keydir/host cleanup steps.
- Hardware errors suggest VPU/DRM instability beyond ordinary stream restart behavior.

Otherwise, proceed autonomously, prefer env-gated experiments, and leave evidence.

## Verification Checklist

For every accepted code change:

- `guest/scripts/static-checks.sh` passes.
- Patch builds on Fuji as an aarch64 Nix derivation.
- Closure copies to Sobo.
- Sobo smoke produces a correct-color screenshot.
- Signal counts are recorded.
- CPU/RSS evidence is recorded in `/storage/.guest/runs/`.
- Atomic commit is created.

## Expected Outcome

The most plausible overnight win is cached per-CAPTURE-buffer EGLImage/texture state plus direct OUTPUT copy. A realistic target is:

```text
Current color-correct Stage 2: ~11.7% process CPU
Likely after U2/U3:          ~8–10% process CPU if import/copy overhead is significant
Stretch with safe U4/U5:     ~7–8% if queueing/threading also pays off
```

Anything lower should be treated skeptically until repeated and correlated with system busy, screenshots, and stream correctness signals.
