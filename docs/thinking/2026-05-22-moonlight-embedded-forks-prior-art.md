# Research: moonlight-embedded forks & prior art for FFmpeg DRM_PRIME on SM8550

_Sourced via GitHub REST API on 2026-05-22. All upstream issue/PR numbers and
fork URLs verified against api.github.com._

## TL;DR

- **Exactly one piece of relevant prior art exists**: upstream open PR **#932
  `praxis88/moonlight-embedded:ffmpeg-drm-prime`**, "Add FFmpeg V4L2 Request +
  DRM PRIME display backend." 393 LoC of `src/video/ffmpeg_drm.c`, plus
  CMakeLists / platform.[ch] / video.h plumbing.
- PR #932 covers ~70% of the work we need (FFmpeg DRM_PRIME consumer pattern,
  AVDRMFrameDescriptor extraction, platform registration). It does NOT match
  our target environment in two important ways — we will fork it.
- All ~50 forks of upstream moonlight-embedded are either stale or
  packaging-only. No second independent v4l2 / drm-prime implementation
  exists in the wild.

## Upstream PRs / issues — verified

Searched `repo:moonlight-stream/moonlight-embedded` for: `v4l2`, `DRM_PRIME`,
`dmabuf`, `ffmpeg hardware`, `freedreno`, `qualcomm`, `panfrost`.

| # | State | Type | Title | Relevance |
|---|---|---|---|---|
| **932** | **open** | **PR** | **Add FFmpeg V4L2 Request + DRM PRIME display backend** | **Direct prior art. Base our work on this.** |
| 859 | open | issue | Khadas Edge 2 installation issues | None — packaging only |
| 856 | open | issue | "failed to open X display" on OrangePi | None |
| 809 | open | issue | v4l2 support on Raspberry Pi | Old feature request, no patch |
| 776 | open | issue | no audio + no video stream on client (RPi2) | None |
| 573 | open | issue | Vero 4K support | None |
| 876 | closed | issue | Rockchip platform issue | None |
| 875 | closed | issue | rk_setup: Assertion 'plane_id' failed | Adjacent — rkmpp on rk3588 plane allocation |
| 861 | closed | issue | failed to stream on rk3588 sbc | None |
| 626 | closed | PR | Rockchip integration tested on ODROID-N1 | Historical context for current `rk` platform |

Searches for `DRM_PRIME` and `dmabuf` returned **0 results** other than PR
#932's body text. There is no second design proposal in flight.

## PR #932 details

```
branch  : praxis88/moonlight-embedded:ffmpeg-drm-prime @ 4ecbed5
base    : moonlight-stream/moonlight-embedded:master   @ f7dc33c
size    : +518/-2 across 6 files (1 commit)
created : 2026-05-16 (6 days old at time of research)
status  : open, mergeable=true, mergeable_state=unstable
author  : praxis88
```

Files changed:

| File | Δ |
|---|---|
| `CMakeLists.txt` | +13/-1 — `ENABLE_FFMPEG_DRM` cmake option, libdrm + libavcodec deps |
| `README-ffmpeg-drm.md` | +97 new — usage docs |
| `src/platform.c` | +11 — register `ffmpeg_drm` platform name |
| `src/platform.h` | +1/-1 — enum addition |
| `src/video/ffmpeg_drm.c` | +393 new — the actual implementation |
| `src/video/video.h` | +3 — export `decoder_callbacks_ffmpeg_drm` |

What PR #932 does (saved at `/tmp/me-research/pr932-ffmpeg_drm.c` for offline
study):

1. **DRM device init** — opens `/dev/dri/card{1,0}`, atomic mode, picks a
   connected connector + CRTC + a free overlay plane that supports
   `DRM_FORMAT_NV12`. Blanks every other plane on the CRTC at startup.
2. **FFmpeg setup** — `av_hwdevice_ctx_create(AV_HWDEVICE_TYPE_DRM,
   "/dev/dri/renderD128", ...)`, then `avcodec_find_decoder(AV_CODEC_ID_HEVC
   | _H264)` (the *generic* codec, not `_v4l2m2m`-suffixed), then
   `get_format` callback that returns `AV_PIX_FMT_DRM_PRIME` when offered.
3. **Decode** — `avcodec_send_packet` / `avcodec_receive_frame` on the
   moonlight callback thread; frames at `AV_PIX_FMT_DRM_PRIME` are
   `av_frame_clone`d and pushed to a one-slot display queue.
4. **Display thread** — `drmPrimeFDToHandle` → `drmModeAddFB2WithModifiers`
   (with fallback to `drmModeAddFB2`) → blocking atomic commit. Releases
   the previously-displayed FB after each commit.
5. **Cleanup** — signals display thread EOS, joins, disables the overlay
   plane, frees all DRM/FFmpeg objects.

Tested platform per PR description: RK3399 + rkvdec (V4L2 Request stateless),
1080p60 HEVC @ 20 Mbps, 2.7ms average decode, 0% drops.

## Why PR #932 is not directly usable on SM8550 (and what we keep)

### Mismatch 1: stateless vs stateful V4L2

