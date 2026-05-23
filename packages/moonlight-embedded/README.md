# moonlight-embedded (SM8550)

Downstream build of [moonlight-embedded](https://github.com/moonlight-stream/moonlight-embedded)
carrying a patch stack that adds zero-copy V4L2 stateful M2M hardware HEVC
(and H.264) decode for Qualcomm SM8550 handhelds (Adreno 740 + iris VPU +
freedreno + Mesa).

## Status

| Stage | State |
|---|---|
| Vanilla upstream v2.7.1 derivation | scaffolded |
| `ffmpeg_drm` vendored from upstream PR #932 (V4L2 Request + KMS atomic) | not yet vendored |
| `v4l2m2m` (this repo's new platform: hevc_v4l2m2m + EGL DMA-buf import) | not yet implemented |
| Validated on Sobo via gamescope | not yet |

The patches will land as files in `patches/`, listed in `manifest.nix`.
Until they do, `nix build .#moonlight-embedded` ships an upstream binary with
only the SDL software-decode platform.

## Build

```sh
nix build .#moonlight-embedded --print-build-logs
```

The package installs `bin/moonlight` and write-evidence under
`$out/nix-support/moonlight-embedded-build/`.

## What this package owns vs. doesn't

Owned here (package-generic):

- Upstream moonlight-embedded source pin and submodule contract
- The C patches that add zero-copy HW decode on SM8550 hardware
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

## Patch architecture (planned)

```
patches/
  0001-vendored-ffmpeg-drm-prime-pr932.patch   # PR #932 verbatim
  0002-add-v4l2m2m-egl-platform.patch          # our delta — SM8550-targeted
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

**0002** is the SM8550-targeted platform: it forks 0001's structure to
select `hevc_v4l2m2m` / `h264_v4l2m2m` decoders explicitly by name, and
replaces the KMS atomic display thread with an EGL/GLES path
(`eglCreateImageKHR(EGL_LINUX_DMA_BUF_EXT)` →
`glEGLImageTargetTexture2DOES(GL_TEXTURE_EXTERNAL_OES)` →
`samplerExternalOES` in the fragment shader) so it works under gamescope,
which already owns DRM master.

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

This patch stack was scoped in a prior session and is documented in detail
in the parent repo's session handoff. Key technical references:

- Upstream PR #932: <https://github.com/moonlight-stream/moonlight-embedded/pull/932>
- Upstream `src/video/rk.c` — the existing EGL/GLES rkmpp platform; the
  EGL import path is structurally identical to what 0002 will do
- FFmpeg `libavcodec/v4l2_m2m_dec.c` — the actual decoder wrapper
- Mesa `src/gallium/drivers/freedreno/` — modifier negotiation for
  Qualcomm UBWC vs linear NV12
