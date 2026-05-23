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
, opus
, SDL2
, systemdMinimal
, util-linux
# Pulled in by the SM8550 zero-copy patches (libdrm for AVDRMFrameDescriptor;
# libglvnd for EGL + GLES2 import). Kept in the vanilla buildInputs so the
# package shape is stable across patch presence.
, libdrm
, libglvnd
}:

let
  manifest = import ./manifest.nix;
in

# moonlight-embedded with the SM8550 zero-copy v4l2m2m HW decode patch stack.
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
    opus
    SDL2
    systemdMinimal
    util-linux
    # Added by this package for the SM8550 zero-copy HW-decode patch stack:
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
    description = "Moonlight game streaming client for embedded Linux, with SM8550 zero-copy v4l2m2m HW decode patches";
    homepage = "https://github.com/moonlight-stream/moonlight-embedded";
    license = lib.licenses.gpl3Plus;
    mainProgram = "moonlight";
    platforms = [ "aarch64-linux" "x86_64-linux" ];
  };
}
