# moonlight-embedded patches

Downstream patches applied to upstream `moonlight-embedded` to add zero-copy
hardware HEVC decode on Qualcomm SM8550 handhelds.

Patches are listed in `../manifest.nix` under `patches` and applied in
filename order by the package derivation. Filename order is significant:
later patches assume earlier patches have applied.

## Patch stack

| Order | Patch | Origin | Scope |
|---|---|---|---|
| 0001 | `0001-vendored-ffmpeg-drm-prime-pr932.patch` | [moonlight-embedded PR #932](https://github.com/moonlight-stream/moonlight-embedded/pull/932) (`praxis88/moonlight-embedded@4ecbed5`) | Adds the `ffmpeg_drm` platform: FFmpeg `AV_PIX_FMT_DRM_PRIME` consumer + KMS atomic display. Provides the CMake / `src/platform.[ch]` / `src/video/video.h` registration plumbing that patch 0002 builds on. Vendored verbatim. |
| 0001a | `0001a-fix-libdrm-cmake-find-and-main-help.patch` | This repo | Fixes two defects in PR #932 that prevented it from actually working: the CMake build-gate references `DRM_LIBRARY` / `DRM_INCLUDE_DIR` but never runs a probe to set them (gate silently false), and `src/main.c`'s `-platform` usage banner never gained the new platform name. Adds `pkg_check_modules(DRM libdrm)` and updates the help string. Kept as a separate patch so 0001 remains exact-byte-equal to PR #932. |
| 0002 | `0002-add-v4l2m2m-egl-platform.patch` | This repo | Adds the `v4l2m2m` platform: selects `hevc_v4l2m2m` / `h264_v4l2m2m` decoders by name, imports `AVDRMFrameDescriptor` dma-buf fds via `EGL_LINUX_DMA_BUF_EXT`, samples `GL_TEXTURE_EXTERNAL_OES` in an SDL2 GL context (so it works under gamescope, which already owns DRM master). |

All three patches are in `manifest.patches`. 0002 was authored on Fuji in
a scratch tree (compile-clean against FFmpeg 8.0 + libdrm 2.4.131 +
EGL 1.5 + GLES 3.2 + SDL2 2.32.64 on aarch64). Sobo hardware iteration
(V4L2 negotiation, EGL_BAD_ACCESS triage, frame-pacing stability) is
tracked as units **U4 G1–G5a** in
`docs/plans/2026-05-22-003-feat-moonlight-embedded-sobo-zero-copy-shipping-plan.md`.

## Authoring workflow

Use `scripts/moonlight-embedded-dev-checkout.sh` from the repo root to get
a working git tree of upstream at the manifest-pinned commit, with any
patches already in this directory applied on top as commits. Iterate
inside the scratch tree; export the final result back here with
`git format-patch` once it works on real hardware.

The dev-checkout helper is idempotent: re-running it against an existing
scratch tree refreshes the branch from the pinned upstream rev and
re-applies the current set of patches, stashing any uncommitted work
first.

## Rules

- Each patch carries a human-readable header describing **origin**
  (upstream commit or "this repo"), **scope** (what it adds / why),
  and **dependencies on other patches** (e.g. "depends on 0001 for
  `src/platform.h` enum extension").
- Patch filenames use `NNNN-short-description.patch` (four-digit
  zero-padded prefix, kebab-cased description). Numbers leave gaps when
  splitting or reordering so we don't have to renumber existing patches.
- Vendored upstream patches are renamed to include the upstream
  identifier (`-pr<N>`, `-commit-<short>`) so it's obvious they didn't
  originate here.
- When a vendored upstream patch merges upstream, delete it from this
  directory and from `manifest.patches`; subsequent patches should still
  apply against the bumped upstream pin.
