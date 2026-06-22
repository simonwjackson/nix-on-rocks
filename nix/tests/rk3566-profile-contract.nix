{ pkgs, rg353mProfileConfiguration }:

let
  helpers = import ./helpers.nix { inherit pkgs; };
  assertContract = helpers.assertContract "RK3566 profile contract";
  cfg = rg353mProfileConfiguration.config;
  services = cfg.systemd.services;
  audioBootstrap = services.main-space-audio-sink-bootstrap;
  inputplumberEnv = services.inputplumber.environment;
  hasInfix = pkgs.lib.hasInfix;
  hasPrefix = pkgs.lib.hasPrefix;
  contains = needle: haystack: builtins.elem needle haystack;
in
helpers.runAssertions "rocknix-rk3566-profile-contract" [
  (assertContract cfg.boot.isContainer "RG353M profile evaluates as a container rootfs")
  (assertContract (cfg.networking.hostName == "rg353m") "RG353M profile owns a stable hostname")
  (assertContract (cfg.rocknix.rk3566.deviceId == "rg353m") "RG353M profile selects the RK3566 device id")
  (assertContract (cfg.rocknix.device.id == "rg353m") "RG353M profile exposes the generic device id")
  (assertContract (hasInfix "output DSI-1" cfg.rocknix.device.display.swayDeviceConfig) "RG353M display config targets the captured DSI-1 connector")
  (assertContract (hasInfix "640x480" cfg.rocknix.device.display.swayDeviceConfig) "RG353M display config records the captured 640x480 mode")
  (assertContract (!(hasInfix "DSI-2" cfg.rocknix.device.display.swayDeviceConfig)) "RK3566 display config does not inherit Thor DSI-2 topology")
  (assertContract (builtins.elem "rk805 pwrkey" cfg.rocknix.device.input.powerEventNames) "RG353M power input uses the captured rk805 pwrkey event")
  (assertContract (builtins.elem "gpio-keys-vol" cfg.rocknix.device.input.volumeDownEventNames) "RG353M volume-down input uses the captured gpio-keys-vol event")
  (assertContract (builtins.elem "gpio-keys-vol" cfg.rocknix.device.input.volumeUpLidEventNames) "RG353M volume-up input uses the captured gpio-keys-vol event")
  (assertContract (builtins.elem "retrogame_joypad" cfg.rocknix.device.input.rawGamepadEventNames) "RG353M raw gamepad names use the captured retrogame_joypad event")
  (assertContract (builtins.elem "Microsoft Xbox Series S|X Controller" cfg.rocknix.device.input.virtualGamepadEventNames) "RG353M virtual gamepad names match the live InputPlumber target")
  (assertContract (!(builtins.elem "AYN Odin2 Gamepad" cfg.rocknix.device.input.rawGamepadEventNames)) "RK3566 raw gamepad names do not inherit AYN Odin2 names")
  (assertContract (builtins.elem "/share/inputplumber" cfg.environment.pathsToLink) "InputPlumber data is linked into /run/current-system/sw/share")
  (assertContract (hasPrefix "/run/current-system/sw/share:" inputplumberEnv.XDG_DATA_DIRS) "InputPlumber discovers product maps before package defaults")
  (assertContract (cfg.rocknix.device.audio.ucmPackage != cfg.rocknix.sm8550.audio.ucmPackage) "RK3566 audio package does not reuse the SM8550 UCM package")
  (assertContract (hasInfix "alsa-ucm-conf" "${cfg.rocknix.device.audio.ucmPackage}") "RG353M uses the upstream ALSA UCM package instead of the empty placeholder")
  (assertContract (cfg.rocknix.device.audio.card == "rk817ext") "RG353M declares the captured RK817 ALSA card id")
  (assertContract (cfg.rocknix.device.audio.route.kind == "manual-pcm") "RG353M declares an explicit interim manual PCM route")
  (assertContract (cfg.rocknix.device.audio.route.pcm == "hw:rk817ext,0") "RG353M declares a stable RK817 card-name speaker PCM")
  (assertContract (cfg.rocknix.device.audio.defaultSink.pcm == "hw:rk817ext,0") "RG353M legacy default sink mirrors the stable RK817 speaker PCM")
  (assertContract (cfg.rocknix.device.audio.route.sinkName == "rg353m_speaker") "RG353M declares the live-validated speaker sink name")
  (assertContract (services ? rocknix-sound-card-udev-hydrate) "RG353M includes generic sound-card udev hydration")
  (assertContract (builtins.elem "rocknix-sound-card-udev-hydrate.service" (services.main-space-wireplumber.after or [ ])) "RG353M WirePlumber waits for sound-card udev hydration")
  (assertContract (services ? main-space-audio-sink-bootstrap) "RG353M creates a declared default-route bootstrap service")
  (assertContract (contains "main-space-pipewire-pulse.service" (audioBootstrap.after or [ ])) "RG353M sink bootstrap waits for PipeWire Pulse")
  (assertContract (audioBootstrap.environment.ALSA_CONFIG_UCM2 == "${cfg.rocknix.device.audio.ucmPackage}/share/alsa/ucm2") "RG353M sink bootstrap receives the generic device UCM path")
]
