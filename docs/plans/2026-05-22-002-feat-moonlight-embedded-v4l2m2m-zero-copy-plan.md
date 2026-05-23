---
title: Add SM8550 Zero-Copy v4l2m2m + EGL DMA-buf Platform to moonlight-embedded
type: feat
status: active
date: 2026-05-22
verify_command: "nix eval --impure --expr '(import packages/moonlight-embedded/manifest.nix).version'"
origin: nix-sm8550@2fe90b1 (migrated 2026-05-22)
---

> **Migration note (2026-05-22):** This plan was authored in the sibling
> `nix-sm8550` repository and migrated here ahead of the monorepo merge
> restructure (`docs/plans/2026-05-22-001-refactor-monorepo-merge-layered-restructure-plan.md`).
> The package files referenced below (`packages/moonlight-embedded/...`)
> now live in this repo at the post-refactor target paths. The full
> `nix build .#moonlight-embedded` verification command only becomes
> runnable once the merge plan's U10 (flake collapse) lands; until then
> the manifest's syntactic well-formedness is the only verifiable
> property in this tree. The dev-checkout helper at
> `scripts/moonlight-embedded-dev-checkout.sh` works today against the
> manifest pin without needing a flake.

# Add SM8550 Zero-Copy v4l2m2m + EGL DMA-buf Platform to moonlight-embedded

## Summary

Ship two patches under `packages/moonlight-embedded/patches/` so the package
gains a hardware HEVC/H.264 decode path on Qualcomm SM8550 handhelds with no
CPU-side frame copy. Patch 0001 vendors upstream
[PR #932](https://github.com/moonlight-stream/moonlight-embedded/pull/932)
("Add FFmpeg V4L2 Request + DRM PRIME display backend") verbatim so we inherit
its CMake / platform-registration plumbing. Patch 0002 forks PR #932's
`ffmpeg_drm` platform into a sibling `v4l2m2m` platform that selects FFmpeg's
stateful `hevc_v4l2m2m` / `h264_v4l2m2m` decoders by name and renders into a
GL_TEXTURE_EXTERNAL_OES sampled from an `EGL_LINUX_DMA_BUF_EXT`-imported
`AVDRMFrameDescriptor`, against an SDL2 GL context (so it works when wrapped
by gamescope, which owns DRM master).

---

## Problem Frame

The `packages/moonlight-embedded/` scaffold (commit `9399c0f`) ships vanilla
upstream v2.7.1 with only software decode (`-platform sdl`). On Sobo (SM8550
+ ROCKNIX) this means the CPU decodes 1080p/4K HEVC into RGB and SDL2 uploads
each frame to a GL texture every vsync — burning power, capping at modest
bitrates, and visibly stuttering on Main 10 streams.

The substrate already exposes Venus/iris V4L2 nodes
(`/dev/video0`, `/dev/video1`) inside the guest after the v4l2 passthrough
fix shipped in `rocknix:patches/rocknix/0006-rocknix-guest-substrate.patch`
(commit `537b92f`). FFmpeg already ships `hevc_v4l2m2m` / `h264_v4l2m2m`
stateful M2M wrappers, and freedreno on Adreno 740 supports
`EGL_EXT_image_dma_buf_import` with QCOM-tiled and linear NV12 modifiers.
What's missing is a moonlight-embedded video platform that wires the two
ends together.

PR #932 solves ~70% of the structural problem upstream: it adds the
CMake/platform-registration plumbing for an "FFmpeg DRM_PRIME" platform and
demonstrates the `AVDRMFrameDescriptor` consumer pattern. It cannot run as-is
on SM8550 because (a) it relies on FFmpeg's V4L2 Request stateless hwaccel
(matches rkvdec/hantro/cedrus, not iris stateful M2M) and (b) it owns the
display via KMS atomic commits, which conflicts with gamescope on our
runtime.

---

## Requirements

- R1. `nix build .#moonlight-embedded` produces a `bin/moonlight` that
  advertises `v4l2m2m` (and `ffmpeg_drm`) in addition to the existing
  upstream platforms when the build host has the relevant
  cmake-feature-detected libraries.
- R2. Patch 0001 lands verbatim from PR #932 (`praxis88/moonlight-embedded`
  branch `ffmpeg-drm-prime` at commit `4ecbed5`) so traceability and rebase
  cost are minimal if upstream merges it.
- R3. Patch 0002 adds a new `v4l2m2m` platform that:
  - Selects `avcodec_find_decoder_by_name("hevc_v4l2m2m")` /
    `"h264_v4l2m2m")` explicitly.
  - Negotiates `AV_PIX_FMT_DRM_PRIME` via `get_format`.
  - Imports each frame's dma-buf fd(s) via
    `eglCreateImageKHR(EGL_LINUX_DMA_BUF_EXT)` with explicit per-plane
    modifier attribs.
  - Binds to `GL_TEXTURE_EXTERNAL_OES` and samples via `samplerExternalOES`
    in the fragment shader.
  - Renders into an SDL2 GL context (the same surface `sdl.c` uses today),
    so it works under gamescope without owning DRM master.
