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

    # Real connector/orientation/touch routing is intentionally deferred to the
    # hardware probe. Keep this non-empty only as documented Sway config text.
    display.swayDeviceConfig = mkForce ''
      # RK3566/RG353M display topology pending hardware probe.
      # Do not inherit SM8550 Thor/Odin panel assumptions.
    '';

    input = {
      powerEventNames = mkForce [ ];
      volumeDownEventNames = mkForce [ ];
      volumeUpLidEventNames = mkForce [ ];
      rawGamepadEventNames = mkForce [ ];
      virtualGamepadEventNames = mkForce [ ];
    };

    # Placeholder only: task-013 owns real RK817 audio bring-up after the device
    # reports its ALSA card and mixer topology.
    audio.ucmPackage = mkForce emptyRk3566Ucm;

    # Avoid an SM8550-tuned CPU mask on RK3566 until performance evidence exists.
    performance.cemuAffinityMask = mkForce "none";
  };
}
