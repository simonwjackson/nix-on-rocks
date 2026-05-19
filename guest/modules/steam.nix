# Guest-native ARM64 Steam runtime support.
#
# Steam's ARM64 client is a mutable generic-Linux payload under /storage.  On
# NixOS it needs the same kind of FHS runtime that nixpkgs uses for Steam:
# a conventional /lib dynamic linker, /usr tools, ld.so.cache, graphics driver
# discovery paths, FEX for x86/x86_64 runtime helpers, and a stable session bus.
# Keep the mutable Valve payload in /storage; keep the guest runtime contract here.
{ pkgs, ... }:

let
  defaultSteamArgs = [
    "-steamdeck"
    "-gamepadui"
    "-forcedesktopscaling" "1.5"
    "-noverifyfiles"
    "-nobootstrapupdate"
    "-skipinitialbootstrap"
    "-norepairfiles"
  ];

  steamUinputPrep = pkgs.writeShellScriptBin "rocknix-steam-ensure-uinput" ''
    set -eu

    warn() {
      echo "rocknix-steam-ensure-uinput: warning: $*" >&2
    }

    if [ -c /dev/uinput ]; then
      ${pkgs.coreutils}/bin/chmod 0660 /dev/uinput 2>/dev/null || true
      exit 0
    fi

    if [ -e /dev/uinput ]; then
      # A stale regular placeholder makes Steam Input's open(2) succeed but
      # uinput ioctls fail later as "Couldn't configure axes".  Only replace
      # plain files/symlinks; leave unusual mounts alone and report them.
      if [ -f /dev/uinput ] || [ -L /dev/uinput ]; then
        ${pkgs.coreutils}/bin/rm -f /dev/uinput 2>/dev/null || {
          warn "could not remove stale non-character /dev/uinput"
          exit 0
        }
      else
        warn "existing /dev/uinput is not a character device; leaving it untouched"
        exit 0
      fi
    fi

    devno=""
    if [ -r /sys/devices/virtual/misc/uinput/dev ]; then
      devno="$(${pkgs.coreutils}/bin/cat /sys/devices/virtual/misc/uinput/dev 2>/dev/null || true)"
    fi
    if [ -z "$devno" ] && [ -r /proc/misc ]; then
      minor="$(${pkgs.gawk}/bin/awk '$2 == "uinput" { print $1; exit }' /proc/misc 2>/dev/null || true)"
      if [ -n "$minor" ]; then
        # uinput is a Linux misc device; misc devices use dynamic major 10.
        devno="10:$minor"
      fi
    fi

    case "$devno" in
      [0-9]*:[0-9]*) ;;
      *)
        warn "kernel did not report a uinput device number"
        exit 0
        ;;
    esac

    major="''${devno%:*}"
    minor="''${devno#*:}"
    case "$major:$minor" in
      *[!0-9:]*|:*|*:)
        warn "invalid uinput device number: $devno"
        exit 0
        ;;
    esac

    ${pkgs.coreutils}/bin/mknod /dev/uinput c "$major" "$minor" 2>/dev/null || {
      warn "could not create /dev/uinput c $major:$minor"
      exit 0
    }
    ${pkgs.coreutils}/bin/chmod 0660 /dev/uinput 2>/dev/null || true
  '';

  steamRuntimePrep = pkgs.writeShellScriptBin "rocknix-steam-prepare-runtime" ''
    set -eu

    steam_home="''${STEAM_HOME:-/storage/.local/share/Steam}"
    common="$steam_home/steamapps/common"
    [ -d "$common" ] || exit 0

    restore_fex_wrapper() {
      file="$1"
      [ -f "$file" ] || return 0
      for suffix in x86_64 x86; do
        backup="$file.$suffix"
        if [ -f "$backup" ] && ${pkgs.gnugrep}/bin/grep -q "FEX_ROOTFS\|/FEX" "$file" 2>/dev/null; then
          mv -f "$backup" "$file"
          chmod a+rx "$file" 2>/dev/null || true
          return 0
        fi
      done
    }

    wrap_fex_tool() {
      file="$1"
      [ -f "$file" ] || return 0
      case "''${file##*/}" in
        srt-bwrap)
          backup="$file.x86_64"
          if [ ! -e "$backup" ]; then
            mv -f "$file" "$backup"
          fi
          cat > "$file" <<'EOF'
#!/bin/sh
exec ${pkgs.bubblewrap}/bin/bwrap "$@"
EOF
          chmod 755 "$file"
          return 0
          ;;
      esac

      if ${pkgs.gnugrep}/bin/grep -q "FEX_ROOTFS\|/FEX" "$file" 2>/dev/null; then
        return 0
      fi

      info="$(${pkgs.file}/bin/file "$file" 2>/dev/null || true)"
      case "$info" in
        *"shared object"*)
          return 0
          ;;
        *"executable"*"x86-64"*|*"x86-64"*"executable"*|*"executable"*"Intel 80386"*|*"Intel 80386"*"executable"*)
          backup="$file.x86_64"
          if [ ! -e "$backup" ]; then
            mv -f "$file" "$backup"
          fi
          cat > "$file" <<'EOF'
