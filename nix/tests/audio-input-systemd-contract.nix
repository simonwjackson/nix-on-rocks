{ pkgs
, baseConfiguration
, devEnvConfiguration
, thorConfiguration
, odin2portalConfiguration
, rg353mProfileConfiguration
}:

let
  helpers = import ./helpers.nix { inherit pkgs; };
  assertContract = helpers.assertContract "audio/input systemd contract";
  cfg = baseConfiguration.config;
  services = cfg.systemd.services;
  pipewire = services.main-space-pipewire;
  pulse = services.main-space-pipewire-pulse;
  wireplumber = services.main-space-wireplumber;
  inputplumber = services.inputplumber;
  hideRaw = services.rocknix-guest-hide-raw-gamepad;
  hydrate = services.rocknix-sound-card-udev-hydrate;
  contains = needle: haystack: builtins.elem needle haystack;
  hasInfix = pkgs.lib.hasInfix;
  audioModuleSource = builtins.readFile ../../guest/modules/audio.nix;
  runtimeDir = "/run/user/${toString cfg.rocknix.session.runtimeDir.uid}";
  thorCfg = thorConfiguration.config;
  thorServices = thorCfg.systemd.services;
  thorBootstrap = thorServices.main-space-audio-sink-bootstrap;
  odinCfg = odin2portalConfiguration.config;
  odinBootstrap = odinCfg.systemd.services.main-space-audio-sink-bootstrap;
  rgCfg = rg353mProfileConfiguration.config;
  rgServices = rgCfg.systemd.services;
  rgBootstrap = rgServices.main-space-audio-sink-bootstrap;