- R4. The patch stack must build cleanly against the existing buildInputs
  set (`ffmpeg`, `libdrm`, `libglvnd`, `SDL2`); any new buildInput is
  recorded in `manifest.nix` and called out in the package README.
- R5. The `manifest.nix` `expectedPlatforms` list and the package
  README's "Status" table must be updated when each patch lands so the
  package's advertised contract matches what the binary actually offers.
- R6. The DMA-buf fd lifecycle must be safe: the `AVFrame` reference is
  held until the EGLImage is no longer in flight; the EGLImage is destroyed
  before the AVFrame is unrefed. No `eglCreateImageKHR` followed by an
  early `close(fd)`.
- R7. The patch must degrade cleanly on systems where either (a) the
  decoder isn't present, (b) the DMA-buf modifier isn't accepted by the
  EGL importer, or (c) the output format isn't sampleable. Fall back to
  `-platform sdl` software decode with a single clear log line, not a
  silent crash.
- R8. End-to-end smoke validation is performed on Sobo by streaming
  Sunshine's "Desktop (Sway)" app via `gamescope` wrap, captured in
  `docs/solutions/` as a learning when complete. Validation is gated by R1
  but not blocking on patch-land.

---

## Scope Boundaries

- Do not own the Sway/Gamescope launcher, keydir layout, or portal
  demote/restore policy. Those live in `nix-on-rocks` (per the
  cross-repo boundary established when this monorepo was carved out).
- Do not own host-side Sunshine app stickiness recovery. Distinct bug,
  server-side, not a moonlight-embedded concern.
- Do not implement an HDR path. SM8550 HDR is its own multi-week piece of
  work involving Mesa, kernel, and Sunshine signaling; explicitly deferred.
- Do not change the upstream `sdl`, `rk`, `x11`, `pi`, `imx`, `aml`, or
  `x11_vdpau` platforms. The new platform is additive.
- Do not vendor or rebuild FFmpeg. Use the nixpkgs `ffmpeg` as-is and
  verify at evaluation time that `hevc_v4l2m2m` is present in its
  configuration; surface a clear cmake-time error if absent (deferred to
  Implementation, not blocking the plan).

### Deferred to Follow-Up Work

- HDR / Main 10 wide-gamut path: separate plan after the SDR path is
  working and stable. Likely needs `P010` output, freedreno P010 external
  OES sampling validation, and Sunshine HDR-mode negotiation.
- nix-on-rocks consumer wiring: a follow-up commit there adds `nix-sm8550`
  as a flake input and references
  `nix-sm8550.packages.${system}.moonlight-embedded` from the guest
  module, replacing the current `nix shell nixpkgs#moonlight-embedded`
  ephemeral pattern.
- Upstreaming patch 0002 to moonlight-embedded as a PR. Worth doing once
  it's been validated on real hardware and PR #932's fate is clearer.
- Iris-specific output-format negotiation tuning (Q08C vs linear NV12 vs
  P010) for best performance under different stream profiles. First cut
  uses whatever the decoder defaults to, accepts the modifier the EGL
  importer accepts, and degrades if the modifier is unsupported.

---

## Context & Research

### Relevant Code and Patterns

- Upstream `src/video/rk.c` (763 LoC, in
  `/tmp/me-research/moonlight-embedded/src/video/rk.c`): the existing
  EGL/GLES platform built around rkmpp. Structural model for the EGL-import
  half of patch 0002 — same `eglCreateImageKHR` + `GL_TEXTURE_EXTERNAL_OES`
  + `samplerExternalOES` shape.
- Upstream PR #932 `src/video/ffmpeg_drm.c` (393 LoC, in
  `/tmp/me-research/pr932-ffmpeg_drm.c`): the FFmpeg DRM_PRIME consumer
  scaffolding patch 0002 forks from.
- Upstream `src/video/sdl.c` (87 LoC): the existing software-decode
  platform; shows how to acquire an SDL2 GL context and run a render loop
  without owning DRM.
- Upstream `src/video/ffmpeg.c` + `ffmpeg.h`: shared FFmpeg decoder
  primitives (`ffmpeg_init`, `ffmpeg_decode`, `ffmpeg_get_frame`) the
  existing `x11.c` and `sdl.c` already use. Reuse rather than reimplement
  if the existing `ffmpeg_init` accommodates `hw_device_ctx` selection;
  otherwise add a parallel `ffmpeg_init_drm_prime` entry point.
- Local `packages/cemu/` and `packages/steam/`: the data-only-manifest +
  derivation + package-README + static-check pattern this package mirrors.

### Research briefs (local)

- `/tmp/me-research/brief-rk-structure.md` (26 KB, 345 lines): scout's
  structural map of `rk.c` and the platform contract. Section 6 has a
  file-by-file change checklist for the new platform.
- `/tmp/me-research/brief-ffmpeg-drm-prime.md` (32 KB, 772 lines):
  FFmpeg `AV_PIX_FMT_DRM_PRIME` + `AVDRMFrameDescriptor` API contract,
  dma-buf lifecycle discipline, EGL attrib list for NV12 plane import,
  10-bit considerations, fallback patterns.
- `/tmp/me-research/brief-forks-prior-art.md`: GitHub-API-verified survey
  of upstream PRs and ~50 forks. Concludes that PR #932 is the only
  relevant prior art; nothing else has shipped v4l2m2m / DRM_PRIME work.

