# Guest-native ARM64 Steam runtime support.
#
# The Steam package owns generic Steam/FEX/pressure-vessel runtime mechanics.
# This module is the SM8550 guest adapter: it supplies /storage defaults,
# session/driver environment, and substrate services such as uinput repair.
{ config, lib, pkgs, ... }:

let
  cfg = config.rocknix.steam;

  defaultSteamArgs = [
    "-steamdeck"
    "-gamepadui"
    "-forcedesktopscaling"
    "1.5"
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

  steamLauncher = pkgs.writeShellScriptBin "rocknix-steam-guest" ''
    set -e

    export HOME="''${HOME:-/storage}"
    export USER="''${USER:-root}"
    export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/0}"
    export WAYLAND_DISPLAY="''${WAYLAND_DISPLAY:-wayland-1}"
    export DISPLAY="''${DISPLAY:-:0}"
    export DBUS_SESSION_BUS_ADDRESS="''${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/0/bus}"
    export LANG="''${LANG:-C.UTF-8}"
    if [ -z "''${STEAM_HOME:-}" ]; then export STEAM_HOME=${lib.escapeShellArg cfg.home}; fi
    if [ -z "''${STEAM_GAMES_ROOT:-}" ]; then export STEAM_GAMES_ROOT=${lib.escapeShellArg cfg.gamesRoot}; fi
    if [ -z "''${STEAM_DOT:-}" ]; then export STEAM_DOT=${lib.escapeShellArg cfg.dotDir}; fi
    if [ -z "''${FEX_ROOTFS:-}" ]; then export FEX_ROOTFS=${lib.escapeShellArg cfg.fexRootfs}; fi

    export SDL_JOYSTICK_DISABLE_UDEV="''${SDL_JOYSTICK_DISABLE_UDEV:-1}"
    export GTK_IM_MODULE="''${GTK_IM_MODULE:-xim}"
    unset GIO_EXTRA_MODULES

    export LIBGL_DRIVERS_PATH="''${LIBGL_DRIVERS_PATH:-/run/opengl-driver/lib/dri}"
    export __EGL_VENDOR_LIBRARY_DIRS="''${__EGL_VENDOR_LIBRARY_DIRS:-/run/opengl-driver/share/glvnd/egl_vendor.d}"
    export LIBVA_DRIVERS_PATH="''${LIBVA_DRIVERS_PATH:-/run/opengl-driver/lib/dri}"
    export VDPAU_DRIVER_PATH="''${VDPAU_DRIVER_PATH:-/run/opengl-driver/lib/vdpau}"

    ${steamUinputPrep}/bin/rocknix-steam-ensure-uinput || true

    if [ "$#" -eq 0 ]; then
      set -- ${lib.escapeShellArgs cfg.defaultArgs}
    fi

    exec ${cfg.package}/bin/steam-arm64-fhs "$@"
  '';
in
{
  options.rocknix.steam = {
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../packages/steam/package.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ../../packages/steam/package.nix { }";
      description = "Package-owned Steam runtime capsule consumed by the SM8550 guest adapter.";
    };

    home = lib.mkOption {
      type = lib.types.str;
      default = "/storage/.local/share/Steam";
      description = "Mutable guest Steam home supplied to package-owned helpers.";
    };

    gamesRoot = lib.mkOption {
      type = lib.types.str;
      default = "/storage/games-internal/roms/steam";
      description = "Mutable guest Steam library root supplied to package-owned helpers.";
    };

    dotDir = lib.mkOption {
      type = lib.types.str;
      default = "/storage/.steam";
      description = "Mutable guest Steam dot-directory used by bootstrap and seed helpers.";
    };

    fexRootfs = lib.mkOption {
      type = lib.types.str;
      default = "/storage/.local/share/fex-emu/RootFS/ArchLinux";
      description = "Guest-provided FEX rootfs path for x86 Steam Runtime helpers and games.";
    };

    defaultArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = defaultSteamArgs;
      description = "Default Steam client arguments supplied by the SM8550 guest adapter.";
    };
  };

  config = {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.system == "aarch64-linux";
        message = "guest/modules/steam.nix requires the aarch64 Steam run capsule; x86 package support is helper/check-only.";
      }
      {
        assertion = cfg.package ? rocknixSteamHasRunCapsule && cfg.package.rocknixSteamHasRunCapsule;
        message = "rocknix.steam.package must provide the aarch64 Steam run capsule; helper-only x86 packages cannot satisfy the guest launcher.";
      }
    ];

    environment.systemPackages = [
      cfg.package
      steamLauncher
      steamUinputPrep
    ];

    systemd.services.main-space-steam-uinput = {
      description = "Prepare the guest uinput device for Steam Input";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${steamUinputPrep}/bin/rocknix-steam-ensure-uinput";
        RemainAfterExit = true;
      };
    };
  };
}
