# Moonlight Embedded Artemis common-c audit

Date: 2026-05-23

## Scope

Audit the first-batch non-Apollo Artemis/Moonlight Noir `moonlight-common-c` fixes against the Moonlight Embedded v2.7.1 patch stack used by `nix-on-rocks`.

Compared trees:

- Moonlight Embedded scratch tree: `/tmp/moonlight-embedded-dev/7754442`
- Embedded common-c submodule: `third_party/moonlight-common-c @ b126e48`
- Artemis common-c reference: `/tmp/moonlight-android-artemis/app/src/main/jni/moonlight-core/moonlight-common-c @ c999436`
- Android upstream comparison: `/tmp/moonlight-android-upstream/app/src/main/jni/moonlight-core/moonlight-common-c @ 8af4562`

## Result

No Moonlight Embedded patch-stack change is needed for the first common-c batch. The pinned Embedded `moonlight-common-c` already contains the portable first-batch fixes:

| Candidate | Embedded status |
|---|---|
| RTSP DESCRIBE missing-payload guard | Present in `src/RtspConnection.c` (`RTSP DESCRIBE no content in response`) |
| Opus channel-count validation | Present in `src/RtspConnection.c` (`channelCount > AUDIO_CONFIGURATION_MAX_CHANNEL_COUNT`) |
| Sunshine surround Opus header tolerance | Present in `src/AudioStream.c` (`... || IS_SUNSHINE()`) |
| Non-picture data keyframe notification cleanup | Present in `src/VideoDepacketizer.c` (`bufferType != BUFFER_TYPE_PICDATA`) |
| ENet control-stream ping scheduling fix | Present in `src/ControlStream.c` (`Ensure we don't sleep through a ping`) |

The Artemis diff also carries Apollo/server-command, clipboard, file-transfer, 4:4:4, and empty-payload features. Those remain intentionally out of scope for the Sobo first batch.

## Follow-up implemented

Because the common-c fixes were already present, the implementation work focused on harness-level telemetry:

- `guest/launchers/remote-moonlight-runner.sh` now writes per-run `telemetry-samples.csv`, `telemetry-summary.txt`, and `signals.txt` alongside `env.txt`, `host-state.txt`, and `launch.log`.
- `guest/launchers/remote-moonlight-runtime-ab.sh` inlines each variant's telemetry and signal counts into `evidence.md`.
- `guest/launchers/remote-moonlight-direct-ab.sh` includes max observed temperature in run summaries and counts additional runtime signal patterns.

This preserves the default shipping path (`moonlight -platform v4l2m2m`) and keeps direct V4L2/dma-buf behavior env-gated only.