### Institutional learnings

- `docs/solutions/runtime-errors/guest-moonlight-no-v4l2m2m-decoder-missing-video-passthrough-rocknix-2026-05-22.md`
  (in the parent `nix-on-rocks` repo) documents the substrate-side v4l2
  passthrough fix that is a prerequisite for any HW decode option, including
  this one.

### External references

- moonlight-embedded PR #932:
  <https://github.com/moonlight-stream/moonlight-embedded/pull/932>
- FFmpeg `libavcodec/v4l2_m2m_dec.c` (canonical stateful M2M decoder
  source): <https://git.ffmpeg.org/gitweb/ffmpeg.git/tree/HEAD:/libavcodec>
- mpv `video/out/hwdec/hwdec_drmprime.c`: small readable reference for the
  DRM_PRIME → EGL importer step in isolation.
- EGL `EGL_EXT_image_dma_buf_import` /
  `EGL_EXT_image_dma_buf_import_modifiers` extension specs (Khronos
  registry).

---

## Key Technical Decisions

- **Vendor PR #932 verbatim as patch 0001, then add our delta as patch
  0002**. Two patches instead of one combined patch. Rationale:
  traceability (PR #932 is reviewable in isolation against its origin),
  smaller delta to review for our novel work, low rebase cost if PR #932
  merges upstream (delete patch 0001, our patch 0002 still applies).
  *Alternative considered:* one combined patch. Rejected because it
  obscures the boundary between "what upstream is proposing" and "what
  we're adding," and inflates review surface.
- **Platform name: `v4l2m2m`**. Mirrors the FFmpeg decoder family
  (`hevc_v4l2m2m`) — the meaningful axis on this hardware path is the
  decoder, not the display surface. Sibling to PR #932's `ffmpeg_drm`.
  *Alternatives considered:* `sdl_drm` (mirrors `sdl` + the DRM_PRIME
  import); `ffmpeg_egl` (mirrors PR #932's `ffmpeg_drm` with EGL output
  swap). Rejected because they name the output technology; `v4l2m2m`
  names the constraint that determines whether the platform works at all.
- **Render into an SDL2 GL context, not GBM/KMS or raw EGL**. The Sobo
  runtime path wraps moonlight in gamescope, which already owns DRM
  master. SDL2 already abstracts away whether we're on Wayland, X11, or
  KMS, and the existing `sdl.c` proves SDL2 is in our buildInputs. The
  new platform's `setup` opens an SDL2 GL window; the render loop calls
  SDL2's GL swap. *Alternative considered:* raw EGL on a GBM surface
  (matches `rk.c`). Rejected because it doesn't compose with gamescope.
- **Reuse `src/video/ffmpeg.c` primitives where possible; add a small
  `ffmpeg_init_drm_prime` parallel entry point if needed**. The existing
  `ffmpeg_init` builds for software decode by default; the simplest
  delta is a sibling that sets `decoder_ctx->get_format` to a
  DRM_PRIME-preferring callback and pre-selects the decoder by name.
  Resolve at implementation time whether to fold the change into
  existing `ffmpeg_init` (less duplication) or sibling it (no behavioral
  change for the existing path).
- **No `av_hwdevice_ctx_create` for the stateful path**. Per
  `brief-ffmpeg-drm-prime.md` §3, `hevc_v4l2m2m` is a wrapper decoder,
  not a hwaccel — it negotiates its own V4L2 device internally and
  exports DRM_PRIME from the V4L2 CAPTURE-side dma-buf fds without
  needing an external `AV_HWDEVICE_TYPE_DRM` context. PR #932 needs the
  hwdevice context because it uses generic FFmpeg hwaccels; we don't.
- **DMA-buf modifier negotiation is best-effort**. Try the modifier the
  AVDRMFrameDescriptor reports; if `eglCreateImageKHR` returns
  `EGL_NO_IMAGE_KHR`, log once and fall through to the next frame (or
  exit cleanup with a "v4l2m2m platform unsupported on this driver,
  rerun with `-platform sdl`" message). Format-negotiation tuning
  (forcing linear NV12, requesting P010, etc.) is deferred until we see
  what the iris driver gives us.
- **Build is gated by a CMake option, off by default**. Patch 0002 adds
  `-DENABLE_V4L2M2M=ON` to `manifest.nix` so the package builds it; the
  patch leaves the CMake default off so unrelated downstreams who pick up
  patch 0002 in the future don't pay for a platform they don't have the
  deps for.

---

## Open Questions

### Resolved During Planning

- Naming: `v4l2m2m` (see Key Technical Decisions).
- Vendoring vs single patch: vendor PR #932 separately (see Key Technical
  Decisions).
- Output surface: SDL2 GL context (see Key Technical Decisions).
- Decoder selection: by name, no `av_hwdevice_ctx_create` for the M2M
  wrapper (see Key Technical Decisions).
- Prior-art base: branch off PR #932 commit `4ecbed5`. Existing
  community forks were surveyed and none have gone further.

### Deferred to Implementation

- Exact `EGL_LINUX_DRM_FOURCC_EXT` value for whatever iris hands us
  (NV12 / P010 / a Q08C-flavored variant). Depends on what
  `AVDRMLayerDescriptor.format` reports at runtime; both `DRM_FORMAT_NV12`
  and `DRM_FORMAT_P010` are realistic candidates.
- Whether to add a small `ffmpeg_init_drm_prime` entry point or extend
  `ffmpeg_init` with an opt-in flag. Decide once we see the diff size.
- Whether the render loop drops frames on backpressure or blocks. PR
  #932's KMS thread drops; the SDL2 path probably wants the same to
  avoid stalling the decode pipeline behind vsync.
- Whether nixpkgs' `ffmpeg` ships with `--enable-v4l2-m2m` (default in
  recent versions, but worth verifying at cmake-configure time). If
  absent, surface a clear cmake error and document the fix in the
  package README.
