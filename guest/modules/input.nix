# Guest-owned input routing for SM8550 handheld controls.
#
# ROCKNIX used to run InputPlumber on the host and bind a scrubbed udev DB into
# the guest so sway/libseat would not open InputPlumber-hidden raw event nodes.
# The minimal-host direction is for the guest to own the product input stack,
# leaving the host with only kernel/device/container substrate.
{
  config,
  lib,
  pkgs,
  options,
  ...
}:

let
  rocknixInputplumber = pkgs.callPackage ../packages/inputplumber { };
  hasKorriKiosk = options.services ? korri && options.services.korri ? kiosk;
in
{
  environment.systemPackages = [ rocknixInputplumber ];

  # InputPlumber creates virtual keyboard/mouse/gamepad devices through uinput.
  # The host nspawn unit allows the cgroup device and binds /dev/uinput; this
  # tmpfiles rule also makes live migrations work on existing roots where the
  # node was not present when the container started.
  systemd.tmpfiles.rules = [
    "c /dev/uinput 0600 root root - 10:223"
  ];

  services.inputplumber = {
    enable = true;
    package = rocknixInputplumber;
  };

  # The nixpkgs service module sets XDG_DATA_DIRS so InputPlumber discovers
  # /run/current-system/sw/share/inputplumber, including the SM8550 maps in the
  # package above. Order it before sway so libseat sees the virtual devices and
  # does not race raw controller ownership.
  systemd.services.inputplumber = {
    before = [
      "main-space-sway-kiosk.service"
      "korri-kiosk.service"
    ];
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
