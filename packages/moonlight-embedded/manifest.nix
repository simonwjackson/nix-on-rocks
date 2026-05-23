# moonlight-embedded package contract for SM8550 zero-copy HW decode work.
#
# This package builds upstream moonlight-embedded with a downstream patch
# stack that adds a V4L2 stateful M2M (`hevc_v4l2m2m` / `h264_v4l2m2m`) +
# EGL_LINUX_DMA_BUF_EXT zero-copy video platform suitable for Qualcomm
# SM8550 (Adreno 740 + iris VPU + freedreno).
#
# Patch order matters and is documented per-entry. Keep this file data-only
# so derivation, docs, and static checks share the same source of truth.

{
  pname = "moonlight-embedded";
  version = "2.7.1-sm8550-v4l2m2m";

  source = {
    owner = "moonlight-stream";
    repo = "moonlight-embedded";
    # v2.7.1 tag — the most recent upstream release with stable
    # moonlight-common-c and SDL_GameControllerDB submodules.
    rev = "775444287305849ebdf4736c75298ad0713e2d5d";
    shortRev = "7754442";
    # Includes submodules (moonlight-common-c, SDL_GameControllerDB,
    # h264bitstream); required for the build to succeed.
    hash = "sha256-h+hI9TQUGMI8VDzvnuRGDjxm8D7GuC/L4/0rwTFocgA=";
    fetchSubmodules = true;
  };

  patches = [
    {
      name = "0001-vendored-ffmpeg-drm-prime-pr932.patch";
      file = ./patches/0001-vendored-ffmpeg-drm-prime-pr932.patch;
      upstreamPath = "github:praxis88/moonlight-embedded@4ecbed5a4016c4b498860a030d9727110c96cc74";
      upstreamPullRequest = "https://github.com/moonlight-stream/moonlight-embedded/pull/932";
      role = "vendored verbatim from upstream PR #932; adds the ffmpeg_drm platform (FFmpeg AV_PIX_FMT_DRM_PRIME consumer + KMS atomic display thread) and the platform-registration plumbing patch 0002 will build on";
    }
    {
      name = "0001a-fix-libdrm-cmake-find-and-main-help.patch";
      file = ./patches/0001a-fix-libdrm-cmake-find-and-main-help.patch;
      upstreamPath = "this repo";
      role = "PR #932 references DRM_LIBRARY/DRM_INCLUDE_DIR but never sets them, so its build-gate is silently false. This adds the missing pkg_check_modules(DRM libdrm) probe and advertises ffmpeg_drm in main.c's -platform help text. Logically part of 0001 but kept separate to preserve verbatim vendoring of PR #932";
    }
    {
      name = "0002-add-v4l2m2m-egl-platform.patch";
      file = ./patches/0002-add-v4l2m2m-egl-platform.patch;
      upstreamPath = "this repo";
      role = "Adds the SM8550-targeted v4l2m2m platform: selects hevc_v4l2m2m / h264_v4l2m2m by name, imports AVDRMFrameDescriptor dma-buf fds via EGL_LINUX_DMA_BUF_EXT, samples GL_TEXTURE_EXTERNAL_OES in an SDL2 GL ES 3.0 context. Registered alongside ffmpeg_drm so this fork covers both the KMS-overlay variant (PR #932) and the EGL-composited variant that cohabits with gamescope (which already owns DRM master). Depends on 0001 for the src/platform.h enum slot and on 0001a for the libdrm pkg-config probe in CMakeLists.txt";
    }
  ];

  cmakeFlags = [
    "-DCMAKE_BUILD_TYPE=Release"
    # Suppress the BCM/IMX/Amlogic/Rockchip platform conditionals; on
    # aarch64-linux without the upstream sysroots they fail to detect.
    # Keep SDL and the upcoming v4l2m2m platform on.
    "-DBCM_LIBRARY=OFF"
    "-DENABLE_PI=OFF"
    "-DENABLE_MMAL=OFF"
    "-DENABLE_IMX=OFF"
    "-DENABLE_AML=OFF"
    "-DENABLE_FFMPEG=ON"
    "-DENABLE_SDL=ON"
    # Patch 0001 introduces ENABLE_FFMPEG_DRM (defaults ON in the patch,
    # but pin it here so the cmake invocation makes the intent explicit).
    # Patch 0002 introduces ENABLE_V4L2M2M (also defaults ON; same
    # reasoning -- explicit beats implicit at the derivation boundary).
    "-DENABLE_FFMPEG_DRM=ON"
    "-DENABLE_V4L2M2M=ON"
  ];

  # Runtime platforms the package is expected to offer post-patch.
  expectedPlatforms = [
    "sdl"           # always available — software decode through SDL2
    "ffmpeg_drm"    # added by patch 0001 (PR #932 vendored) + 0001a (build-gate fix)
    "v4l2m2m"       # added by patch 0002 (this repo, SM8550 zero-copy)
  ];

  knownIntentionalNixDeltas = [
    "BCM/IMX/Amlogic/Rockchip platforms compiled out; this package is targeted at SM8550 + generic SDL fallback"
    "Submodules pinned to the v2.7.1 tag; not the same as nixpkgs' moonlight-embedded which sometimes carries patch bumps"
  ];

  packageContract = {
    supported = [
      "moonlight CLI binary with sdl platform for software-decode fallback"
      "(post-patch) ffmpeg_drm platform for generic V4L2 Request hwaccel + KMS atomic display"
      "(post-patch) v4l2m2m platform for SM8550 zero-copy hevc_v4l2m2m + EGL DMA-buf import"
    ];
    downstreamOwned = [
      "session compositor launch policy and geometry"
      "client-state keydir layout (XDG cache vs handheld read-write mount)"
      "portal demote/restore policy around stream launch"
      "pair flow orchestration"
      "streaming-host app naming and stickiness recovery"
    ];
  };
}
