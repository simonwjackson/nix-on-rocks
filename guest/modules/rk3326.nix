# RK3326 / R36T Max guest device policy scaffold.
#
# The host lane has hardware proof for boot, RK915 Wi-Fi, and SSH. Display,
# input, and audio are intentionally conservative until Korri-on-hardware
# acceptance evidence is captured.
{ config, lib, pkgs, ... }:

let
  inherit (lib) mkForce mkOption types;
in
{
  options.rocknix.rk3326 = {
    deviceId = mkOption {
      type = types.enum [ "r36tmax" ];
      default = "r36tmax";
      description = "RK3326 handheld variant targeted by this guest profile.";
    };
  };

  config.rocknix.device = {
    id = mkForce config.rocknix.rk3326.deviceId;

    display.swayDeviceConfig = mkForce ''
      # R36T Max: first Korri guest payload lane. Keep output policy broad until
      # DRM connector/mode evidence is captured from the NixOS guest.
      output * bg #000000 solid_color
    '';

    input = {
      powerEventNames = mkForce [ "rk805 pwrkey" ];
      volumeDownEventNames = mkForce [ ];
      volumeUpLidEventNames = mkForce [ ];
      rawGamepadEventNames = mkForce [ ];
      virtualGamepadEventNames = mkForce [ ];
    };

    audio = {
      ucmPackage = mkForce pkgs.alsa-ucm-conf;
      api = mkForce "pulseaudio";
      card = mkForce "rk817ext";
      ucmCard = mkForce "rk817ext";
      route = {
        kind = mkForce "none";
        expectedSink = mkForce null;
        pcm = mkForce null;
        sinkName = mkForce null;
        description = mkForce null;
        ucmVerb = mkForce null;
        ucmDevice = mkForce null;
      };
      defaultSink = {
        pcm = mkForce null;
        name = mkForce "r36tmax_speaker";
        description = mkForce "R36T Max speaker";
        ucmVerb = mkForce null;
        ucmDevice = mkForce null;
      };
    };

    performance.cemuAffinityMask = mkForce "none";
  };
}