#!/bin/sh
FEX_ROOTFS="''${FEX_ROOTFS:-/storage/.local/share/fex-emu/RootFS/ArchLinux}"
PATH="/usr/bin:/bin:/usr/sbin:/sbin:''${PATH:-}"
export FEX_ROOTFS PATH
exec ${pkgs.fex}/bin/FEX "$0.x86_64" "$@"
EOF
          chmod 755 "$file"
          ;;
      esac
    }

    # Earlier live experiments wrapped Proton/Wine payloads themselves.  That
    # breaks Wine's own ELF-header checks.  Keep Proton intact and wrap only
    # Steam Runtime / pressure-vessel's Linux helper executables, which are
    # x86/x86_64 binaries launched by the ARM64 Steam client.
    for dir in "$common"/Proton*/files/bin "$common"/Proton*/files/bin-wow64 "$common"/Proton*/files/lib/wine/*-unix; do
      [ -d "$dir" ] || continue
      ${pkgs.findutils}/bin/find "$dir" -maxdepth 1 -type f | while IFS= read -r file; do
        restore_fex_wrapper "$file"
      done
    done

    for pv in "$common"/SteamLinuxRuntime*/pressure-vessel "$steam_home"/steamrt64/pv-runtime/steam-runtime-steamrt/pressure-vessel; do
      [ -d "$pv" ] || continue
      ${pkgs.findutils}/bin/find "$pv" -type f -perm -0100 | while IFS= read -r file; do
        wrap_fex_tool "$file"
      done
    done

    # Steam Runtime font containers copy .uuid marker files from every font
    # directory they mirror. Some ARM64 runtime snapshots lack these marker
    # files, which makes pressure-vessel abort before Proton starts.
    for fonts in "$common"/SteamLinuxRuntime*/steamrt*_platform_*/files/share/fonts "$common"/SteamLinuxRuntime*/sniper_platform_*/files/share/fonts; do
      [ -d "$fonts" ] || continue
      ${pkgs.findutils}/bin/find "$fonts" -type d | while IFS= read -r dir; do
        : > "$dir/.uuid"
      done
    done

    # Proton and Steam Runtime helper scripts commonly use /usr/bin/env
    # python3. In nested pressure-vessel containers PATH is intentionally
    # sparse, so use the FHS-visible absolute interpreter from the FHS runtime.
    for proton in "$common"/Proton*/proton; do
      [ -f "$proton" ] || continue
      first_line="$(${pkgs.coreutils}/bin/head -n 1 "$proton" 2>/dev/null || true)"
      if [ "$first_line" = "#!/usr/bin/env python3" ]; then
        tmp="$proton.rocknix-python3-tmp"
        { echo '#!/usr/bin/python3'; ${pkgs.gnused}/bin/sed '1d' "$proton"; } > "$tmp"
        chmod --reference="$proton" "$tmp" 2>/dev/null || chmod a+rx "$tmp"
        mv -f "$tmp" "$proton"
      fi
    done

    for py in "$common"/SteamLinuxRuntime*/steamrt*_platform_*/files/bin/python3.* "$common"/SteamLinuxRuntime*/sniper_platform_*/files/bin/python3.*; do
      [ -x "$py" ] || continue
      bindir="''${py%/*}"
      base="''${py##*/}"
      ln -sfn "$base" "$bindir/python3"
      ln -sfn "$base" "$bindir/python"
    done
  '';

  steamRunScript = pkgs.writeShellScript "rocknix-steam-arm64-run" ''
    set -e

    export HOME="''${HOME:-/storage}"
    export USER="''${USER:-root}"
    export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/0}"
    export WAYLAND_DISPLAY="''${WAYLAND_DISPLAY:-wayland-1}"
    export DISPLAY="''${DISPLAY:-:0}"
    export DBUS_SESSION_BUS_ADDRESS="''${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/0/bus}"
    export LANG="''${LANG:-C.UTF-8}"
    export STEAM_HOME="''${STEAM_HOME:-/storage/.local/share/Steam}"
    export STEAM_GAMES_ROOT="''${STEAM_GAMES_ROOT:-/storage/games-internal/roms/steam}"
    export FEX_ROOTFS="''${FEX_ROOTFS:-/storage/.local/share/fex-emu/RootFS/ArchLinux}"

    ${steamUinputPrep}/bin/rocknix-steam-ensure-uinput || true

    # Steam Input creates a virtual controller through uinput when launching
    # Proton games. The outer guest/FHS has /dev/uinput, but pressure-vessel's
    # nested device view can omit it unless it is explicitly shared. Without
    # this, Steam Big Picture can see the controller while games like Balatro
    # never receive the Steam Input virtual XInput device.
    pv_rw_paths="/dev/uinput:/dev/input"
    if [ -n "''${PRESSURE_VESSEL_FILESYSTEMS_RW:-}" ]; then
      export PRESSURE_VESSEL_FILESYSTEMS_RW="$pv_rw_paths:$PRESSURE_VESSEL_FILESYSTEMS_RW"
    else
      export PRESSURE_VESSEL_FILESYSTEMS_RW="$pv_rw_paths"
    fi

    ${steamRuntimePrep}/bin/rocknix-steam-prepare-runtime || true

    client="''${STEAM_CLIENT:-$STEAM_HOME/steamrtarm64/steam}"
    if [ ! -x "$client" ]; then
      echo "error: guest-native Steam client is missing or not executable: $client" >&2
      echo "hint: seed the ARM64 Steam payload into STEAM_HOME first." >&2
      exit 1
    fi

    export SDL_JOYSTICK_DISABLE_UDEV=1
    export GTK_IM_MODULE=xim
    unset GIO_EXTRA_MODULES

    export LIBGL_DRIVERS_PATH=/run/opengl-driver/lib/dri
    export __EGL_VENDOR_LIBRARY_DIRS=/run/opengl-driver/share/glvnd/egl_vendor.d
    export LIBVA_DRIVERS_PATH=/run/opengl-driver/lib/dri
    export VDPAU_DRIVER_PATH=/run/opengl-driver/lib/vdpau

    # The FHS environment supplies the generic distro ABI and Nix-provided
    # system libraries. This small LD_LIBRARY_PATH is intentionally limited to
    # Valve's mutable ARM64 payload so non-transitive dependencies such as
    # steamrtarm64/libavcodec.so -> libvpx.so.6 resolve without smearing Nix
    # store paths globally.
    export LD_LIBRARY_PATH="$STEAM_HOME/steamrtarm64:$STEAM_HOME/steamrtarm64/video:$STEAM_HOME/lib/aarch64-linux-gnu''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

    # Some Steam helper commands are launched by basename.
    export PATH="$STEAM_HOME/steamrtarm64:$STEAM_HOME/steamrtarm64/bin:$PATH"

    if [ "$#" -eq 0 ]; then
      set -- ${pkgs.lib.escapeShellArgs defaultSteamArgs}
    fi

    cd "$STEAM_HOME"
    exec "$client" "$@"
  '';

  steamFhs = pkgs.buildFHSEnv {
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
      export SDL_JOYSTICK_DISABLE_UDEV=1
      export GTK_IM_MODULE=xim
      export LIBGL_DRIVERS_PATH=/run/opengl-driver/lib/dri
      export __EGL_VENDOR_LIBRARY_DIRS=/run/opengl-driver/share/glvnd/egl_vendor.d
      export LIBVA_DRIVERS_PATH=/run/opengl-driver/lib/dri
      export VDPAU_DRIVER_PATH=/run/opengl-driver/lib/vdpau
      export FEX_ROOTFS="''${FEX_ROOTFS:-/storage/.local/share/fex-emu/RootFS/ArchLinux}"
    '';

    runScript = steamRunScript;

    # Steam expects /sbin/ldconfig to exist. Copy rather than symlink to avoid
    # nested-runtime symlink loops, matching nixpkgs' Steam FHS wrapper.
    extraBuildCommands = ''
      cp -f $out/usr/{bin,sbin}/ldconfig
    '';

    extraBwrapArgs = [
      "--bind-try" "/tmp/dumps" "/tmp/dumps"
    ];
  };

  steamLauncher = pkgs.writeShellScriptBin "rocknix-steam-guest" ''
    set -e
    export HOME="''${HOME:-/storage}"
    export USER="''${USER:-root}"
    export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/0}"
    export WAYLAND_DISPLAY="''${WAYLAND_DISPLAY:-wayland-1}"
    export DISPLAY="''${DISPLAY:-:0}"
    export DBUS_SESSION_BUS_ADDRESS="''${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/0/bus}"
    export LANG="''${LANG:-C.UTF-8}"
    export STEAM_HOME="''${STEAM_HOME:-/storage/.local/share/Steam}"
    export STEAM_GAMES_ROOT="''${STEAM_GAMES_ROOT:-/storage/games-internal/roms/steam}"
    export FEX_ROOTFS="''${FEX_ROOTFS:-/storage/.local/share/fex-emu/RootFS/ArchLinux}"
    exec ${steamFhs}/bin/steam-arm64-fhs "$@"
  '';
in
{
  environment.systemPackages = [
    steamFhs
    steamLauncher
    steamRuntimePrep
    steamUinputPrep
  ];

  systemd.services.rocknix-steam-uinput = {
    description = "Prepare the guest uinput device for Steam Input";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${steamUinputPrep}/bin/rocknix-steam-ensure-uinput";
      RemainAfterExit = true;
    };
  };
}