PR #932 relies on FFmpeg's **V4L2 Request API hwaccels** (`rkvdec`,
`hantro`, `cedrus`), which are stateless: FFmpeg parses the bitstream and
issues per-frame `MEDIA_REQUEST` ioctls. This is selected automatically when
you set `AV_HWDEVICE_TYPE_DRM` and offer `AV_PIX_FMT_DRM_PRIME` in
`get_format`.

The **Qualcomm `iris` driver on SM8550 is stateful V4L2 M2M**, not
stateless. The right FFmpeg wrapper is `hevc_v4l2m2m` / `h264_v4l2m2m`
(libavcodec/v4l2_m2m_dec.c) — selected by name, not by hwaccel negotiation.

**Action:** replace
```c
codec = avcodec_find_decoder(id);
av_hwdevice_ctx_create(&hw_ctx, AV_HWDEVICE_TYPE_DRM, "/dev/dri/renderD128", NULL, 0);
codec_ctx->hw_device_ctx = av_buffer_ref(hw_ctx);
```
with
```c
codec = avcodec_find_decoder_by_name(
  (id == AV_CODEC_ID_HEVC) ? "hevc_v4l2m2m" : "h264_v4l2m2m");
/* hevc_v4l2m2m is a wrapper, not a hwaccel — no hw_device_ctx needed.
 * get_format still returns AV_PIX_FMT_DRM_PRIME when DRM_PRIME export is
 * available (FFmpeg ≥ 5.x exports DRM_PRIME from v4l2_m2m_dec by default
 * when V4L2 capture buffers come back with dmabuf fds). */
```

(Detail in `/tmp/me-research/brief-ffmpeg-drm-prime.md` §1 and §3.)

### Mismatch 2: KMS atomic display vs gamescope-wrapped EGL/GLES

PR #932 owns the display: it `drmSetMaster`s implicitly via `O_RDWR`, picks
its own CRTC, and does atomic page flips. **Our process runs inside
gamescope**, which already owns DRM master. We cannot do KMS at all — we
must render into an SDL2 GL context (the same path `src/video/sdl.c` uses
for software decode), but using `EGLImage` import of the DMA-buf instead of
a CPU memcpy.

**Action:** keep the FFmpeg/AVDRMFrameDescriptor extraction half of
PR #932; replace the entire `drm_init` / `display_loop` / `release_fb` /
KMS-atomic-commit half with:
- `EGL_LINUX_DMA_BUF_EXT` import via `eglCreateImageKHR`
- `glEGLImageTargetTexture2DOES(GL_TEXTURE_EXTERNAL_OES, ...)`
- fragment shader using `samplerExternalOES`
- SDL2 GL window for the GL context (gamescope handles physical output)

Reference code for this half: **`src/video/rk.c`** (the existing rkmpp +
EGL/GLES platform in moonlight-embedded — described in
`/tmp/me-research/brief-rk-structure.md`). rk.c uses `mpp_buffer_get_fd` to
get a DMA-buf fd and then `eglCreateImageKHR` exactly like we need.

## Other forks — survey result

50 forks total. Most relevant filtered subset:

| Stars | Fork | Last push | Default branch | Relevant? |
|---|---|---|---|---|
| 3 | `TheChoconut/moonlight-embedded` | 2022-12 | master | No — stale, no decoder changes |
| 2 | `XK9274/moonlight-embedded-miyoo` | 2023-11 | master | No — Miyoo Mini packaging |
| 2 | `TheHacker66/moonlight-embedded` | 2022-08 | master | No |
| 1 | `amazingfate/moonlight-embedded` | 2024-01 | master + `rk3588-drm-type` branch | **Maybe** — rk3588-drm-type branch may have related KMS work, last touched 2024 |
| 1 | `krishenriksen/moonlight-embedded-rg351p` | 2021-02 | master | No — RG351P packaging |
| 1 | `NightVsKnight/moonlight-embedded` | 2022-12 | master | No |
| 0 | `numbqq/moonlight-embedded-deb` | 2025-05 | — | No — Khadas Edge2 Ubuntu deb packaging only, no decoder code |
| 0 | `NegXuan/moonlight-embedded-Wesion` | 2025-05 | — | No — Edge2 packaging only |
| 0 | `cgutman/moonlight-embedded-packaging` | 2025-11 | — | No — Dockerfiles only, by the upstream maintainer |
| 0 | `jjzhang166`, `emtee40`, `IVOES`, … | 2024-09 and earlier | various | No — generic mirrors, CodeQL scans, sprintf fixes |

Adjacent projects (different repos under `moonlight-stream` namespace or
related):

- `mariotaku/moonlight-tv` — LG webOS / RPi, has its own decoder
  abstractions; not directly relevant
- `xyzz/vita-moonlight` (PS Vita), `zoeyjodon/moonlight-N3DS`,
  `kbhomes/moonlight-switch` — console-specific forks, no Linux V4L2 work
- `dji-moonlight-embedded`, `vita-moonlight-motion`, etc. — niche, no
  relevance

