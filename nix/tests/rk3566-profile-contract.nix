{ pkgs, rg353mProfileConfiguration }:

let
  helpers = import ./helpers.nix { inherit pkgs; };
  assertContract = helpers.assertContract "RK3566 profile contract";
  cfg = rg353mProfileConfiguration.config;
  hasInfix = pkgs.lib.hasInfix;
in
helpers.runAssertions "rocknix-rk3566-profile-contract" [
  (assertContract cfg.boot.isContainer "RG353M profile evaluates as a container rootfs")
  (assertContract (cfg.networking.hostName == "rg353m") "RG353M profile owns a stable hostname")
  (assertContract (cfg.rocknix.rk3566.deviceId == "rg353m") "RG353M profile selects the RK3566 device id")
  (assertContract (cfg.rocknix.device.id == "rg353m") "RG353M profile exposes the generic device id")
  (assertContract (cfg.rocknix.device.audio.ucmPackage != cfg.rocknix.sm8550.audio.ucmPackage) "RK3566 audio package does not reuse the SM8550 UCM package")
  (assertContract (!(hasInfix "DSI-2" cfg.rocknix.device.display.swayDeviceConfig)) "RK3566 display config does not inherit Thor DSI-2 topology")
  (assertContract (!(builtins.elem "AYN Odin2 Gamepad" cfg.rocknix.device.input.rawGamepadEventNames)) "RK3566 raw gamepad names do not inherit AYN Odin2 names")
]
