# moonlight-embedded (SM8550)

Downstream build of [moonlight-embedded](https://github.com/moonlight-stream/moonlight-embedded)
carrying a patch stack that adds V4L2 stateful M2M hardware HEVC/H.264
decode for Qualcomm SM8550 handhelds (Adreno 740 + iris VPU + freedreno +
Mesa) and presents the iris VPU's NV12 output through SDL.

## Status

| Stage | State |
|---|---|
| Vanilla upstream v2.7.1 derivation | shipped |
| `ffmpeg_drm` vendored from upstream PR #932 (V4L2 Request + KMS atomic) | shipped (patches `0001` + `0001a`) |
| `v4l2m2m` (this repo's new platform: hevc_v4l2m2m/h264_v4l2m2m + SDL NV12 presentation) | shipped in patch `0002` |
| Validated on Sobo via Sway/gamescope-adjacent kiosk session | yes — VPU decode, SDL presentation, resize/aspect-fit, 30s A/B benchmark |

The patches live as files in `patches/`, listed in `manifest.nix`. Today
`nix build .#moonlight-embedded` produces a binary advertising the `sdl`
(software decode, always available) and `ffmpeg_drm` (PR #932 KMS atomic —
not useful under gamescope, which already owns DRM master) platforms. The
`v4l2m2m` SM8550 hardware-decode platform ships in patch `0002`. True
DRM PRIME zero-copy remains deferred because FFmpeg 8.0's v4l2_m2m wrapper
emits native NV12 frames on iris even when DRM_PRIME is requested.

## Build

This package does not yet have a flake entry in nix-on-rocks; the top-level
`flake.nix` is introduced by U10 of
`docs/plans/2026-05-22-001-refactor-monorepo-merge-layered-restructure-plan.md`.
Until that lands, the build path is:

```sh
# Manifest well-formedness check (works today, no flake required):
nix eval --impure --expr '(import packages/moonlight-embedded/manifest.nix).version'

# Full derivation build (post-flake-collapse):
nix build .#moonlight-embedded --print-build-logs
```

The package installs `bin/moonlight` and write-evidence under
`$out/nix-support/moonlight-embedded-build/`.

## What this package owns vs. doesn't

Owned here (package-generic):

- Upstream moonlight-embedded source pin and submodule contract
- The C patches that add V4L2 M2M HW decode on SM8550 hardware
- Build-input set and cmake flag set
- Per-platform availability metadata (`expectedPlatforms`) for downstream
  consumers to introspect via `passthru.moonlightPackageManifest`

Not owned here (downstream / consumer responsibility):

- Sway/Gamescope launch policy and geometry
- Moonlight keydir location (`~/.cache/moonlight` vs ROCKNIX `/storage/.cache/moonlight`)
- Sunshine host pairing flow and app naming
- Portal demote/restore policy around stream launch
- SM8550 CPU/GPU tuning while a stream is active

These belong in the consuming flake (`nix-on-rocks` for ROCKNIX guests, or
any other integration repo).

## Patch architecture

```
patches/
  0001-vendored-ffmpeg-drm-prime-pr932.patch   # PR #932 verbatim
  0002-add-v4l2m2m-sdl-nv12-platform.patch          # our delta — SM8550-targeted
```

**0001** vendors upstream PR #932 (`praxis88/ffmpeg-drm-prime`,
[#932](https://github.com/moonlight-stream/moonlight-embedded/pull/932)),
which adds a generic FFmpeg V4L2 Request + KMS atomic display backend. We
keep it because it provides the platform-registration plumbing
(`CMakeLists.txt`, `src/platform.[ch]`, `src/video/video.h`) and a clean
working example of consuming `AV_PIX_FMT_DRM_PRIME` frames. Useful on
RK3399-class boards even though it's not what SM8550 needs.

**0001a** is a tiny in-repo fixup for two defects in PR #932 that prevented
it from actually working: its CMake gate references `DRM_LIBRARY` and
`DRM_INCLUDE_DIR` but never sets them (so the gate was silently false),
and its `src/main.c` `-platform` usage string was never updated to
advertise the new platform. 0001a adds the missing
`pkg_check_modules(DRM libdrm)` probe and the help-text entry. Kept
separate from 0001 to preserve verbatim vendoring of PR #932.

**0002** is the SM8550-targeted platform: it selects `hevc_v4l2m2m` /
`h264_v4l2m2m` decoders explicitly by name so the iris VPU performs the
expensive video decode, then presents the resulting NV12 frames through
`SDL_UpdateNVTexture()` + `SDL_RenderCopy()`. That keeps SDL responsible
for Wayland sizing, compositor scale, live resize, aspect-fit, and display
moves — important for dual-screen devices like AYN Thor.

The original zero-copy idea (FFmpeg `AV_PIX_FMT_DRM_PRIME` → EGL dma-buf
import) is deferred. On FFmpeg 8.0 the v4l2_m2m wrapper advertises
`capture=NV12/drm_prime` when requested, but `v4l2_try_start()` overwrites
`avctx->pix_fmt` with the native V4L2 format after `VIDIOC_G_FMT`; on iris
that means CPU-visible NV12 frames. The practical cost is small: the Sobo
A/B benchmark measured ~49% Moonlight process CPU for the SDL software
baseline vs ~13% for v4l2m2m + SDL NV12 presentation.

## Developing the patch stack

Use the repo helper to get a working git tree of upstream at the
manifest-pinned commit with any current patches applied on top as
commits:

```sh
bash scripts/moonlight-embedded-dev-checkout.sh
```

The helper clones into `/tmp/moonlight-embedded-dev/<short-rev>/`
(override with `MOONLIGHT_DEV_ROOT=...`), checks out the manifest-pinned
rev, re-creates a `nix-sm8550-dev` branch from it, and runs
`git am --3way` over `patches/*.patch` in filename order.

Iterate freely in the scratch tree (edit, commit, build, run on Sobo).
When ready, export the final result back into this repo with:

```sh
git -C /tmp/moonlight-embedded-dev/<short-rev> \
    format-patch <pinned-rev>..nix-sm8550-dev \
    -o packages/moonlight-embedded/patches/
```

The helper is idempotent: re-running against an existing tree refreshes
the branch from upstream and re-applies the current patch set, stashing
any uncommitted edits first.

## Background

This patch stack was scoped in the sibling `nix-sm8550` repository and
migrated here at the post-refactor target paths ahead of the monorepo merge
(see `docs/plans/2026-05-22-001-refactor-monorepo-merge-layered-restructure-plan.md`).
Full design context lives in
`docs/plans/2026-05-22-002-feat-moonlight-embedded-v4l2m2m-zero-copy-plan.md`;
research briefs are under `docs/thinking/2026-05-22-moonlight-embedded-*.md`.
Key technical references:

- Upstream PR #932: <https://github.com/moonlight-stream/moonlight-embedded/pull/932>
- Upstream `src/video/rk.c` — the existing EGL/GLES rkmpp platform; the
  EGL import path is structurally identical to what 0002 will do
- FFmpeg `libavcodec/v4l2_m2m_dec.c` — the actual decoder wrapper
- Mesa `src/gallium/drivers/freedreno/` — modifier negotiation for
  Qualcomm UBWC vs linear NV12
