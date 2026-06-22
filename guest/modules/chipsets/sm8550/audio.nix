# SM8550 connectivity policy retained for compatibility after the generic
# main-space audio graph moved to ../audio.nix.
{ pkgs, ... }:

{
  hardware.bluetooth = {
    enable = true;
    # The guest owns Bluetooth HID pairing/connection in main-space mode.
    # Power the controller at boot so trusted mice/keyboards reconnect without
    # a host-side bluetoothd or manual bluetoothctl power-on.
    powerOnBoot = true;
    settings = {
      General = {
        FastConnectable = "true";
        JustWorksRepairing = "always";
      };
    };
  };

  # NixOS' bluez unit is WantedBy=bluetooth.target, but our nspawn main-space
  # boot does not otherwise pull bluetooth.target into the transaction. Start
  # bluetoothd as part of the guest boot so paired HID devices reconnect.
  systemd.services.bluetooth.wantedBy = [ "multi-user.target" ];

  environment.systemPackages = with pkgs; [
    bluez
    bluez-tools
  ];
}
