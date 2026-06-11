{ lib
, stdenv
, fetchFromGitHub
, cmake
, perl
, pkg-config
, alsa-lib
, avahi
, curl
, expat
, ffmpeg
, libcec
, libevdev
, libpulseaudio
, libpthreadstubs
, libva
, libvdpau
, libxcb
, libopus
, SDL2
, systemdMinimal
, util-linux
# Pulled in by the SM8550 HW-decode patches. libdrm/libglvnd are retained
# for the vendored ffmpeg_drm patch and the deferred DRM_PRIME/EGL experiment;
# the active v4l2m2m shipping path presents NV12 through SDL.
, libdrm
, libglvnd
}:

let
  manifest = import ./manifest.nix;
in

# moonlight-embedded with the SM8550 v4l2m2m HW decode patch stack.
#
# Upstream: https://github.com/moonlight-stream/moonlight-embedded
# Patch rationale lives in patches/README.md alongside the patch files.
stdenv.mkDerivation rec {
  pname = manifest.pname;
  version = manifest.version;

  src = fetchFromGitHub {
    inherit (manifest.source) owner repo rev hash fetchSubmodules;
  };

  patches = map (patch: patch.file) manifest.patches;

  nativeBuildInputs = [
    cmake
    perl
    pkg-config
  ];

  buildInputs = [
    # Upstream nixpkgs moonlight-embedded buildInputs (aligned with
    # pkgs/applications/networking/moonlight-embedded as of nixos-unstable):
    alsa-lib
    avahi
    curl
    expat
    ffmpeg
    libcec
    libevdev
    libpulseaudio
    libpthreadstubs
    libva
    libvdpau
    libxcb
    libopus
    SDL2
    systemdMinimal
    util-linux
    # Added by this package for ffmpeg_drm + SM8550 HW-decode experiments:
    libdrm
    libglvnd
  ];

  strictDeps = true;

  cmakeFlags = manifest.cmakeFlags;

  # The upstream CMakeLists searches for embedded-vendor sysroots that don't
  # exist on Nix (RPi /opt/vc, IMX, Amlogic). Manifest cmakeFlags already
  # disable them; nothing extra needed here today, but the hook stays so
  # patches can append without restructuring the derivation.
  preConfigure = ''
    : # intentional no-op — manifest cmakeFlags suppress unsupported platforms.
  '';

  postInstall = ''
    mkdir -p "$out/nix-support/moonlight-embedded-build"

    # InputPlumber's virtual Xbox 360 pad on Thor is USB 045e:028e v0001.
    # The vendored SDL controller DB entry for that exact Linux GUID maps the
    # hat values as if they were rotated 180°; normalize it so Moonlight sends
    # the same D-pad directions that evdev and downstream input daemons observe.
    substituteInPlace "$out/share/moonlight/gamecontrollerdb.txt" \
      --replace-fail \
        '030000005e0400008e02000001000000,Microsoft Xbox 360,a:b0,b:b1,back:b6,dpdown:h0.1,dpleft:h0.2,dpright:h0.8,dpup:h0.4' \
        '030000005e0400008e02000001000000,Microsoft Xbox 360,a:b0,b:b1,back:b6,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1'

    {
      printf '%s\n' 'pname=${manifest.pname}'
      printf '%s\n' 'version=${manifest.version}'
      printf '%s\n' 'source-rev=${manifest.source.rev}'
      printf '%s\n' 'source-short-rev=${manifest.source.shortRev}'
      printf '%s\n' 'fetch-submodules=true'
      printf '%s\n' 'patches=${lib.concatMapStringsSep " " (patch: patch.name) manifest.patches}'
      printf '%s\n' 'expected-platforms=${lib.concatStringsSep " " manifest.expectedPlatforms}'
      printf '%s\n' 'main-program=bin/moonlight'
    } > "$out/nix-support/moonlight-embedded-build/manifest.txt"

    if [ -f "$out/bin/moonlight" ]; then
      printf 'present\n' > "$out/nix-support/moonlight-embedded-build/moonlight-binary-present"
    else
      echo "error: moonlight binary missing from $out/bin" >&2
      exit 1
    fi

    if [ -f CMakeCache.txt ]; then
      cp CMakeCache.txt "$out/nix-support/moonlight-embedded-build/CMakeCache.txt"
    fi
  '';

  passthru = {
    moonlightPackageManifest = manifest;
  };

  meta = {
    description = "Moonlight game streaming client for embedded Linux, with SM8550 v4l2m2m HW decode patches";
    homepage = "https://github.com/moonlight-stream/moonlight-embedded";
    license = lib.licenses.gpl3Plus;
    mainProgram = "moonlight";
    platforms = [ "aarch64-linux" "x86_64-linux" ];
  };
}
