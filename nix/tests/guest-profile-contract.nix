{ pkgs
, baseConfiguration
, devEnvConfiguration
, thorConfiguration
, odin2portalConfiguration
, videoOverrideConfiguration
}:

let
  helpers = import ./helpers.nix { inherit pkgs; };
  assertContract = helpers.assertContract "guest profile contract";
  cfg = baseConfiguration.config;
  devCfg = devEnvConfiguration.config;
  thorCfg = thorConfiguration.config;
  odinCfg = odin2portalConfiguration.config;
  overrideCfg = videoOverrideConfiguration.config;
in
helpers.runAssertions "rocknix-guest-profile-contract" [
  (assertContract cfg.boot.isContainer "rocknix-guest-base evaluates as a container rootfs")
  (assertContract (cfg.networking.hostName == "rocknix-input-boundary-contract") "base profile can be composed with downstream hostname override")
  (assertContract (cfg.time.timeZone == "America/New_York") "rocknix-guest-base sets a stable timezone")
  (assertContract cfg.programs.sway.enable "display module enables Sway")
  (assertContract cfg.hardware.graphics.enable "display module enables hardware graphics")
  (assertContract cfg.services.dbus.enable "guest substrate enables D-Bus")
  (assertContract cfg.services.pipewire.enable "guest substrate enables PipeWire")
  (assertContract cfg.services.pipewire.alsa.enable "PipeWire ALSA support is enabled")
  (assertContract cfg.services.pipewire.pulse.enable "PipeWire Pulse support is enabled")
  (assertContract cfg.hardware.bluetooth.enable "guest substrate enables Bluetooth")
  (assertContract cfg.hardware.bluetooth.powerOnBoot "guest Bluetooth powers on at boot")
  (assertContract cfg.networking.networkmanager.enable "guest substrate enables NetworkManager")
  (assertContract (cfg.networking.networkmanager.wifi.backend == "iwd") "NetworkManager uses iwd backend")
  (assertContract (!cfg.networking.nftables.enable) "guest substrate keeps nftables service disabled under nspawn")
  (assertContract (!(cfg.services.tailscale.enable or false)) "guest substrate does not own Tailscale service policy")
  (assertContract (!(builtins.any (pkg: (pkg.pname or pkg.name or "") == "tailscale") (cfg.environment.systemPackages or [ ]))) "guest substrate does not install Tailscale as product policy")
  (assertContract (cfg.rocknix.session.runtimeDir.uid == 0) "main-space runtime-dir uid defaults to root")
  (assertContract (cfg.rocknix.device.id == cfg.rocknix.sm8550.deviceId) "generic device id is bridged from SM8550 owner")
  (assertContract (cfg.rocknix.device.display.swayDeviceConfig == cfg.rocknix.sm8550.display.swayDeviceConfig) "generic display config is bridged from SM8550 owner")
  (assertContract (cfg.rocknix.device.input.powerEventNames == cfg.rocknix.sm8550.input.powerEventNames) "generic power input names are bridged from SM8550 owner")
  (assertContract (cfg.rocknix.device.audio.ucmPackage == cfg.rocknix.sm8550.audio.ucmPackage) "generic audio UCM package is bridged from SM8550 owner")
  (assertContract (cfg.rocknix.device.performance.cemuAffinityMask == cfg.rocknix.sm8550.performance.cemuAffinityMask) "generic performance policy is bridged from SM8550 owner")
  (assertContract (cfg.rocknix.sm8550.video.decodeBackend == "v4l2m2m") "SM8550 substrate exposes v4l2m2m as the default video decode backend")
  (assertContract (devCfg.rocknix.sm8550.video.decodeBackend == "v4l2m2m") "dev-env substrate exposes the same SM8550 video decode backend as main-space")
  (assertContract (thorCfg.networking.hostName == "bandai") "Thor profile still evaluates with its hostname")
  (assertContract (thorCfg.rocknix.device.id == "thor") "Thor profile exposes the generic device id")
  (assertContract (thorCfg.rocknix.device.display.swayDeviceConfig == thorCfg.rocknix.sm8550.display.swayDeviceConfig) "Thor profile keeps SM8550 display bridge")
  (assertContract (thorCfg.rocknix.sm8550.video.decodeBackend == "v4l2m2m") "Thor substrate exposes v4l2m2m as its video decode backend")
  (assertContract (odinCfg.networking.hostName == "sobo") "Odin 2 Portal profile still evaluates with its hostname")
  (assertContract (odinCfg.rocknix.device.id == "odin2portal") "Odin 2 Portal profile exposes the generic device id")
  (assertContract (odinCfg.rocknix.device.display.swayDeviceConfig == odinCfg.rocknix.sm8550.display.swayDeviceConfig) "Odin 2 Portal profile keeps SM8550 display bridge")
  (assertContract (odinCfg.rocknix.sm8550.video.decodeBackend == "v4l2m2m") "Odin 2 Portal substrate inherits the same video decode backend without duplicating the value")
  (assertContract (overrideCfg.rocknix.sm8550.video.decodeBackend == "sdl") "A per-device profile can override the SM8550 video decode backend without editing the shared chipset module")
  (assertContract (devCfg.programs.sway.enable or false) "dev-env profile keeps display stack evaluable")
]