in
helpers.runAssertions "rocknix-audio-input-systemd-contract" [
  (assertContract (contains "multi-user.target" (services.bluetooth.wantedBy or [ ])) "Bluetooth starts during main-space boot")
  (assertContract (services ? main-space-pipewire) "main-space PipeWire service exists")
  (assertContract (services ? main-space-pipewire-pulse) "main-space PipeWire Pulse service exists")
  (assertContract (services ? main-space-wireplumber) "main-space WirePlumber service exists")
  (assertContract (services ? rocknix-sound-card-udev-hydrate) "generic sound-card udev hydration service exists")
  (assertContract (contains "main-space-runtime-dir.service" (pipewire.after or [ ])) "PipeWire orders after runtime-dir anchor")
  (assertContract (contains "main-space-session-dbus.service" (pipewire.after or [ ])) "PipeWire orders after session D-Bus")
  (assertContract (contains "main-space-runtime-dir.service" (pulse.after or [ ])) "PipeWire Pulse orders after runtime-dir anchor")
  (assertContract (contains "main-space-pipewire.service" (pulse.after or [ ])) "PipeWire Pulse orders after PipeWire")
  (assertContract (contains "main-space-runtime-dir.service" (wireplumber.after or [ ])) "WirePlumber orders after runtime-dir anchor")
  (assertContract (contains "rocknix-sound-card-udev-hydrate.service" (wireplumber.after or [ ])) "WirePlumber orders after sound-card udev hydration")
  (assertContract (contains "main-space-wireplumber.service" (hydrate.before or [ ])) "sound-card udev hydration runs before WirePlumber")
  (assertContract (pipewire.environment.XDG_RUNTIME_DIR == runtimeDir) "PipeWire runtime dir is parameterized")
  (assertContract (pipewire.environment.PIPEWIRE_RUNTIME_DIR == runtimeDir) "PipeWire runtime env is parameterized")
  (assertContract (pipewire.environment.PULSE_SERVER == "unix:${runtimeDir}/pulse/native") "PipeWire Pulse server path is parameterized")
  (assertContract (pipewire.environment.ALSA_CONFIG_UCM2 != "") "PipeWire receives guest-owned UCM path")
  (assertContract (pipewire.environment.ALSA_CONFIG_UCM2 == "${cfg.rocknix.device.audio.ucmPackage}/share/alsa/ucm2") "PipeWire consumes the generic device UCM package")
  (assertContract (wireplumber.environment.ALSA_CONFIG_UCM2 == pipewire.environment.ALSA_CONFIG_UCM2) "WirePlumber uses same guest-owned UCM path")
  (assertContract (!(services ? main-space-audio-sink-bootstrap)) "no default-route bootstrap is created when the route kind is none")
  (assertContract (hasInfix "sink_exists()" audioModuleSource) "audio bootstrap uses exact sink-name matching helper")
  (assertContract (hasInfix "expected WirePlumber sink" audioModuleSource) "audio bootstrap polls for declared WirePlumber/UCM sinks")
  (assertContract (hasInfix "routeHasFullUcm" audioModuleSource) "audio bootstrap combines full UCM activation in one alsaucm invocation")
  (assertContract (hasInfix "ucmCard = cfg.ucmCard" audioModuleSource) "audio bootstrap uses the UCM config id separately from kernel card id")
  (assertContract (hasInfix "set _verb" audioModuleSource && hasInfix "set _enadev" audioModuleSource) "audio bootstrap activates declared UCM verb/device")
  (assertContract (hasInfix "load-module module-alsa-sink" audioModuleSource) "audio bootstrap retains manual PCM sink loading")
  (assertContract (hasInfix "failed to select declared default sink" audioModuleSource) "audio bootstrap fails when default sink selection fails")
  (assertContract (hasInfix "cfg.route.expectedSink != \"\"" audioModuleSource) "wireplumber route validation rejects empty sink names")
  (assertContract (hasInfix "cfg.route.pcm != \"\"" audioModuleSource) "manual route validation rejects empty PCMs")
  (assertContract (contains "c /dev/uinput 0600 root root - 10:223" cfg.systemd.tmpfiles.rules) "/dev/uinput tmpfiles rule exists")
  (assertContract cfg.services.inputplumber.enable "InputPlumber service is enabled")
  (assertContract (contains "main-space-sway-kiosk.service" (inputplumber.before or [ ])) "InputPlumber starts before fallback Sway")
  (assertContract (inputplumber.before == [ "main-space-sway-kiosk.service" ]) "InputPlumber ordering names no product units")
  (assertContract (contains "inputplumber.service" (hideRaw.wants or [ ])) "raw gamepad hider wants InputPlumber")
  (assertContract (contains "inputplumber.service" (hideRaw.after or [ ])) "raw gamepad hider orders after InputPlumber")
  (assertContract (builtins.elem "AYN Odin2 Gamepad" cfg.rocknix.device.input.rawGamepadEventNames) "raw gamepad names live under the generic device seam")
  (assertContract (builtins.elem "Microsoft Xbox Series S|X Controller" cfg.rocknix.device.input.virtualGamepadEventNames) "live SM8550 virtual gamepad name lives under the generic device seam")
  (assertContract (builtins.elem "Microsoft X-Box 360 pad" cfg.rocknix.device.input.virtualGamepadEventNames) "legacy SM8550 virtual gamepad name remains accepted")

  # Neutral audio API capability — the value the product layer translates
  # into SDL_AUDIODRIVER / client-specific environment.
  (assertContract (cfg.rocknix.sm8550.audio.api == "pulseaudio") "SM8550 substrate exposes a PulseAudio-compatible audio API")
  (assertContract (cfg.rocknix.device.audio.card == "AYNOdin2") "SM8550 keeps the kernel ALSA card id")
  (assertContract (cfg.rocknix.device.audio.ucmCard == "AYN-Odin2") "SM8550 exposes the UCM configuration id separately")

  # Thor's substrate-owned speaker route is graph-owned by WirePlumber/UCM.
  (assertContract (thorCfg.rocknix.device.audio.route.kind == "wireplumber-ucm") "Thor declares a WirePlumber/UCM route strategy")
  (assertContract (thorCfg.rocknix.device.audio.route.expectedSink == "alsa_output.platform-sound.HiFi__Speaker__sink") "Thor declares the validated graph-created speaker sink")
  (assertContract (thorCfg.rocknix.device.audio.card == "AYNOdin2") "Thor keeps the kernel ALSA card id")
  (assertContract (thorCfg.rocknix.device.audio.ucmCard == "AYN-Odin2") "Thor uses the shipped Odin2 UCM config id")
  (assertContract (thorCfg.rocknix.device.audio.defaultSink.pcm == null) "Thor no longer declares a direct speaker PCM")
  (assertContract (thorCfg.rocknix.device.audio.route.ucmVerb == "HiFi") "Thor declares the speaker UCM verb")
  (assertContract (thorCfg.rocknix.device.audio.route.ucmDevice == "Speaker") "Thor declares the speaker UCM device")
  (assertContract (thorServices ? main-space-audio-sink-bootstrap) "Thor substrate exposes a default-route bootstrap service")
  (assertContract (thorBootstrap.serviceConfig.Type == "oneshot") "Thor sink bootstrap is oneshot")
  (assertContract (thorBootstrap.serviceConfig.RemainAfterExit == true) "Thor sink bootstrap remains active after success")
  (assertContract (contains "main-space-pipewire.service" (thorBootstrap.after or [ ])) "Thor sink bootstrap orders after PipeWire")
  (assertContract (contains "main-space-pipewire-pulse.service" (thorBootstrap.after or [ ])) "Thor sink bootstrap orders after PipeWire Pulse")
  (assertContract (contains "main-space-wireplumber.service" (thorBootstrap.after or [ ])) "Thor sink bootstrap orders after WirePlumber")
  (assertContract (contains "main-space-sway-kiosk.service" (thorBootstrap.before or [ ])) "Thor sink bootstrap orders before fallback Sway kiosk")
  (assertContract (thorBootstrap.before == [ "main-space-sway-kiosk.service" ]) "Thor sink bootstrap ordering names no product units")
  (assertContract (thorBootstrap.environment.XDG_RUNTIME_DIR == "/run/user/${toString thorCfg.rocknix.session.runtimeDir.uid}") "Thor sink bootstrap retains main-space XDG_RUNTIME_DIR")
  (assertContract (thorBootstrap.environment.PIPEWIRE_RUNTIME_DIR == thorBootstrap.environment.XDG_RUNTIME_DIR) "Thor sink bootstrap retains PIPEWIRE_RUNTIME_DIR")
  (assertContract (thorBootstrap.environment.PULSE_SERVER == "unix:${thorBootstrap.environment.XDG_RUNTIME_DIR}/pulse/native") "Thor sink bootstrap retains PULSE_SERVER")
  (assertContract (thorBootstrap.environment.ALSA_CONFIG_UCM2 != "") "Thor sink bootstrap retains UCM path")

  # Odin 2 Portal/Sobo now shares the same SM8550 WirePlumber/UCM route, not a
  # Thor direct PCM or arbitrary default sink fallback.
  (assertContract (odinCfg.rocknix.device.audio.route.kind == "wireplumber-ucm") "Odin 2 Portal declares a WirePlumber/UCM route strategy")
  (assertContract (odinCfg.rocknix.device.audio.route.expectedSink == "alsa_output.platform-sound.HiFi__Speaker__sink") "Odin 2 Portal declares the validated graph-created speaker sink")
  (assertContract (odinCfg.rocknix.device.audio.card == "AYNOdin2") "Odin 2 Portal keeps the kernel ALSA card id")
  (assertContract (odinCfg.rocknix.device.audio.ucmCard == "AYN-Odin2") "Odin 2 Portal uses the shipped Odin2 UCM config id")
  (assertContract (odinCfg.rocknix.device.audio.defaultSink.pcm == null) "Odin 2 Portal leaves the direct default-sink PCM null")
  (assertContract (odinCfg.systemd.services ? main-space-audio-sink-bootstrap) "Odin 2 Portal selects the declared graph sink at boot")
  (assertContract (odinBootstrap.serviceConfig.Type == "oneshot") "Odin 2 Portal route bootstrap is oneshot")

  # RG353M receives the same substrate audio services and hydration, while its
  # speaker remains an explicit interim manual PCM route.
  (assertContract (rgServices ? main-space-pipewire) "RG353M has main-space PipeWire")
  (assertContract (rgServices ? main-space-wireplumber) "RG353M has main-space WirePlumber")
  (assertContract (rgServices ? rocknix-sound-card-udev-hydrate) "RG353M has generic sound-card udev hydration")
  (assertContract (contains "rocknix-sound-card-udev-hydrate.service" (rgServices.main-space-wireplumber.after or [ ])) "RG353M WirePlumber waits for sound-card hydration")
  (assertContract (rgCfg.rocknix.device.audio.ucmCard == "rk817ext") "RG353M mirrors the RK817 UCM/card id")
  (assertContract (rgCfg.rocknix.device.audio.route.kind == "manual-pcm") "RG353M declares an explicit interim manual PCM route")
  (assertContract (rgCfg.rocknix.device.audio.route.pcm == "hw:rk817ext,0") "RG353M uses stable RK817 card-name PCM facts")
  (assertContract (rgCfg.rocknix.device.audio.route.sinkName == "rg353m_speaker") "RG353M declares the live-validated speaker sink name")
  (assertContract (rgServices ? main-space-audio-sink-bootstrap) "RG353M creates a declared default-route bootstrap service")
  (assertContract (contains "main-space-pipewire-pulse.service" (rgBootstrap.after or [ ])) "RG353M route bootstrap waits for PipeWire Pulse")
  (assertContract (rgBootstrap.environment.ALSA_CONFIG_UCM2 == "${rgCfg.rocknix.device.audio.ucmPackage}/share/alsa/ucm2") "RG353M route bootstrap receives the generic device UCM path")
]
