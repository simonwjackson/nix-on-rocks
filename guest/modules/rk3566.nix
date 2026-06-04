# RK3566 device policy scaffold.
#
# This module intentionally provides only evaluation-safe defaults until an
# RG353M is probed. It owns the RK3566 device id and overrides the generic
# rocknix.device.* seam introduced for non-SM8550 targets without claiming
# final display, input, audio, or performance behavior.
{ config, lib, pkgs, ... }:

let
  inherit (lib) mkForce mkOption types;
  emptyRk3566Ucm = pkgs.runCommand "rk3566-empty-ucm" { } ''
    mkdir -p $out/share/alsa/ucm2
  '';
in
{
  options.rocknix.rk3566 = {
    deviceId = mkOption {
      type = types.enum [ "rg353m" ];
      default = "rg353m";
      description = "RK3566 handheld variant targeted by this guest profile.";
    };
  };

  config.rocknix.device = {
    id = mkForce config.rocknix.rk3566.deviceId;

    # Physical RG353M official ROCKNIX SD-boot evidence captured on 2026-06-04:
    # /sys/class/drm/card0-DSI-1 is connected/enabled at 640x480, HDMI-A-1 is
    # present but disconnected, and the backlight node is /sys/class/backlight/backlight.
    display.swayDeviceConfig = mkForce ''
      # RG353M: captured SD-boot panel path is card0-DSI-1 at 640x480.
      # Keep the handheld panel as-is; do not inherit SM8550 Thor/Odin transforms.
      output DSI-1 mode 640x480
      output DSI-1 pos 0 0
      output DSI-1 bg #000000 solid_color
    '';

    input = {
      powerEventNames = mkForce [ "rk805 pwrkey" ];
      volumeDownEventNames = mkForce [ "gpio-keys-vol" ];
      volumeUpLidEventNames = mkForce [ "gpio-keys-vol" ];
      rawGamepadEventNames = mkForce [ "retrogame_joypad" ];
      virtualGamepadEventNames = mkForce [ ];
    };

    # Placeholder only: task-013 owns real RK817 audio bring-up after the device
    # reports its ALSA card and mixer topology.
    audio.ucmPackage = mkForce emptyRk3566Ucm;

    # Avoid an SM8550-tuned CPU mask on RK3566 until performance evidence exists.
    performance.cemuAffinityMask = mkForce "none";
  };
}
