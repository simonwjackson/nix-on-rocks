{ pkgs, baseConfiguration, devEnvConfiguration }:

let
  helpers = import ./helpers.nix { inherit pkgs; };
  assertContract = helpers.assertContract "audio/input systemd contract";
  cfg = baseConfiguration.config;
  devCfg = devEnvConfiguration.config;
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
  (assertContract (contains "systemd-udev-settle.service" (wireplumber.wants or [ ])) "WirePlumber pulls udev-settle into transaction")
  (assertContract (contains "systemd-udev-settle.service" (wireplumber.after or [ ])) "WirePlumber orders after udev-settle")
  (assertContract (contains "main-space-runtime-dir.service" (wireplumber.after or [ ])) "WirePlumber orders after runtime-dir anchor")
  (assertContract (pipewire.environment.XDG_RUNTIME_DIR == runtimeDir) "PipeWire runtime dir is parameterized")
  (assertContract (pipewire.environment.PIPEWIRE_RUNTIME_DIR == runtimeDir) "PipeWire runtime env is parameterized")
  (assertContract (pipewire.environment.PULSE_SERVER == "unix:${runtimeDir}/pulse/native") "PipeWire Pulse server path is parameterized")
  (assertContract (pipewire.environment.ALSA_CONFIG_UCM2 != "") "PipeWire receives guest-owned UCM path")
  (assertContract (wireplumber.environment.ALSA_CONFIG_UCM2 == pipewire.environment.ALSA_CONFIG_UCM2) "WirePlumber uses same guest-owned UCM path")
  (assertContract (contains "c /dev/uinput 0600 root root - 10:223" cfg.systemd.tmpfiles.rules) "/dev/uinput tmpfiles rule exists")
  (assertContract (contains "L /dev/inputplumber - - - - /dev/input/.inputplumber" cfg.systemd.tmpfiles.rules) "/dev/inputplumber symlink tmpfiles rule exists")
  (assertContract (contains "d /run/udev/rules.d 0755 root root -" cfg.systemd.tmpfiles.rules) "/run/udev/rules.d tmpfiles rule exists")
  (assertContract cfg.services.inputplumber.enable "InputPlumber service is enabled")
  (assertContract (inputplumber.environment.HIDE_DEVICES_FROM_ROOT or "" == "1") "InputPlumber hides raw devices from root")
  (assertContract (contains "systemd-udev-settle.service" (inputplumber.wants or [ ])) "InputPlumber pulls udev-settle")
  (assertContract (contains "systemd-udev-settle.service" (inputplumber.after or [ ])) "InputPlumber orders after udev-settle")
  (assertContract (contains "main-space-sway-kiosk.service" (inputplumber.before or [ ])) "InputPlumber starts before fallback Sway")
  (assertContract (contains "korri-kiosk.service" (inputplumber.before or [ ])) "InputPlumber starts before downstream Korri kiosk")
  (assertContract (contains "inputplumber.service" (hideRaw.wants or [ ])) "raw gamepad hider wants InputPlumber")
  (assertContract (contains "inputplumber.service" (hideRaw.after or [ ])) "raw gamepad hider orders after InputPlumber")
  (assertContract (contains "systemd-udev-settle.service" (devCfg.systemd.services.main-space-wireplumber.wants or [ ])) "dev-env WirePlumber keeps udev-settle ordering")
]
