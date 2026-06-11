# Guest-owned input routing for handheld controls.
#
# ROCKNIX used to run InputPlumber on the host and bind a scrubbed udev DB into
# the guest so sway/libseat would not open InputPlumber-hidden raw event nodes.
# The minimal-host direction is for the guest to own the product input stack,
# leaving the host with only kernel/device/container substrate.
{ config
, lib
, pkgs
, ...
}:

let
  rocknixInputplumber = pkgs.callPackage ../../packages/inputplumber { };
  input = config.rocknix.device.input;
  rawGamepadEventNames = lib.concatMapStringsSep " " lib.escapeShellArg input.rawGamepadEventNames;
  virtualGamepadEventNames = lib.concatMapStringsSep " " lib.escapeShellArg input.virtualGamepadEventNames;
in
{
  environment.systemPackages = [ rocknixInputplumber ];

  # InputPlumber v0.75.2 does not merge every entry in XDG_DATA_DIRS. Its
  # get_base_path() helper returns the first existing inputplumber data root,
  # then device/capability/profile discovery is relative to that single root.
  # Keep /run/current-system/sw/share first so product-specific map packages
  # linked into the system profile (SM8550/RK3566) are visible to the daemon,
  # while still retaining the package share as a fallback.
  environment.pathsToLink = [ "/share/inputplumber" ];

  services.udev.packages = [ rocknixInputplumber ];

  # InputPlumber creates virtual keyboard/mouse/gamepad devices through uinput.
  # The host nspawn unit allows the cgroup device and binds /dev/uinput; this
  # tmpfiles rule also makes live migrations work on existing roots where the
  # node was not present when the container started.
  systemd.tmpfiles.rules = [
    "c /dev/uinput 0600 root root - 10:223"
    "L /dev/inputplumber - - - - /dev/input/.inputplumber"
    "d /run/udev/rules.d 0755 root root -"
  ];

  services.inputplumber = {
    enable = true;
    package = rocknixInputplumber;
  };

  systemd.services.rocknix-guest-hide-raw-gamepad = {
    description = "Hide raw gamepad event nodes after InputPlumber claims them";
    wantedBy = [ "multi-user.target" ];
    wants = [ "inputplumber.service" ];
    after = [ "inputplumber.service" ];
    # Ordering against the substrate fallback compositor only. Downstream
    # product sessions order themselves after this unit from their side;
    # the substrate does not know product unit names.
    before = [ "main-space-sway-kiosk.service" ];
    path = [ pkgs.coreutils ];
    script = ''
      set -eu

      mkdir -p /dev/inputplumber/sources

      name_matches() {
        candidate="$1"
        shift
        for wanted in "$@"; do
          [ "$candidate" = "$wanted" ] && return 0
        done
        return 1
      }

      # Wait until InputPlumber has opened the raw pad and created the virtual
      # target. Moving the node before that point would hide the source from
      # InputPlumber itself; moving after preserves InputPlumber's fd while
      # removing the raw node from later consumers such as Moonlight/libinput.
      for _ in $(seq 1 200); do
        for name in /sys/class/input/event*/device/name; do
          [ -r "$name" ] || continue
          if name_matches "$(cat "$name")" ${virtualGamepadEventNames}; then
            found_virtual_gamepad=1
            break 2
          fi
        done
        sleep 0.1
      done

      [ "''${found_virtual_gamepad:-0}" = 1 ] || {
        echo "InputPlumber virtual Xbox target did not appear" >&2
        exit 1
      }

      moved=0
      for name_path in /sys/class/input/event*/device/name; do
        [ -r "$name_path" ] || continue
        event_name="$(basename "$(dirname "$(dirname "$name_path")")")"
        source="/dev/input/$event_name"
        target="/dev/inputplumber/sources/$event_name"
        name="$(cat "$name_path")"
        name_matches "$name" ${rawGamepadEventNames} || continue

        if [ -e "$target" ]; then
          moved=1
          continue
        fi
        if [ -e "$source" ]; then
          mv "$source" "$target"
          moved=1
        fi
      done

      [ "$moved" = 1 ] || {
        echo "Raw gamepad event node was not found or already hidden under an unexpected name" >&2
        exit 1
      }
    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
  };

  # The nixpkgs service module sets XDG_DATA_DIRS so InputPlumber discovers
  # /run/current-system/sw/share/inputplumber, including the SM8550 maps in the
  # package above. Order it before sway so libseat sees the virtual devices and
  # does not race raw controller ownership.
  systemd.services.inputplumber = {
    wants = [ "systemd-udev-settle.service" ];
    after = [ "systemd-udev-settle.service" ];
    before = [ "main-space-sway-kiosk.service" ];
    environment = {
      HIDE_DEVICES_FROM_ROOT = "1";
      XDG_DATA_DIRS = lib.mkForce "/run/current-system/sw/share:${config.services.inputplumber.package}/share";
    };
    serviceConfig = {
      Restart = lib.mkForce "on-failure";
      RestartSec = lib.mkForce 2;
    };
  };

}
