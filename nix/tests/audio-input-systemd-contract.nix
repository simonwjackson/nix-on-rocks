{ pkgs
, baseConfiguration
, devEnvConfiguration
, thorConfiguration
, odin2portalConfiguration
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
  contains = needle: haystack: builtins.elem needle haystack;
  runtimeDir = "/run/user/${toString cfg.rocknix.session.runtimeDir.uid}";
  thorCfg = thorConfiguration.config;
  thorServices = thorCfg.systemd.services;
  thorBootstrap = thorServices.main-space-audio-sink-bootstrap;
  odinCfg = odin2portalConfiguration.config;
in
helpers.runAssertions "rocknix-audio-input-systemd-contract" [
  (assertContract (contains "multi-user.target" (services.bluetooth.wantedBy or [ ])) "Bluetooth starts during main-space boot")
  (assertContract (services ? main-space-pipewire) "main-space PipeWire service exists")
  (assertContract (services ? main-space-pipewire-pulse) "main-space PipeWire Pulse service exists")
  (assertContract (services ? main-space-wireplumber) "main-space WirePlumber service exists")
  (assertContract (contains "main-space-runtime-dir.service" (pipewire.after or [ ])) "PipeWire orders after runtime-dir anchor")
  (assertContract (contains "main-space-session-dbus.service" (pipewire.after or [ ])) "PipeWire orders after session D-Bus")
  (assertContract (contains "main-space-runtime-dir.service" (pulse.after or [ ])) "PipeWire Pulse orders after runtime-dir anchor")
  (assertContract (contains "main-space-pipewire.service" (pulse.after or [ ])) "PipeWire Pulse orders after PipeWire")
  (assertContract (contains "main-space-runtime-dir.service" (wireplumber.after or [ ])) "WirePlumber orders after runtime-dir anchor")
  (assertContract (pipewire.environment.XDG_RUNTIME_DIR == runtimeDir) "PipeWire runtime dir is parameterized")
  (assertContract (pipewire.environment.PIPEWIRE_RUNTIME_DIR == runtimeDir) "PipeWire runtime env is parameterized")
  (assertContract (pipewire.environment.PULSE_SERVER == "unix:${runtimeDir}/pulse/native") "PipeWire Pulse server path is parameterized")
  (assertContract (pipewire.environment.ALSA_CONFIG_UCM2 != "") "PipeWire receives guest-owned UCM path")
  (assertContract (pipewire.environment.ALSA_CONFIG_UCM2 == "${cfg.rocknix.device.audio.ucmPackage}/share/alsa/ucm2") "PipeWire consumes the generic device UCM package")
  (assertContract (wireplumber.environment.ALSA_CONFIG_UCM2 == pipewire.environment.ALSA_CONFIG_UCM2) "WirePlumber uses same guest-owned UCM path")
  (assertContract (contains "c /dev/uinput 0600 root root - 10:223" cfg.systemd.tmpfiles.rules) "/dev/uinput tmpfiles rule exists")
  (assertContract cfg.services.inputplumber.enable "InputPlumber service is enabled")
  (assertContract (contains "main-space-sway-kiosk.service" (inputplumber.before or [ ])) "InputPlumber starts before fallback Sway")
  (assertContract (contains "korri-kiosk.service" (inputplumber.before or [ ])) "InputPlumber starts before downstream Korri kiosk")
  (assertContract (contains "inputplumber.service" (hideRaw.wants or [ ])) "raw gamepad hider wants InputPlumber")
  (assertContract (contains "inputplumber.service" (hideRaw.after or [ ])) "raw gamepad hider orders after InputPlumber")
  (assertContract (builtins.elem "AYN Odin2 Gamepad" cfg.rocknix.device.input.rawGamepadEventNames) "raw gamepad names live under the generic device seam")
  (assertContract (builtins.elem "Microsoft X-Box 360 pad" cfg.rocknix.device.input.virtualGamepadEventNames) "virtual gamepad names live under the generic device seam")

  # Neutral audio API capability — the value the product layer translates
  # into SDL_AUDIODRIVER / client-specific environment.
  (assertContract (cfg.rocknix.sm8550.audio.api == "pulseaudio") "SM8550 substrate exposes a PulseAudio-compatible audio API")

  # Thor's substrate-owned speaker route. Bootstrap service must exist,
  # order after the audio graph, and run before downstream kiosks so the
  # default sink is no longer `auto_null` by the time Korri/Moonlight launches.
  (assertContract (thorServices ? main-space-audio-sink-bootstrap) "Thor substrate exposes a default-sink bootstrap service")
  (assertContract (thorBootstrap.serviceConfig.Type == "oneshot") "Thor sink bootstrap is oneshot")
  (assertContract (thorBootstrap.serviceConfig.RemainAfterExit == true) "Thor sink bootstrap remains active after success")
  (assertContract (contains "main-space-pipewire.service" (thorBootstrap.after or [ ])) "Thor sink bootstrap orders after PipeWire")
  (assertContract (contains "main-space-pipewire-pulse.service" (thorBootstrap.after or [ ])) "Thor sink bootstrap orders after PipeWire Pulse")
  (assertContract (contains "main-space-wireplumber.service" (thorBootstrap.after or [ ])) "Thor sink bootstrap orders after WirePlumber")
  (assertContract (contains "main-space-sway-kiosk.service" (thorBootstrap.before or [ ])) "Thor sink bootstrap orders before fallback Sway kiosk")
  (assertContract (contains "korri-kiosk.service" (thorBootstrap.before or [ ])) "Thor sink bootstrap orders before downstream Korri kiosk")
  (assertContract (thorBootstrap.environment.XDG_RUNTIME_DIR == "/run/user/${toString thorCfg.rocknix.session.runtimeDir.uid}") "Thor sink bootstrap retains main-space XDG_RUNTIME_DIR")
  (assertContract (thorBootstrap.environment.PIPEWIRE_RUNTIME_DIR == thorBootstrap.environment.XDG_RUNTIME_DIR) "Thor sink bootstrap retains PIPEWIRE_RUNTIME_DIR")
  (assertContract (thorBootstrap.environment.PULSE_SERVER == "unix:${thorBootstrap.environment.XDG_RUNTIME_DIR}/pulse/native") "Thor sink bootstrap retains PULSE_SERVER")
  (assertContract (thorBootstrap.environment.ALSA_CONFIG_UCM2 != "") "Thor sink bootstrap retains UCM path")

  # Thor's measured speaker-route facts live in the device profile.
  (assertContract (thorCfg.rocknix.sm8550.audio.defaultSink.pcm == "hw:0,0") "Thor declares the validated speaker PCM")
  (assertContract (thorCfg.rocknix.sm8550.audio.defaultSink.name == "thor_speaker") "Thor declares a non-empty sink name")
  (assertContract (thorCfg.rocknix.sm8550.audio.defaultSink.ucmVerb == "HiFi") "Thor declares the speaker UCM verb")
  (assertContract (thorCfg.rocknix.sm8550.audio.defaultSink.ucmDevice == "Speaker") "Thor declares the speaker UCM device")

  # Odin 2 Portal must not silently inherit Thor's speaker PCM. The
  # bootstrap service is omitted until Odin's audio path is physically
  # validated; the contract proves the absence rather than relying on a
  # "happens to be null" coincidence.
  (assertContract (odinCfg.rocknix.sm8550.audio.defaultSink.pcm == null) "Odin 2 Portal leaves the default-sink PCM null until physically validated")
  (assertContract (!(odinCfg.systemd.services ? main-space-audio-sink-bootstrap)) "Odin 2 Portal does not auto-create a substrate-owned default sink")
]
