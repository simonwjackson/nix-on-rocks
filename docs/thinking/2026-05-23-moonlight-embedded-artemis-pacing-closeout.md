# Moonlight Embedded Artemis/pacing exploration closeout

Date: 2026-05-23
Branch: `feat/moonlight-artemis-first-batch`
Status: ready for review/PR prep

## Scope

This note closes out the Artemis-inspired Moonlight Embedded exploration for Sobo. It references the durable evidence files and captures the decisions so future work can resume without replaying the session.

## Evidence index

- Artemis candidate ranking and non-Apollo scope: `docs/thinking/2026-05-23-artemis-streaming-improvements-for-moonlight-embedded.md`
- Common-c audit: `docs/acceptance/moonlight-embedded-artemis-common-c-audit-2026-05-23.md`
- Initial pacing experiments: `docs/acceptance/moonlight-embedded-v4l2m2m-pacing-experiments-2026-05-23.md`
- Wi-Fi pacing validation: `docs/acceptance/moonlight-embedded-v4l2m2m-wifi-pacing-2026-05-23.md`
- Final gamescope launcher A/B: `docs/acceptance/moonlight-embedded-gamescope-launcher-ab-2026-05-23.md`
- Future warp plan: `docs/plans/2026-05-23-002-moonlight-embedded-warp-pacing-exploration-plan.md`
- Supported-path decision: `docs/solutions/tooling-decisions/moonlight-embedded-sm8550-v4l2m2m-supported-path-sobo-2026-05-23.md`

## What landed

Relevant commits on `feat/moonlight-artemis-first-batch`:

```text
ae436b9 docs(moonlight-embedded): validate gamescope launcher baseline
02c7343 docs(moonlight-embedded): record wifi pacing baseline
204f0f3 feat(moonlight-embedded): add env-gated pacing experiments
52de6e9 fix(moonlight-embedded): use wayland gamescope backend for baselines
ac6d5c5 feat(moonlight-embedded): add streaming telemetry harness evidence
```

The work added:

- telemetry artifacts in the Moonlight harnesses,
- a real launcher fix: gamescope defaults to Wayland backend instead of Sobo-crashing SDL backend,
- env-gated v4l2m2m pacing research knobs,
- acceptance evidence for local, Wi-Fi, and gamescope launcher paths.

## Runtime decisions

Default remains unchanged:

```sh
moonlight -platform v4l2m2m ...
```

Research-only knobs:

```sh
MOONLIGHT_V4L2M2M_PACING=prefer-low-delay
MOONLIGHT_V4L2M2M_TIGHT_THRESHOLDS=1
MOONLIGHT_V4L2M2M_TIGHT_LATE_US=25000
```

Do not make these default based on current evidence.

Direct V4L2/dma-buf remains research-only behind its existing gates:

```sh
MOONLIGHT_V4L2M2M_DIRECT=1
MOONLIGHT_V4L2M2M_DMABUF=1
```

## Findings

### Common-c

The targeted portable Artemis/common-c fixes were already present in the pinned embedded common-c, so no new common-c patch was needed.

### Gamescope launcher

The launcher problem was real and merge-worthy:

- `gamescope --backend sdl` segfaulted on Sobo.
- Wayland/default backend worked.
- The launcher now defaults to `GS_BACKEND=wayland`, with override available.
- Final A/B through the real launcher completed with exit `0` for both `sdl` and `v4l2m2m`.

### Hardware decode value

Final launcher-path A/B confirmed the core value proposition:

```text
sdl software decode: 73.6% CPU, max temp 41.4 C
v4l2m2m hardware decode + SDL NV12: 15.1% CPU, max temp 37.0 C
```

The hardware path also had cleaner stream signals in the final run:

```text
v4l2m2m: Waiting for IDR=0, Unrecoverable=0, presentation(SDL)=1
```

### Pacing experiments

The `prefer-low-delay` and tight-threshold knobs were safe enough to keep as research scaffolding but did not produce a clear win.

Wi-Fi did not change the decision: default v4l2m2m was already clean over a strong 5 GHz Wi-Fi link.

### Warp

`warp` / `warp2` were not implemented in this branch. They are captured as deferred research in:

```text
docs/plans/2026-05-23-002-moonlight-embedded-warp-pacing-exploration-plan.md
```

Do not pursue them unless there is a real latency metric or reviewer request. They are pacing hacks, not CPU optimizations.

## Merge-worthy pieces

This branch is merge-worthy as an observability/baseline-quality branch:

1. **Harness telemetry** makes future Moonlight runs comparable.
2. **Gamescope Wayland backend fix** resolves a real Sobo launcher crash path.
3. **Pacing env gates** are harmless by default and useful for future research.
4. **Acceptance docs** prove that defaults remain safe and v4l2m2m remains the right shipping path.

The branch should not be sold as a runtime speedup. It is a reliability, observability, and research-scaffolding improvement.

## Closeout recommendation

Before PR/merge:

1. Run structured code review focused on shell harness correctness and patch-stack defaults.
2. Ensure PR description clearly says:
   - no common-c runtime patch was needed,
   - defaults are unchanged,
   - gamescope SDL backend crash was fixed by defaulting to Wayland,
   - pacing knobs are research-only,
   - v4l2m2m remains much lower CPU than SDL software decode.
3. Preserve unrelated untracked files; do not include them in this branch.

No further runtime experiments are recommended unless review asks for them.
