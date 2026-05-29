{ pkgs, baseConfiguration, devEnvConfiguration }:

let
  helpers = import ./helpers.nix { inherit pkgs; };
  assertContract = helpers.assertContract "guest profile contract";
  cfg = baseConfiguration.config;
  devCfg = devEnvConfiguration.config;
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
  (assertContract cfg.services.tailscale.enable "guest substrate owns Tailscale")
  (assertContract (cfg.services.tailscale.useRoutingFeatures == "client") "Tailscale uses client routing features")
  (assertContract (cfg.rocknix.session.runtimeDir.uid == 0) "main-space runtime-dir uid defaults to root")
  (assertContract (devCfg.programs.sway.enable or false) "dev-env profile keeps display stack evaluable")
]
