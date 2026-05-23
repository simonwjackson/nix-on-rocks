{ lib
, stdenvNoCC
, symlinkJoin
, buildFHSEnv
, makeWrapper
, bash
, binutils
, bubblewrap
, coreutils
, curl
, dbus
, file
, findutils
, gawk
, glibc
, gnugrep
, gnused
, gnutar
, gzip
, lsb-release
, lsof
, pciutils
, python3
, unzip
, usbutils
, xdg-utils
, xorg
, xz
, zenity
, alsa-lib
, at-spi2-core
, cairo
, cups
, expat
, fontconfig
, freetype
, fribidi
, gdk-pixbuf
, glib
, gtk2
, harfbuzz
, libcap
, libdrm
, libgbm
, libGL
, libpulseaudio
, libudev0-shim
, libva
, libxcrypt
, libxkbcommon
, libxml2
, networkmanager
, nspr
, nss
, openal
, openssl
, pango
, pipewire
, sdl2-compat
, sqlite
, udev
, vulkan-loader
, wayland
, zlib
}:

let
  manifest = import ./manifest.nix;
  resourceNames = map (resource: resource.name) manifest.resources;
  isAarch64 = stdenvNoCC.hostPlatform.system == "aarch64-linux";

  steamHelpers = stdenvNoCC.mkDerivation {
    pname = "${manifest.pname}-helpers";
    version = manifest.version;

    src = ./.;

    dontConfigure = true;
    dontBuild = true;

    nativeBuildInputs = [ makeWrapper ];

    installPhase = ''
            runHook preInstall

            install -Dm755 scripts/steam-arm64-bootstrap \
              "$out/bin/steam-arm64-bootstrap"
            install -Dm755 scripts/steam-arm64-seed \
              "$out/bin/steam-arm64-seed"
            install -Dm755 scripts/steam-guest-native \
              "$out/bin/steam-guest-native"
            install -Dm755 scripts/steam-guest-runtime-prep \
              "$out/bin/steam-guest-runtime-prep"
            install -Dm755 scripts/steam-guest-run \
              "$out/bin/steam-guest-run"

            mkdir -p \
              "$out/share/steam-rocknix-bootstrap/resources" \
              "$out/nix-support/rocknix-steam-bootstrap"

            for resource in ${lib.escapeShellArgs resourceNames}; do
              install -Dm644 "resources/$resource" \
                "$out/share/steam-rocknix-bootstrap/resources/$resource"
            done

            cat > "$out/nix-support/rocknix-steam-bootstrap/manifest.txt" <<EOF
      pname=${manifest.pname}
      version=${manifest.version}
      rocknix-repo=${manifest.rocknixSource.repo}
      rocknix-rev=${manifest.rocknixSource.rev}
      rocknix-package-path=${manifest.rocknixSource.paths.package}
      rocknix-install-helper-path=${manifest.rocknixSource.paths.installHelper}
      rocknix-resource-path=${manifest.rocknixSource.paths.resources}
      rocknix-launcher-path=${manifest.rocknixSource.paths.launcher}
      steam-launcher-version=${manifest.steamLauncher.version}
      steam-launcher-deb-url=${manifest.steamLauncher.debUrl}
      steam-arm64-runtime-url=${manifest.arm64Bootstrap.runtimeTarUrl}
      steam-arm64-client-manifest-url=${manifest.arm64Bootstrap.clientManifestUrl}
      steam-arm64-cdn-base-url=${manifest.arm64Bootstrap.cdnBaseUrl}
      proton-compatibility-tool-name=${manifest.arm64Bootstrap.protonCompatibilityToolName}
      proton-compatibility-tool-link=${manifest.arm64Bootstrap.protonCompatibilityToolLink}
      package-entry-points=bin/steam-arm64-bootstrap bin/steam-arm64-seed bin/steam-guest-native bin/steam-guest-runtime-prep bin/steam-guest-run${lib.optionalString isAarch64 " bin/steam-arm64-fhs"}
      steam-client-launcher=guest-native-helper
      steam-runtime-prep-helper=bin/steam-guest-runtime-prep
      steam-run-capsule=${if isAarch64 then "bin/steam-arm64-fhs" else "aarch64-only"}
      host-steam-fallback=false
      guest-native-steam-target=true
      immutable-nix-store-valve-arm64-seed-artifacts=false
      downstream-owns-target-layout=true
      downstream-owns-fex-rootfs=true
      downstream-owns-session-launch=true
      resources=${lib.concatStringsSep " " resourceNames}
      EOF

            cat > "$out/nix-support/rocknix-steam-bootstrap/resource-sha256.txt" <<EOF
      ${lib.concatMapStringsSep "\n" (resource: "${resource.sha256}  ${resource.name}") manifest.resources}
      EOF

            wrapProgram "$out/bin/steam-arm64-bootstrap" \
              --prefix PATH : ${lib.makeBinPath [ bash coreutils ]}
            wrapProgram "$out/bin/steam-arm64-seed" \
              --prefix PATH : ${lib.makeBinPath [ bash binutils coreutils curl findutils gnugrep gnutar gzip unzip ]}
            wrapProgram "$out/bin/steam-guest-native" \
              --prefix PATH : ${lib.makeBinPath [ bash coreutils ]}
            wrapProgram "$out/bin/steam-guest-runtime-prep" \
              --prefix PATH : ${lib.makeBinPath [ bash bubblewrap coreutils file findutils gnugrep gnused ]}
            wrapProgram "$out/bin/steam-guest-run" \
              --prefix PATH : ${lib.makeBinPath [ bash coreutils ]}

            runHook postInstall
    '';
  };

  steamFhs = buildFHSEnv {
    name = "rocknix-steam-arm64-fhs";
    executableName = "steam-arm64-fhs";
    privateTmp = true;
    includeClosures = true;

    targetPkgs = p: with p; [
      bash
      bubblewrap
      coreutils
      curl
      dbus
      fex
      file
      findutils
      gawk
      glibc.bin
      gnugrep
      gnused
      gnutar
      gzip
      lsb-release
      lsof
      pciutils
      python3
      usbutils
      xdg-utils
      xorg.xrandr
      xz
      zenity
    ];

    multiPkgs = p: with p; [
      alsa-lib
      at-spi2-core
      cairo
      cups.lib
      curl
      dbus.lib
      expat
      fontconfig
      freetype
      fribidi
      gdk-pixbuf
      glib
      glibc
      gtk2
      harfbuzz
      libcap
      libdrm
      libgbm
      libGL
      libpulseaudio
      libudev0-shim
      libva
      libxcrypt
      libxkbcommon
      libxml2
      networkmanager
      nspr
      nss
      openal
      openssl
      pango
      pipewire
      sdl2-compat
      sqlite
      udev
      vulkan-loader
      wayland
      xorg.libICE
      xorg.libSM
      xorg.libX11
      xorg.libXcomposite
      xorg.libXcursor
      xorg.libXdamage
      xorg.libXext
      xorg.libXfixes
      xorg.libXi
      xorg.libXinerama
      xorg.libXrandr
      xorg.libXrender
      xorg.libXScrnSaver
      xorg.libXtst
      xorg.libxcb
      xorg.libxshmfence
      zlib
    ];

    profile = ''
      unset GIO_EXTRA_MODULES
    '';

    runScript = "${steamHelpers}/bin/steam-guest-run";

    # Steam expects /sbin/ldconfig to exist. Copy rather than symlink to avoid
    # nested-runtime symlink loops, matching nixpkgs' Steam FHS wrapper.
    extraBuildCommands = ''
      cp -f $out/usr/{bin,sbin}/ldconfig
    '';

    extraBwrapArgs = [
      "--bind-try"
      "/tmp/dumps"
      "/tmp/dumps"
    ];
  };
in
symlinkJoin {
  name = "${manifest.pname}-${manifest.version}";
  paths = [ steamHelpers ] ++ lib.optionals isAarch64 [ steamFhs ];

  passthru = {
    rocknixSteamManifest = manifest;
    rocknixSteamHelpers = steamHelpers;
    rocknixSteamFhs = if isAarch64 then steamFhs else null;
    rocknixSteamHasRunCapsule = isAarch64;
  };

  meta = {
    description = "ROCKNIX-informed guest-native Steam ARM64 package helpers for SM8550";
    homepage = "https://store.steampowered.com/";
    license = lib.licenses.gpl2Only;
    platforms = [ "x86_64-linux" "aarch64-linux" ];
  };
}
