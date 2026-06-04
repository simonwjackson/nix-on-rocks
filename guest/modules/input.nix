# Guest-owned input routing for handheld controls.
#
# ROCKNIX used to run InputPlumber on the host and bind a scrubbed udev DB into
# the guest so sway/libseat would not open InputPlumber-hidden raw event nodes.
# The minimal-host direction is for the guest to own the product input stack,
# leaving the host with only kernel/device/container substrate.
{ config
, lib
, pkgs
, options
, ...
}:

let
  rocknixInputplumber = pkgs.callPackage ../../packages/inputplumber { };
  hasKorriKiosk = options.services ? korri && options.services.korri ? kiosk;
  input = config.rocknix.device.input;
  rawGamepadEventNames = lib.concatMapStringsSep " " lib.escapeShellArg input.rawGamepadEventNames;
  virtualGamepadEventNames = lib.concatMapStringsSep " " lib.escapeShellArg input.virtualGamepadEventNames;
in
{
  environment.systemPackages = [ rocknixInputplumber ];
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
    before = [
      "korri-compositor.service"
      "korri-inputd.service"
      "main-space-sway-kiosk.service"
      "korri-kiosk.service"
    ];
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
      for event in /dev/input/event*; do
        [ -e "$event" ] || continue
        name_path="/sys/class/input/$(basename "$event")/device/name"
        [ -r "$name_path" ] || continue
        name="$(cat "$name_path")"
        name_matches "$name" ${rawGamepadEventNames} || continue

        target="/dev/inputplumber/sources/$(basename "$event")"
        if [ ! -e "$target" ]; then
          mv "$event" "$target"
        fi
        moved=1
      done

      [ "$moved" = 1 ] || {
        echo "Raw gamepad event node was not found" >&2
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
    before = [
      "main-space-sway-kiosk.service"
      "korri-kiosk.service"
    ];
    environment = {
      HIDE_DEVICES_FROM_ROOT = "1";
    };
    serviceConfig = {
      Restart = lib.mkForce "on-failure";
      RestartSec = lib.mkForce 2;
    };
  };

  systemd.services.main-space-sway-kiosk = lib.mkIf (!hasKorriKiosk) {
    wants = [ "inputplumber.service" ];
    after = [ "inputplumber.service" ];
  };
}
