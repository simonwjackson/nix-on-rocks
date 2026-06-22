{ pkgs, baseConfiguration, devEnvConfiguration }:

let
  assertContract = condition: message:
    if condition then message else builtins.throw "guest input boundary contract failed: ${message}";
  cfg = baseConfiguration.config;
  devCfg = devEnvConfiguration.config;
  inputplumber = cfg.systemd.services.inputplumber;
  wireplumber = cfg.systemd.services.main-space-wireplumber;
  soundHydrate = cfg.systemd.services.rocknix-sound-card-udev-hydrate;
  devWireplumber = devCfg.systemd.services.main-space-wireplumber;
  udevModuleSource = builtins.readFile ../../guest/modules/udev.nix;
  hasInfix = pkgs.lib.hasInfix;
  contract = builtins.toFile "guest-input-boundary-contract.json" (builtins.toJSON [
    (assertContract cfg.services.udev.enable "services.udev.enable")
    (assertContract (builtins.elem "systemd-udev-trigger.service" cfg.systemd.additionalUpstreamSystemUnits) "udev-trigger upstream unit restored")
    (assertContract cfg.systemd.services.systemd-udevd.enable "systemd-udevd enabled")
    (assertContract cfg.systemd.services.systemd-udev-trigger.enable "systemd-udev-trigger enabled")
    (assertContract cfg.systemd.services.systemd-udev-settle.enable "systemd-udev-settle enabled")
    (assertContract (builtins.length cfg.services.udev.packages > 0) "InputPlumber udev package installed")
    (assertContract (inputplumber.environment.HIDE_DEVICES_FROM_ROOT or "" == "1") "InputPlumber hides from root")
    (assertContract (builtins.elem "systemd-udev-settle.service" (inputplumber.after or [ ])) "InputPlumber orders after udev-settle")
    (assertContract (builtins.elem "L /dev/inputplumber - - - - /dev/input/.inputplumber" cfg.systemd.tmpfiles.rules) "/dev/inputplumber symlink tmpfiles rule")
    (assertContract (builtins.elem "d /run/udev/rules.d 0755 root root -" cfg.systemd.tmpfiles.rules) "/run/udev/rules.d tmpfiles rule")
    (assertContract (cfg.systemd.services ? rocknix-sound-card-udev-hydrate) "generic sound-card udev hydration service exists")
    (assertContract (builtins.elem "systemd-udev-settle.service" (soundHydrate.after or [ ])) "sound-card hydration orders after udev-settle")
    (assertContract (builtins.elem "main-space-wireplumber.service" (soundHydrate.before or [ ])) "sound-card hydration orders before WirePlumber")
    (assertContract (hasInfix "/run/udev/data/+sound:$card" udevModuleSource) "sound-card hydration writes card-level udev records")
    (assertContract (hasInfix "E:SOUND_INITIALIZED=1" udevModuleSource) "sound-card hydration marks cards initialized")
    (assertContract (hasInfix "E:ID_PATH=%s" udevModuleSource) "sound-card hydration records path identity")
    (assertContract (hasInfix "E:ID_PATH_TAG=%s" udevModuleSource) "sound-card hydration records path tags")
    (assertContract (hasInfix "udevadm test-builtin path_id" udevModuleSource) "sound-card hydration derives path identity with udev path_id")
    (assertContract (hasInfix "failed to install $data_file" udevModuleSource) "sound-card hydration fails on record install failure")
    (assertContract (builtins.elem "systemd-udev-settle.service" (wireplumber.wants or [ ])) "WirePlumber pulls in udev-settle")
    (assertContract (builtins.elem "systemd-udev-settle.service" (wireplumber.after or [ ])) "WirePlumber orders after udev-settle")
    (assertContract (builtins.elem "rocknix-sound-card-udev-hydrate.service" (wireplumber.after or [ ])) "WirePlumber orders after sound-card hydration")
    (assertContract (builtins.elem "systemd-udev-settle.service" (devWireplumber.wants or [ ])) "dev-env WirePlumber pulls in udev-settle")
  ]);
in
pkgs.runCommand "rocknix-guest-input-boundary-contract"
  { }
  ''
    cat ${contract} >/dev/null
    touch $out
  ''
