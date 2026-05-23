# Artemis streaming improvements relevant to Moonlight Embedded

Date: 2026-05-23

## Scope

Research target:

```text
https://github.com/ClassicOldSong/moonlight-android.git
```

Local clones used during review:

```text
/tmp/moonlight-android-artemis      ClassicOldSong/moonlight-android @ 3397ec7
/tmp/moonlight-android-upstream     moonlight-stream/moonlight-android @ f10085f
/tmp/moonlight-embedded-upstream    moonlight-embedded v2.7.1 @ 7754442
```

This note isolates **streaming improvements** from Artemis/Moonlight Noir. It intentionally excludes Apollo-server-specific product features unless they reveal a generally useful streaming idea.

## Excluded as Apollo-specific

Do not treat these as Moonlight Embedded candidates unless we explicitly decide to support Apollo extensions later:

- `virtualDisplay=1`
- `scaleFactor=...`
- `VirtualDisplayCapable`
- `VirtualDisplayDriverReady`
- `ServerCommand`
- `actions/clipboard`
- Apollo permission flags
- app UUID / current-game UUID if only needed for Apollo behavior
- `LiSendExecServerCmd()`

## Easy-win / reward ranking

Sorted by likely **reward per unit of implementation risk** for Moonlight Embedded on Sobo:

| Rank | Candidate | Reward | Ease | Why it ranks here |
|---:|---|---|---|---|
| 1 | **RTSP/common-c guard fixes**: empty DESCRIBE guard, Opus channel validation, Sunshine surround header tolerance, keyframe notification cleanup | High | Easy | Small, localized protocol correctness fixes. Low renderer risk. Can prevent weird stream failures without touching the hot path. |
| 2 | **Control-stream ping scheduling fix** | High | Easy/medium | Portable common-c change with direct impact on connection health/latency. Needs careful comparison to embedded's current ENet loop, but should be much safer than renderer changes. |
| 3 | **Telemetry in harness/runtime logs**: RTT, packet loss, rendered/incoming FPS, bandwidth, decode/present timing | High | Medium | Makes every later experiment more trustworthy. Not a direct performance win, but highest compounding value. Start in harness if runtime hooks are invasive. |
| 4 | **Remote packet-size / NAT64 / IPv6 robustness** | Medium/high | Medium | Good portability and useful outside Sobo's LAN. More networking edge-case surface than rank 1–2, so validate carefully. |
| 5 | **`preferLowerDelays`-style dequeue/present timeout policy** | Medium/high | Medium | More likely to affect perceived latency than CPU. Should be env-gated and measured with telemetry first. |
| 6 | **`forceTightThresholds`-style pacing thresholds** | Medium | Medium | Potential latency/smoothness improvement, but easy to make judder worse. Needs rendered-FPS/drop evidence. |
| 7 | **Tiny output queue / latest-frame policy** | Potentially high | Hard/risky | Attractive latency idea, but Sobo already showed destabilization with direct-index display queue/IDR churn. Do only after telemetry. |
| 8 | **`warp` / `warp2` pacing hacks** | Unknown/potentially medium | Easy to add, risky to trust | Simple env knob, but hacky. Could increase drops, CPU, or pacing artifacts. Treat as research-only, not a default. |
| 9 | **Wi-Fi keepalive / empty payload experiment** | Situational | Medium | Only valuable if soak logs show Wi-Fi sleep/loss. Otherwise it adds traffic and noise for no known Sobo gain. |
| 10 | **4:4:4 negotiation** | Low for Sobo today | Medium/hard | Protocol work may be portable, but Iris/V4L2 decode support and handheld value are uncertain. |
| 11 | **AV1 capability path** | Low/unknown today | Hard | Only worth prioritizing if Sobo hardware decode support is confirmed stable and better than HEVC/H.264. |

Recommended first batch:

1. Cherry-pick/audit small common-c RTSP/control-stream fixes.
2. Add telemetry to the benchmark/soak harness.
3. Only then run env-gated pacing experiments.

## Highest-value non-Apollo candidates

### 1. Common-C transport and RTSP robustness bundle

Relevant Artemis common-c diff paths:

```text
app/src/main/jni/moonlight-core/moonlight-common-c/src/Connection.c
app/src/main/jni/moonlight-core/moonlight-common-c/src/ControlStream.c
app/src/main/jni/moonlight-core/moonlight-common-c/src/PlatformSockets.c
app/src/main/jni/moonlight-core/moonlight-common-c/src/PlatformSockets.h
app/src/main/jni/moonlight-core/moonlight-common-c/src/RtspConnection.c
app/src/main/jni/moonlight-core/moonlight-common-c/src/AudioStream.c
app/src/main/jni/moonlight-core/moonlight-common-c/src/VideoDepacketizer.c
```

Findings:

- NAT64 / 464XLAT handling was added.
- Private IPv4 synthesized to IPv6 can fall back to IPv4-only resolution.
- Remote packet-size caps distinguish IPv4/NAT64 from native IPv6:
  - IPv4 / NAT64: `1024`
  - native IPv6: `1184`
- Control-stream receive loop was changed to avoid sleeping through ENet ping deadlines.
- RTSP DESCRIBE now guards against missing payload.
- Opus channel count is validated before parsing.
- Sunshine surround audio Opus header variation is tolerated.
- Video depacketizer treats non-picture data as forcing keyframe notification, avoiding stale keyframe state.

Assessment for Sobo:

- Likely portable to Moonlight Embedded if its vendored `moonlight-common-c` is behind these changes.
- Mostly protocol/transport correctness, not Android-specific.
- Good candidate for a focused common-c refresh or cherry-pick review before deeper renderer work.

### 2. Pacing / latency hacks

Relevant Artemis paths:

```text
app/src/main/java/com/limelight/Game.java
app/src/main/java/com/limelight/preferences/PreferenceConfiguration.java
app/src/main/java/com/limelight/binding/video/MediaCodecDecoderRenderer.java
```

Artemis has several explicit latency/pacing knobs:

```text
FRAME_PACING_MIN_LATENCY
FRAME_PACING_BALANCED
FRAME_PACING_CAP_FPS
FRAME_PACING_MAX_SMOOTHNESS
preferLowerDelays
forceTightThresholds
framePacingWarpFactor
warp
warp2
```

#### `warp` / `warp2`

Artemis maps frame pacing string values to a multiplier:

```java
if (warpFactorStr.equals("warp")) {
    config.framePacingWarpFactor = 2;
} else if (warpFactorStr.equals("warp2")) {
    config.framePacingWarpFactor = 4;
}
```

Then it multiplies the chosen frame rate:

```java
if (prefConfig.framePacingWarpFactor > 0) {
    chosenFrameRate *= prefConfig.framePacingWarpFactor;
}
```

Interpretation:

- `warp` doubles the internal pacing target.
- `warp2` quadruples it.
- This is a hack to bias the renderer toward faster/lower-latency scheduling.

Sobo relevance:

- Worth treating as a **research-only pacing experiment**, not a shipping feature.
- Possible analogous env gate:

  ```sh
  MOONLIGHT_FRAME_PACING_WARP=2
  MOONLIGHT_FRAME_PACING_WARP=4
  ```

- Must be measured against frame drops, IDR churn, and visual smoothness. Our rejected direct-index queue showed that lower latency shortcuts can destabilize the stream.

#### `preferLowerDelays`

Artemis applies:

```java
decoderRenderer.setPreferLowerDelays(true);
decoderRenderer.setPreferLowerDelaysTimeoutUs(500);
prefConfig.framePacing = PreferenceConfiguration.FRAME_PACING_BALANCED;
```

Default balanced path uses:

```java
decoderRenderer.setPreferLowerDelays(false);
decoderRenderer.setPreferLowerDelaysTimeoutUs(2000);
prefConfig.framePacing = PreferenceConfiguration.FRAME_PACING_BALANCED;
```

Interpretation:

- Lower-delay mode keeps balanced pacing semantics but reduces decoder-output dequeue wait from about `2000us` to `500us`.
- It prefers responsiveness over absolute smoothness.

Sobo relevance:

- Android `MediaCodec.dequeueOutputBuffer()` timeout is not portable directly.
- The concept maps to SDL/V4L2 polling/dequeue and present-late/drop policy.

#### `forceTightThresholds`

Artemis can force tighter vsync-based thresholds:

```java
decoderRenderer.setForceTightThresholds(forceTight);
```

Sobo relevance:

- Conceptually portable to SDL/Wayland frame pacing.
- Could be tested as an env-gated threshold policy, but only with rendered-FPS and drop evidence.

#### Tiny output queue / latest-frame policy

Artemis keeps a very small output queue:

```java
OUTPUT_BUFFER_QUEUE_LIMIT = 2
```

It also has latest-frame style rendering behavior and `releaseWithPolicy()` logic that can present immediately when close to now.

Sobo relevance:

- Conceptually important: avoid accumulating old frames.
- Implementation risk is high. The direct-index/no-AVFrame queue spike rendered initially but destabilized into repeated IDR/drop behavior.
- Prefer conservative SDL/V4L2 queue policies and benchmark gates over invasive ownership changes.

### 3. Streaming telemetry

Relevant Artemis paths:

```text
app/src/main/java/com/limelight/binding/video/VideoStats.java
app/src/main/java/com/limelight/binding/video/MediaCodecDecoderRenderer.java
app/src/main/java/com/limelight/utils/PerformanceDataTracker.java
app/src/main/java/com/limelight/utils/TrafficStatsHelper.java
```

Artemis exposes or records:

- decoder name
- incoming FPS
- rendered FPS
- packet loss
- network latency / RTT
- bandwidth
- decode time
- host processing latency
- frame pacing mode
- post-stream latency summary
- performance history entries