- Whether to compile `src/video/ffmpeg.c` into the `v4l2m2m` shared lib
  (analogue of how the `rk` plugin links its own copies) vs. linking
  against the main binary's symbols. Likely the former; confirm when
  the patch is being shaped.

---

## High-Level Technical Design

> *This illustrates the intended end-to-end frame flow and is directional
> guidance for review, not implementation specification.*

```
[Sunshine HEVC over network]
            │
            ▼
moonlight callback thread
  v4l2m2m_submit_decode_unit(du)
    └─ avcodec_send_packet(ctx, pkt)
            │
            ▼
    while (avcodec_receive_frame(ctx, f) == 0)
            │
            ▼ f->format == AV_PIX_FMT_DRM_PRIME
       desc = (AVDRMFrameDescriptor*) f->data[0]
       enqueue(av_frame_clone(f))   # one-slot, drop-on-overflow
            │
            ▼
render thread (SDL2 GL ctx; gamescope owns the physical display)
  pop f
    ├─ for each layer/plane in desc:
    │     attribs = [EGL_LINUX_DRM_FOURCC_EXT, layer.format,
    │                EGL_WIDTH, f->width, EGL_HEIGHT, f->height,
    │                EGL_DMA_BUF_PLANE0_FD_EXT, desc->objects[oi].fd,
    │                EGL_DMA_BUF_PLANE0_OFFSET_EXT, plane.offset,
    │                EGL_DMA_BUF_PLANE0_PITCH_EXT, plane.pitch,
    │                EGL_DMA_BUF_PLANE0_MODIFIER_LO_EXT, mod & 0xffffffff,
    │                EGL_DMA_BUF_PLANE0_MODIFIER_HI_EXT, mod >> 32,
    │                # …plane1 attribs for NV12 chroma…
    │                EGL_NONE]
    ├─ image = eglCreateImageKHR(dpy, NO_CONTEXT, LINUX_DMA_BUF_EXT, NULL, attribs)
    ├─ glBindTexture(GL_TEXTURE_EXTERNAL_OES, tex)
    ├─ glEGLImageTargetTexture2DOES(GL_TEXTURE_EXTERNAL_OES, image)
    ├─ glDrawElements(...)                   # full-screen quad, samplerExternalOES
    ├─ SDL_GL_SwapWindow(win)                # gamescope handles physical present
    ├─ eglDestroyImageKHR(dpy, image)
    └─ av_frame_free(&f)                     # releases dma-buf back to decoder pool
```

The `samplerExternalOES` returns RGB directly when the EGL driver knows the
YUV→RGB conversion (BT.709 SDR for our case); no shader-side colorspace
math is needed for the first cut.

---

## Output Structure

```
packages/moonlight-embedded/
  patches/
    README.md                                   # per-patch rationale
    0001-vendored-ffmpeg-drm-prime-pr932.patch  # PR #932 verbatim
    0002-add-v4l2m2m-egl-platform.patch         # our delta
  package.nix                                   # (existing)
  manifest.nix                                  # (existing) — patches list updated
  README.md                                     # (existing) — Status table updated
```

The patches directory and its README are created by U2. The two patch
files arrive in U3 (vendored 0001) and U5 (authored 0002).

---

## Implementation Units

### U1. Add a moonlight-embedded development scratch workflow

**Goal:** Establish a reproducible upstream-checkout-and-iterate workflow
so patches 0001 and 0002 can be developed against the same source tree
the Nix derivation builds, validated ephemerally on Sobo, and exported as
`git diff`s without manual surgery.

**Requirements:** R2, R3 (enabling — neither patch can be authored
without a workflow for producing it).

**Dependencies:** None.

**Files:**
- Create: `scripts/moonlight-embedded-dev-checkout.sh` (a small helper
  that clones upstream at the manifest-pinned commit into a scratch
  directory and applies any patches already present, leaving a working
  tree the user can hack on).
