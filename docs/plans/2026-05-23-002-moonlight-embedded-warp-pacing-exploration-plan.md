# Moonlight Embedded warp pacing exploration plan

Date: 2026-05-23
Status: deferred research
Branch context: `feat/moonlight-artemis-first-batch`

## Purpose

This plan captures a future-only exploration of Artemis-style `warp` / `warp2` frame pacing for Moonlight Embedded on Sobo. It is intentionally **not** part of the current shipping baseline.

The current conclusion remains: default `-platform v4l2m2m` with balanced SDL NV12 presentation is the supported path; existing pacing knobs stay research-only.

## Background references

Read these before starting:

- Candidate ranking: `docs/thinking/2026-05-23-artemis-streaming-improvements-for-moonlight-embedded.md`
- Pacing experiment results: `docs/acceptance/moonlight-embedded-v4l2m2m-pacing-experiments-2026-05-23.md`
- Wi-Fi pacing results: `docs/acceptance/moonlight-embedded-v4l2m2m-wifi-pacing-2026-05-23.md`
- Gamescope launcher A/B: `docs/acceptance/moonlight-embedded-gamescope-launcher-ab-2026-05-23.md`
- Shipping decision: `docs/solutions/tooling-decisions/moonlight-embedded-sm8550-v4l2m2m-supported-path-sobo-2026-05-23.md`

## What `warp` means at a high level

In Artemis, `warp` and `warp2` are frame-pacing multipliers:

```text
warp  -> internal pacing target x2
warp2 -> internal pacing target x4
```

If the stream/display target is 60 FPS, the client behaves more like it is scheduling against 120 Hz or 240 Hz deadlines. This does not make decode faster. It attempts to reduce client-side waiting/buffering by making present timing more aggressive.

Expected possible upside:

- lower input-to-display latency if the client is over-buffering,
- less time spent waiting for conservative vsync/pacing deadlines,
- fresher-frame bias under ideal conditions.

Expected possible downside:

- more CPU wakeups,
- more judder,
- more frame drops,
- worse battery/thermals,
- sensitivity to network/compositor jitter,
- possible IDR/drop churn if ownership or pacing becomes unstable.

## Preconditions before testing

Only start this if at least one is true:

1. A human-visible latency problem remains after the current default baseline.
2. A repeatable latency metric exists that can show improvement/regression.
3. Reviewers explicitly request closure on Artemis `warp` behavior.

Do **not** run this just to chase lower process CPU. `warp` is not expected to reduce CPU.

## Proposed env-gated interface

Keep this runtime-only and research-only:

```sh
MOONLIGHT_FRAME_PACING_WARP=2
MOONLIGHT_FRAME_PACING_WARP=4
```

Alternative if implementation is v4l2m2m-specific:

```sh
MOONLIGHT_V4L2M2M_FRAME_PACING_WARP=2
MOONLIGHT_V4L2M2M_FRAME_PACING_WARP=4
```

Default must remain equivalent to:

```sh
MOONLIGHT_FRAME_PACING_WARP=1
```

or unset.

## Implementation guidance

Prefer the smallest possible timing-only patch:

- Do not change decoder selection.
- Do not change default queue sizes.
- Do not change direct V4L2/dma-buf defaults.
- Do not make this a CLI/product option.
- Log the active mode clearly in verbose output, e.g.:

```text
v4l2m2m: pacing=balanced warp=2 vsync=...
```

Likely integration point is the v4l2m2m SDL NV12 presentation/pacing logic added in the Moonlight Embedded patch stack. Apply the multiplier only to frame-deadline / lateness-threshold math, not to actual stream negotiation.

## Measurement matrix

Use Sobo, built on Fuji, copied with `nix copy --no-check-sigs`.

Start with 30s smoke runs:

```text
baseline default v4l2m2m, no env gates
MOONLIGHT_FRAME_PACING_WARP=2
MOONLIGHT_FRAME_PACING_WARP=4
```

Then only if smoke is sane, run 180s or 5–10 minute comparisons:

```text
baseline default v4l2m2m
warp=2
```

Only test `warp=4` beyond smoke if `warp=2` has clean signals and a real latency/smoothness reason.

## Required signals

Capture at minimum:

- process CPU %,
- RSS MiB,
- max temp C,
- presentation observed,
- `Network dropped`,
- `Frames dropped`,
- `Waiting for IDR`,
- `Unrecoverable`,
- full `launch.log`,
- telemetry summary/signals artifacts,
- subjective visual smoothness if a human is watching.

If possible, add or use a real latency metric before judging success. Without latency evidence, a clean run is only proof that warp did not immediately break the stream.

## Stop conditions

Stop and reject the variant if any of these appear repeatedly:

- sustained `Waiting for IDR`,
- `Unrecoverable` events,
- meaningful frame drops,
- visible judder/stutter,
- CPU materially higher without latency benefit,
- thermal rise compared with default,
- launcher instability.

## Success criteria

Do not promote warp unless all are true:

1. Default behavior remains unchanged.
2. Warp run has clean stream signals.
3. Human-visible smoothness is not worse.
4. A latency metric or repeated human test shows a clear improvement.
5. CPU/thermal cost is acceptable.

If only CPU/RSS/temp are measured and no latency metric exists, keep warp as research-only regardless of results.

## Expected decision bias

Given current evidence, expect `warp` to remain research-only. The default path is already stable over gamescope/Wayland and Wi-Fi, while `prefer-low-delay` and tight-threshold experiments did not justify changing defaults.