Sobo relevance:

- High value and portable as harness/runtime observability.
- Good fit for `guest/launchers/remote-moonlight-direct-ab.sh` and future soak harnesses.
- Prefer adding telemetry before adding new pacing hacks.

### 4. Wi-Fi / packet-loss mitigation concept

Relevant Artemis paths:

```text
app/src/main/java/com/limelight/Game.java
app/src/main/java/com/limelight/nvstream/jni/MoonBridge.java
app/src/main/jni/moonlight-core/moonlight-common-c/src/ControlStream.c
app/src/main/jni/moonlight-core/moonlight-common-c/src/Limelight.h
```

Artemis uses Android Wi-Fi locks:

```java
WifiManager.WIFI_MODE_FULL_HIGH_PERF
WifiManager.WIFI_MODE_FULL_LOW_LATENCY
```

It also has a packet-loss prevention mode that sends an empty payload every 20ms:

```java
timerHandler.postDelayed(Game.this.backgroundPing, 20);
MoonBridge.sendEmptyPayload();
```

Native API:

```c
int LiSendEmptyPayload();
```

Comment:

```c
// workaround client side wifi sleeps
```

Sobo relevance:

- Android Wi-Fi locks are not portable.
- Linux equivalent would be OS/network-manager power-save policy plus measured keepalive experiments.
- Only pursue if Sobo shows Wi-Fi sleep, packet loss, or latency spikes during soak.

### 5. 4:4:4 codec negotiation research

Relevant Artemis common-c paths:

```text
src/Limelight.h
src/RtspConnection.c
src/SdpGenerator.c
```

Artemis adds codec/profile bits for:

```text
H.264 High 4:4:4 8-bit
HEVC RExt 4:4:4 8-bit
HEVC RExt 4:4:4 10-bit
AV1 High 4:4:4 8-bit
AV1 High 4:4:4 10-bit
```

And SDP attribute:

```text
x-ss-video[0].chromaSamplingType
```

Sobo relevance:

- Protocol work is portable.
- Iris VPU support is uncertain and likely not the next performance win for handheld streaming.
- Keep as low-priority research unless a desktop/product requirement needs sharper text/office use.

### 6. AV1 capability path

Relevant Artemis paths:

```text
MediaCodecDecoderRenderer.java
MediaCodecHelper.java
StreamConfiguration.java
moonlight-common-c/src/Limelight.h
moonlight-common-c/src/RtspConnection.c
```

Artemis has explicit AV1 decoder discovery, AV1 Main10 HDR checks, AV1 reference frame invalidation heuristics, and AV1 negotiation.

Sobo relevance:

- Only useful if the Sobo Iris/FFmpeg/V4L2 path exposes stable hardware AV1 decode for Moonlight streams.
- Do not prioritize over HEVC v4l2m2m stability/telemetry unless hardware capability is confirmed.

## Android-specific items to avoid porting directly

These are useful context but not direct Moonlight Embedded work:

- Android `MediaCodec` vendor keys:
  - `vendor.qti-ext-dec-low-latency.enable`
  - `vendor.qti-ext-output-sw-fence-enable.value`
  - `vendor.qti-ext-output-fence.enable`
  - `vendor.qti-ext-output-fence.fence_type`
  - MTK/Kirin/Exynos/Amlogic `MediaFormat` extensions
- Android `Choreographer` implementation details.
- Android `Surface` / `SurfaceTexture` lifecycle.
- Android Wi-Fi locks.
- Android input unbuffered dispatch.

Map the concepts to Linux/V4L2/SDL only after measurement.

## Recommended next plan shape

If continuing with non-Apollo streaming improvements, sequence the work like this:

1. **Audit Moonlight Embedded's vendored `moonlight-common-c` against Artemis/common-c transport changes.**
   - Identify which fixes are already upstream, which are fork-only, and which apply to v2.7.1.

2. **Add telemetry before new latency hacks.**
   - Rendered FPS, incoming FPS, packet loss, RTT, decode/present timing, bandwidth, CPU/RSS/temp.

3. **Run controlled pacing experiments.**
   - `balanced`
   - `prefer-low-delay` equivalent
   - `force-tight-thresholds` equivalent
   - `warp=2`
   - `warp=4`

4. **Gate everything behind environment variables.**
   - Default shipping remains FFmpeg `v4l2m2m` + SDL NV12.

5. **Only pursue Wi-Fi keepalive if soak evidence shows packet loss or latency spikes.**

## Decision snapshot

The Artemis fork contains real non-Apollo streaming ideas, but the most portable ones are not the Android MediaCodec vendor hacks. For Sobo, the best near-term value is:

1. common-c transport/RTSP robustness,
2. better telemetry,
3. carefully measured frame-pacing experiments inspired by `preferLowerDelays`, `forceTightThresholds`, and `warp` / `warp2`.