**No fork has gone further than PR #932 for v4l2/drm-prime on a generic
Linux platform.** No fork has a `hevc_v4l2m2m`-specific platform.

## Reference implementations to cargo-cult from

In priority order:

1. **PR #932 `praxis88/ffmpeg-drm-prime`** — already saved at
   `/tmp/me-research/pr932.diff` (608 lines) and
   `/tmp/me-research/pr932-ffmpeg_drm.c` (393 lines). Base structural fork.
2. **Upstream `src/video/rk.c`** — already cloned at
   `/tmp/me-research/moonlight-embedded/src/video/rk.c`. The EGL/GLES half
   we need (eglCreateImageKHR + samplerExternalOES), wrapped around the
   parallel-universe rkmpp decoder. See
   `/tmp/me-research/brief-rk-structure.md` for the structural map.
3. **FFmpeg `libavcodec/v4l2_m2m_dec.c`** — the actual decoder we'll use,
   shows what `AV_PIX_FMT_DRM_PRIME` export looks like from the v4l2m2m
   side. See `/tmp/me-research/brief-ffmpeg-drm-prime.md` §6.
4. **mpv `video/out/hwdec/hwdec_drmprime.c`** — small, readable reference
   for the DRM_PRIME → EGL importer step in isolation.
5. **gstreamer `gst-plugins-base/gst-libs/gst/gl/gstglmemoryegl.c`** +
   `ext/gl/gstglupload.c` — production-quality DMA-buf → EGLImage → GL
   texture path.

## Recommendation: branching strategy

**Base our patch on praxis88/ffmpeg-drm-prime (PR #932) at commit `4ecbed5`,
not on upstream master.**

Rationale:

- PR #932 already does the CMake / `platform.[ch]` / `video.h`
  registration. Rebuilding that from scratch would duplicate work.
- The decoder-side scaffolding (codec context, packet/frame pump, EOS
  handling) is reusable as-is.
- Diffing our final patch against PR #932 (not against upstream master)
  produces a smaller, more focused patch.
- If PR #932 merges first, our patch becomes a clean follow-up (~150 LoC:
  swap KMS output for EGL output, add `hevc_v4l2m2m` decoder selection).
- If PR #932 stalls or gets rejected, we still have a self-contained
  +518 LoC patch we control.

Concretely, the patch file in `packages/moonlight-embedded/patches/` will:

1. **Either** include PR #932's commit `4ecbed5` as a vendored patch and a
   second patch with our deltas, **or** carry one combined patch that
   does both. (Recommend two patches for traceability — the first is
   labeled "vendored from upstream PR #932" and the second is our own.)

Renaming question to settle in the plan:

- PR #932 calls its platform `ffmpeg_drm`. For our patch, the platform that
  combines `hevc_v4l2m2m` decode + EGL/GLES (via SDL2) output should
  probably be named something else — candidates:
  - `v4l2m2m` (mirrors the FFmpeg decoder name)
  - `sdl_drm` (mirrors `sdl` + the DRM_PRIME import)
  - `ffmpeg_egl` (mirrors PR #932's `ffmpeg_drm` naming with the output
    swapped)
  My weak preference is `v4l2m2m` because that's the meaningful constraint
  (the decoder); the output is "whatever GL context Moonlight has," and
  for us that's SDL2-inside-gamescope.

## Open questions for the planner

1. Do we vendor PR #932 verbatim and add our delta, or do we rewrite as a
   single patch that supersedes it? (Recommend: two patches, vendored +
   delta.)
2. If we name the new platform `v4l2m2m`, do we also want to keep PR #932's
   `ffmpeg_drm` platform compiled in (useful on RK3399 / generic Linux
   boxes), or is the package single-purpose? Probably keep both — the
   marginal cost is a CMake flag.
3. Does our package need to ship a custom FFmpeg build? Stock nixpkgs
   `ffmpeg` should have `hevc_v4l2m2m` enabled (it's a non-default but
   standard libavcodec wrapper). Verify with
   `ffmpeg -hide_banner -decoders 2>&1 | grep v4l2m2m` against the
   nixpkgs ffmpeg we'd link. If absent, override
   `ffmpeg-full` or add a configure flag.

## Sources

- `https://api.github.com/repos/moonlight-stream/moonlight-embedded/pulls/932`
- `https://api.github.com/search/issues?q=repo:moonlight-stream/moonlight-embedded+...`
- `https://api.github.com/repos/moonlight-stream/moonlight-embedded/forks?sort=stargazers`
- `https://patch-diff.githubusercontent.com/raw/moonlight-stream/moonlight-embedded/pull/932.diff`
- `https://raw.githubusercontent.com/praxis88/moonlight-embedded/4ecbed5.../src/video/ffmpeg_drm.c`

Local copies:
- `/tmp/me-research/pr932.diff`
- `/tmp/me-research/pr932-ffmpeg_drm.c`
- `/tmp/me-research/pr932-README-ffmpeg-drm.md`
- `/tmp/me-research/gh/*.json` (raw API responses)
- `/tmp/me-research/moonlight-embedded/` (upstream HEAD clone)
