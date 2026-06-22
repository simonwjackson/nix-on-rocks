# RK3566 device policy scaffold.
#
# This module intentionally provides only evaluation-safe defaults until an
# RG353M is probed. It owns the RK3566 device id and overrides the generic
# rocknix.device.* seam introduced for non-SM8550 targets without claiming
# final display, input, audio, or performance behavior.
{ config, lib, pkgs, ... }:

let
  inherit (lib) mkForce mkOption types;
  # Use upstream alsa-ucm-conf for RK817 card naming while bootstrapping an
  # explicit interim direct ALSA sink. WirePlumber discovery is now repaired by
  # the generic sound-card udev hydrator, but RG353M stays on a manual speaker
  # route until a real RK817 UCM/headphone route is validated.
  rk3566Ucm = pkgs.alsa-ucm-conf;
  # RG353M InputPlumber maps shipped in the guest closure so the in-guest
  # InputPlumber discovers them via XDG_DATA_DIRS
  # (/run/current-system/sw/share/inputplumber). Maps the retrogame_joypad
  # D-pad (BTN_DPAD_*) to DPad*, which default capability inference drops.
  rk3566InputplumberMaps =
    pkgs.callPackage ../../packages/inputplumber-rk3566-maps/package.nix { };
in
{
  options.rocknix.rk3566 = {
    deviceId = mkOption {
      type = types.enum [ "rg353m" ];
      default = "rg353m";
      description = "RK3566 handheld variant targeted by this guest profile.";
    };
  };

  config.environment.systemPackages = [ rk3566InputplumberMaps ];

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
      # Live RG353M evidence 2026-06-07: InputPlumber creates this virtual
      # target for the retrogame_joypad source. The raw-gamepad hider waits
      # for this name before moving the raw event node out of later consumers.
      virtualGamepadEventNames = mkForce [ "Microsoft Xbox Series S|X Controller" ];
    };

    audio = {
      ucmPackage = mkForce rk3566Ucm;
      card = mkForce "rk817ext";
      ucmCard = mkForce "rk817ext";
      route = {
        kind = mkForce "manual-pcm";
        pcm = mkForce "hw:rk817ext,0";
        sinkName = mkForce "rg353m_speaker";
        description = mkForce "RG353M speaker";
        expectedSink = mkForce null;
        ucmVerb = mkForce null;
        ucmDevice = mkForce null;
      };
      defaultSink = {
        pcm = mkForce "hw:rk817ext,0";
        name = mkForce "rg353m_speaker";
        description = mkForce "RG353M speaker";
        ucmVerb = mkForce null;
        ucmDevice = mkForce null;
      };
    };

    # Avoid an SM8550-tuned CPU mask on RK3566 until performance evidence exists.
    performance.cemuAffinityMask = mkForce "none";
  };
}
