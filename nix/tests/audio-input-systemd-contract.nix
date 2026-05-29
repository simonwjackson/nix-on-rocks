{ pkgs, baseConfiguration, devEnvConfiguration }:

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
  (assertContract (wireplumber.environment.ALSA_CONFIG_UCM2 == pipewire.environment.ALSA_CONFIG_UCM2) "WirePlumber uses same guest-owned UCM path")
  (assertContract (contains "c /dev/uinput 0600 root root - 10:223" cfg.systemd.tmpfiles.rules) "/dev/uinput tmpfiles rule exists")
  (assertContract cfg.services.inputplumber.enable "InputPlumber service is enabled")
  (assertContract (contains "main-space-sway-kiosk.service" (inputplumber.before or [ ])) "InputPlumber starts before fallback Sway")
  (assertContract (contains "korri-kiosk.service" (inputplumber.before or [ ])) "InputPlumber starts before downstream Korri kiosk")
  (assertContract (contains "inputplumber.service" (hideRaw.wants or [ ])) "raw gamepad hider wants InputPlumber")
  (assertContract (contains "inputplumber.service" (hideRaw.after or [ ])) "raw gamepad hider orders after InputPlumber")
]