- Modify: `packages/moonlight-embedded/README.md` (add a "Developing the
  patch stack" section that explains the workflow).

**Approach:**
- The helper reads the source pin from `packages/moonlight-embedded/manifest.nix`
  via `nix eval`.
- It clones into `/tmp/moonlight-embedded-dev/<short-rev>` (idempotent).
- It applies each `patches/*.patch` in order with `git am --3way` so the
  scratch tree mirrors what the derivation will build.
- It prints next-step instructions (how to build ephemerally on Sobo
  via `nix shell`, how to extract a diff with `git format-patch`).

**Patterns to follow:**
- `scripts/static-checks.sh` (shellcheck-clean, `set -euo pipefail`,
  `command -v` for tool detection).

**Test scenarios:**
- Test expectation: none — this is developer ergonomics tooling. The
  static check (U6) verifies the script is shellcheck-clean.

**Verification:**
- Running `bash scripts/moonlight-embedded-dev-checkout.sh` against a
  fresh `/tmp` produces a clean checkout at the manifest-pinned commit.
- Running it a second time is idempotent (does not error, does not
  re-clone, applies the same patches).

---

### U2. Create the patches directory and per-patch README

**Goal:** Establish `packages/moonlight-embedded/patches/` with a README
that documents per-patch rationale and the patch-application order. This
slot is referenced by `manifest.patches` and consumed by the derivation;
having it empty-but-present makes the U3 and U5 diffs purely additive.

**Requirements:** R2, R3 (substrate for both patches).

**Dependencies:** None.

**Files:**
- Create: `packages/moonlight-embedded/patches/README.md`

**Approach:**
- The README is short: it names each planned patch, its origin, its
  scope, and the rule that patch ordering is significant (0001 lands
  the platform-registration plumbing; 0002 depends on it).
- No `.gitkeep`-style hacks needed because the README itself anchors
  the directory.

**Patterns to follow:**
- `packages/cemu/` keeps patch files flat at the package root with a
  numeric prefix (`000-`, `002-`, `003-`); we choose a `patches/`
  subdirectory because we expect more than three over time and want a
  per-patch README to document rationale.

**Test scenarios:**
- Test expectation: none — directory scaffold. Covered indirectly by U6
  static checks once the patches list in `manifest.nix` references
  `./patches/...`.

**Verification:**
- `packages/moonlight-embedded/patches/README.md` exists and lists the
  two planned patches.
- `nix flake check --no-build` still passes.

---

### U3. Vendor upstream PR #932 as patch 0001

**Goal:** Land PR #932 (`praxis88/moonlight-embedded@4ecbed5`)
verbatim as `0001-vendored-ffmpeg-drm-prime-pr932.patch`, wire it into
`manifest.patches`, and confirm the resulting build produces a binary
that advertises `-platform ffmpeg_drm` in its help output. This is the
substrate patch 0002 builds on.

**Requirements:** R1, R2, R4, R5.

**Dependencies:** U2.

**Files:**
- Create: `packages/moonlight-embedded/patches/0001-vendored-ffmpeg-drm-prime-pr932.patch`
- Modify: `packages/moonlight-embedded/manifest.nix` (uncomment the
  `0001` entry in the `patches` list; add `ffmpeg_drm` to
  `expectedPlatforms`).
- Modify: `packages/moonlight-embedded/README.md` (mark patch 0001 as
  "vendored" in the Status table).
- Modify: `packages/moonlight-embedded/package.nix` if cmake requires
  `-DENABLE_FFMPEG_DRM=ON` to compile the new platform (the manifest's
  commented-out flag becomes active).

**Approach:**
- Fetch the patch from
  `https://patch-diff.githubusercontent.com/raw/moonlight-stream/moonlight-embedded/pull/932.diff`
  (already saved at `/tmp/me-research/pr932.diff`, 608 lines, +518/-2
  across 6 files).
- Drop it into `patches/` verbatim. No edits; the entire point of
  vendoring is traceability.
- Add to `manifest.patches` with `name`, `file`, and an `upstreamPath`
  field that records the upstream commit and PR URL.
- Bump `expectedPlatforms` to `["sdl" "ffmpeg_drm"]`.
- Add a Nix buildInput if PR #932 requires one we don't have today (it
  needs `libdrm` and `libavutil/hwcontext_drm.h`; both already present
  in `manifest.nix`'s buildInputs after the scaffold commit).

**Patterns to follow:**
- `packages/cemu/manifest.nix` `patches` list shape:
  `{ name; file; upstreamPath; }`.

**Test scenarios:**
- Happy path: `nix build .#moonlight-embedded` succeeds; the resulting
  `bin/moonlight` runs and `./result/bin/moonlight stream` help output
  lists `ffmpeg_drm` among the `-platform` options.
- Edge case: re-running `nix build .#moonlight-embedded` after a
  whitespace-only edit to the patch produces a different store path,
  confirming the patch is in the source closure.
- Verification: `cat result/nix-support/moonlight-embedded-build/manifest.txt`
  shows `patches=0001-vendored-ffmpeg-drm-prime-pr932.patch` and
  `expected-platforms=sdl ffmpeg_drm`.

**Verification:**
- `nix build .#moonlight-embedded` exits 0 with the patch applied.
- The binary advertises `ffmpeg_drm` in its `-platform` option help text.
- `bash scripts/static-checks.sh` passes.

---

### U4. Share `src/video/ffmpeg.c` between the new platforms

**Goal:** Decide and implement how the new `v4l2m2m` platform reaches
the shared FFmpeg primitives in `src/video/ffmpeg.c`. The two viable
shapes are: compile `ffmpeg.c` into the per-platform shared lib (mirrors
how PR #932 inlines its FFmpeg usage), or extend `ffmpeg_init` /
`ffmpeg.h` with a DRM_PRIME-aware entry point that both `ffmpeg_drm.c`
and the upcoming `v4l2m2m.c` call.

**Requirements:** R3, R7 (a single decoder-selection seam is easier to
test, fail cleanly, and keep correct).

**Dependencies:** U3 (need patch 0001's `ffmpeg_drm.c` in place to know
what shape PR #932 chose).

**Files:**
- Create: `packages/moonlight-embedded/patches/0002a-share-ffmpeg-init.patch`
  (separate small patch, only if a real factor-out edit is needed —
  may be folded into 0002 if trivial; decide at implementation time).
- Modify: `packages/moonlight-embedded/manifest.nix` if 0002a lands as
  a separate file.

**Approach:**
- Read PR #932's `ffmpeg_drm.c` end-to-end and determine whether it
  duplicates FFmpeg context plumbing or already uses `ffmpeg.c`.
  Initial reading suggests it duplicates (it directly calls
  `avcodec_*` rather than `ffmpeg_init`/`ffmpeg_decode`).
- If duplication: extract a thin shared helper into `ffmpeg.c` that
  both platforms call — `ffmpeg_init_drm_prime(codec_id, width,
  height, decoder_name_or_null)` — and have patch 0002 use it.
- If PR #932 already uses `ffmpeg.c`: skip this unit and merge any
  needed extension directly into patch 0002.

**Patterns to follow:**
- Existing `ffmpeg_init` signature in `src/video/ffmpeg.h`.

**Test scenarios:**
- Test expectation: none for the factor-out itself — behavior coverage
  rides on U3 (`ffmpeg_drm` works) and U5 (`v4l2m2m` works). The
  refactor's correctness is verified by both platforms still building
  and running.

**Verification:**
- Both `-platform ffmpeg_drm` and `-platform v4l2m2m` resolve and
  initialize a decoder. (U5 demonstrates the latter; U3 already
  demonstrates the former.)

---

### U5. Add the `v4l2m2m` platform as patch 0002

**Goal:** Author the SM8550-targeted platform: select
`hevc_v4l2m2m` / `h264_v4l2m2m` by name, consume `AV_PIX_FMT_DRM_PRIME`
frames, import each frame's dma-buf fd(s) into an `EGLImage`, sample
via `samplerExternalOES` in a fragment shader, and render into an SDL2
GL context. Register the platform as `v4l2m2m` in `src/platform.[ch]`
so `-platform v4l2m2m` selects it.

**Requirements:** R1, R3, R4, R5, R6, R7.

**Dependencies:** U3 (the platform-registration plumbing from PR #932
must already be in place), U4 (the shared FFmpeg init seam if it
landed).

**Execution note:** Author and validate ephemerally on Sobo first
(scratch checkout from U1; `nix shell` against the local source), only
emit the final patch file once the EGL-import path is producing visible
frames. The risk surface (DMA-buf modifier negotiation, freedreno OES
sampling, SDL2 GL context inside gamescope) is high enough that paper
review alone cannot catch the failure modes — see Risks.

**Files:**
- Create: `packages/moonlight-embedded/patches/0002-add-v4l2m2m-egl-platform.patch`
- Modify: `packages/moonlight-embedded/manifest.nix` (uncomment the
  `0002` entry; add `v4l2m2m` to `expectedPlatforms`; add
  `-DENABLE_V4L2M2M=ON` to `cmakeFlags`).
- Modify: `packages/moonlight-embedded/README.md` (Status table).

**Approach:**
- Fork the structural skeleton of PR #932's `src/video/ffmpeg_drm.c`
  into `src/video/v4l2m2m.c`. Reuse: decoder context lifecycle,
  packet pump, AVFrame queue, AVDRMFrameDescriptor extraction.
  Replace: KMS atomic display thread → EGL/GLES render path.
- Decoder selection: `avcodec_find_decoder_by_name("hevc_v4l2m2m")` /
  `"h264_v4l2m2m"`. No `av_hwdevice_ctx_create`.
- `get_format` callback returns `AV_PIX_FMT_DRM_PRIME` when offered,
  falls back to the first format otherwise (defensive; the wrapper
  decoder usually offers DRM_PRIME unconditionally).
- Open an SDL2 GL window in `setup`. Mirror `sdl.c`'s context creation;
  request a GLES2 context with `EGL_OPENGL_ES2_BIT`.
- Render-loop: dequeue cloned AVFrame, build per-plane EGL attrib list
  from `AVDRMFrameDescriptor`, `eglCreateImageKHR`, bind to
  `GL_TEXTURE_EXTERNAL_OES`, draw full-screen quad,
  `SDL_GL_SwapWindow`, `eglDestroyImageKHR`, `av_frame_free`.
- Fragment shader: `samplerExternalOES`; rely on the EGL driver for
  YUV→RGB conversion (no manual matrix).
- CMake registration: new `cmake/FindV4L2M2M.cmake` probes for
  `libdrm`, `egl`, `glesv2`, `SDL2`. Build a `libmoonlight-v4l2m2m.so`
  in line with how `rk` and `ffmpeg_drm` are built.
- Platform enum: add `V4L2M2M` in `src/platform.h`; dispatch in
  `src/platform.c`'s `platform_check`, `platform_get_video`,
  `platform_name` switches. Update `-platform` help text in
  `src/main.c`.
- Fallback / failure mode: if `eglCreateImageKHR` returns
  `EGL_NO_IMAGE_KHR`, log once (`"v4l2m2m: EGL DMA-buf import failed
  for format=0x%x modifier=0x%llx; falling back to -platform sdl"`)
  and return DR_NEED_IDR from `submitDecodeUnit` to let moonlight pick
  up. The platform stays selected; the user re-runs with
  `-platform sdl`.

**Patterns to follow:**
- `src/video/rk.c` for the EGL/GLES import + render loop shape
  (eglCreateImageKHR, GL_TEXTURE_EXTERNAL_OES, full-screen quad).
- `src/video/sdl.c` for the SDL2 GL context creation and window
  management.
- PR #932's `src/video/ffmpeg_drm.c` for the FFmpeg decoder
  context lifecycle and AVDRMFrameDescriptor extraction.

**Test scenarios:**
- Test expectation: a single integration-style smoke step is the
  practical test surface. C-level unit tests for the platform would
  require a freedreno + iris kernel in CI, which we don't have.
- Smoke (Sobo, manual): build, copy the result onto Sobo, run
  `moonlight stream aka -app "Desktop (Sway)" -codec h265 -platform
  v4l2m2m -keydir /root/.cache/moonlight -verbose`. Expect: stream
  resolves, frames render, log shows
  `v4l2m2m: decoder=hevc_v4l2m2m, EGL importer ready` and no
  `EGL_NO_IMAGE_KHR` lines.
- Smoke (Sobo, fallback): force a modifier failure by streaming with
  a deliberately misconfigured `V4L2M2M_FORCE_FAIL_MODIFIER=1` env
  (added during implementation; can be a `#ifdef DEBUG_V4L2M2M`
  hatch). Expect: clean log line, no segfault, no GPU hang.
- Static (CI): patch applies cleanly, `nix build .#moonlight-embedded`
  succeeds, binary advertises `v4l2m2m` in its `-platform` help.

**Verification:**
- `nix build .#moonlight-embedded` exits 0 with both patches applied.
- The binary advertises `v4l2m2m` in its `-platform` option help text.
- `bash scripts/static-checks.sh` passes.
- On Sobo, a Sunshine stream renders via `-platform v4l2m2m` with no
  CPU-side colorspace conversion or `glTexSubImage2D` calls visible
  in a quick perf trace.

---

### U6. Extend static checks for the patch stack

**Goal:** Add invariants to `scripts/static-checks.sh` that catch
common regressions: a patch listed in `manifest.nix` but missing on
disk, an `expectedPlatforms` entry not matching the patch list, the
patches directory missing its README, the dev-checkout helper not
shellcheck-clean.

**Requirements:** R5, R2 (boundary).

**Dependencies:** U2, U3, U5.

**Files:**
- Modify: `scripts/static-checks.sh`

**Approach:**
- Assert each `manifest.patches[].file` resolves to a file under
  `packages/moonlight-embedded/patches/`.
- Assert `expectedPlatforms` contains `"sdl"` always and contains
  `"ffmpeg_drm"` if patch 0001 is in the list and `"v4l2m2m"` if patch
  0002 is in the list. (Simple grep-based correlation between
  manifest entries and platform names is enough.)
- Assert `packages/moonlight-embedded/patches/README.md` exists when
  the patches directory exists.
- Shellcheck the dev-checkout helper.

**Patterns to follow:**
- Existing static checks for `packages/steam/scripts/*` use plain
  `grep` and `shellcheck`.

**Test scenarios:**
- Happy path: with all U1-U5 land, `bash scripts/static-checks.sh`
  exits 0.
- Regression (manual): temporarily remove `0001-...patch` from disk —
  the static check fails with a clear message naming the missing file.
- Regression (manual): temporarily remove `ffmpeg_drm` from
  `expectedPlatforms` while the patch is still listed — the static
  check fails with a clear correlation-violation message.

**Verification:**
- `bash scripts/static-checks.sh` exits 0 in the happy-path repo state.
- The regression checks above fail with readable messages (verified
  once during U6 development, then reverted).

---

## System-Wide Impact

- **Interaction graph:** `nix build .#moonlight-embedded` is consumed by
  downstream `nix-on-rocks` once that repo wires this monorepo in as a
  flake input. No internal interaction graph inside this repo — packages
  are independent. The new patches only touch upstream source under
  `src/`; they do not affect the `cemu` or `steam` packages.
- **Error propagation:** Patch 0002's failure mode (EGL DMA-buf import
  rejection) is local to the `v4l2m2m` platform. Other platforms
  (`sdl`, `ffmpeg_drm`, etc.) are unaffected. The fallback path is a
  user re-running with a different `-platform` value, not in-band
  rescue.
- **State lifecycle risks:** The DMA-buf fd lifecycle is the most
  fragile state seam (see R6). Patch 0002 must hold the `AVFrame`
  reference until `eglDestroyImageKHR` returns; only then `av_frame_free`.
  Early `close(fd)` is a known foot-gun called out in
  `brief-ffmpeg-drm-prime.md` §5.
- **API surface parity:** No other platform needs an analogous change.
  This is additive.
- **Integration coverage:** Real-hardware smoke on Sobo (U5
  verification) is the only meaningful integration test until we have
  a freedreno + iris CI runner, which is not in scope.
- **Unchanged invariants:** All existing `-platform` options (`sdl`,
  `rk`, `x11`, `pi`, `imx`, `aml`, `x11_vdpau`, `fake`) keep their
  current semantics. The package's `bin/moonlight` retains its
  upstream argv contract.

---

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| Freedreno's `EGL_EXT_image_dma_buf_import_modifiers` rejects whatever modifier the iris driver advertises (Q08C compressed UBWC NV12 is the likely-default and the likely-rejected one). | Ephemeral validation on Sobo before committing the patch (U5 execution note). If rejected, request linear NV12 via `VIDIOC_S_FMT` on the V4L2 capture side; FFmpeg's `hevc_v4l2m2m` accepts a capture-format hint via `AV_OPT_SEARCH_CHILDREN` on the decoder context. |
| Main 10 (10-bit HEVC) streams produce `P010` or `Q10C` output, and freedreno's `samplerExternalOES` doesn't sample 10-bit. | First cut targets 8-bit only. If the only test stream is Main 10, request 8-bit output explicitly via the capture-format hint; accept dynamic-range loss (Korri Stream is SDR anyway). Real 10-bit sampling is a separate plan. |
| Nixpkgs `ffmpeg` is built without `--enable-v4l2-m2m`. | Add a cmake-configure-time assertion that `hevc_v4l2m2m` is registered (`av_codec_iterate` + name match) and abort with a clear error. Document the fix in the package README. Likelihood is low; v4l2-m2m has been a default-on FFmpeg feature for years. |
| PR #932 mutates before we land. | We pin to `praxis88/moonlight-embedded@4ecbed5` explicitly in patch 0001's header. If upstream rebases, the patch is unchanged here. If PR #932 merges, U3's commit cleanly reverts to a no-op and we delete patch 0001 — patch 0002 still applies. |
| Gamescope-wrapped SDL2 GL context behaves differently from the bare SDL2 context `src/video/sdl.c` already proves. | The smoke validation in U5 happens with gamescope wrapping, not bare SDL2. If gamescope makes EGL import unusable, this fails loudly during ephemeral iteration before any patch lands. Worst case: drop to a bare-SDL2-window variant and accept gamescope-incompatibility, documented in the package README. |
| Sunshine "Korri Stream" stickiness on the host (separate, server-side bug) blocks rapid iteration. | Use "Desktop (Sway)" for development streams. Documented in the handoff. |

---

## Documentation / Operational Notes

- On patch 0001 landing (U3), update the Status table in
  `packages/moonlight-embedded/README.md`: "vendored from upstream PR
  #932" with the date.
- On patch 0002 landing (U5), update the Status table again: "v4l2m2m
  platform: shipped; SDR HEVC 8-bit validated on Sobo on <date>".
- After U5 ships, write a learning to `docs/solutions/` capturing the
  modifier-negotiation outcome (which modifier won, whether linear
  fallback was needed, whether P010 was reachable). Both nix-sm8550
  and nix-on-rocks consumers will want to find that quickly.
- No alerting or monitoring changes — this is a userland binary
  package.

---

## Sources & References

- **Handoff document:** `/tmp/handoff-acJ3K6.md` (session-local; see
  also the SE-compound learning in `nix-on-rocks`
  `docs/solutions/runtime-errors/guest-moonlight-no-v4l2m2m-decoder-missing-video-passthrough-rocknix-2026-05-22.md`).
- **Research briefs (local, scratch):**
  - `/tmp/me-research/brief-rk-structure.md` — `rk.c` structural map
  - `/tmp/me-research/brief-ffmpeg-drm-prime.md` — FFmpeg DRM_PRIME
    API contract
  - `/tmp/me-research/brief-forks-prior-art.md` — GitHub survey
- **Upstream prior art:**
  [moonlight-embedded PR #932](https://github.com/moonlight-stream/moonlight-embedded/pull/932)
  (`praxis88/moonlight-embedded@4ecbed5`, +518/-2 across 6 files)
- **Related code (this repo):** `packages/moonlight-embedded/`
  scaffolded in commit `9399c0f`; flake wiring at `flake.nix:24,29`;
  static-check pattern at `scripts/static-checks.sh:82-99`.
- **Related code (upstream):**
  - `src/video/rk.c` (rkmpp + EGL/GLES; structural model for our EGL
    half)
  - `src/video/sdl.c` (SDL2 GL surface bootstrap)
  - `src/video/ffmpeg.c` + `ffmpeg.h` (shared FFmpeg primitives)
  - `src/platform.c` + `platform.h` (`-platform` dispatch)
- **External specs:** EGL `EGL_EXT_image_dma_buf_import` /
  `EGL_EXT_image_dma_buf_import_modifiers`; FFmpeg
  `libavutil/hwcontext_drm.h` (`AVDRMFrameDescriptor`).
