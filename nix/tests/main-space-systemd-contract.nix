{ pkgs, mainSpaceConfiguration, devEnvConfiguration }:

let
  helpers = import ./helpers.nix { inherit pkgs; };
  assertContract = helpers.assertContract "main-space systemd contract";
  cfg = mainSpaceConfiguration.config;
  devCfg = devEnvConfiguration.config;
  services = cfg.systemd.services;
  sway = services.main-space-sway-kiosk;
  sessionDbus = services.main-space-session-dbus;
  portal = services.main-space-portal-bootstrap;
  devSway = devCfg.systemd.services.main-space-sway-kiosk;
  contains = needle: haystack: builtins.elem needle haystack;
in
helpers.runAssertions "rocknix-main-space-systemd-contract" [
  (assertContract (services ? main-space-runtime-dir) "main-space runtime-dir anchor service exists")
  (assertContract (services ? main-space-session-dbus) "main-space session D-Bus service exists")
  (assertContract (services ? main-space-portal-bootstrap) "main-space portal bootstrap service exists")
  (assertContract (services ? main-space-sway-kiosk) "main-space fallback Sway service exists")
  (assertContract (contains "multi-user.target" (sway.wantedBy or [ ])) "Sway kiosk is wanted by multi-user.target")
  (assertContract (!(contains "multi-user.target" (sway.after or [ ]))) "Sway kiosk does not order after multi-user.target")
  (assertContract (contains "systemd-user-sessions.service" (sway.after or [ ])) "Sway kiosk orders after systemd-user-sessions")
  (assertContract (contains "main-space-runtime-dir.service" (sway.after or [ ])) "Sway kiosk orders after runtime-dir anchor")
  (assertContract (contains "main-space-session-dbus.service" (sway.after or [ ])) "Sway kiosk orders after session D-Bus")
  (assertContract (contains "main-space-runtime-dir.service" (sway.requires or [ ])) "Sway kiosk requires runtime-dir anchor")
  (assertContract (contains "main-space-session-dbus.service" (sway.requires or [ ])) "Sway kiosk requires session D-Bus")
  (assertContract (contains "main-space-sway-kiosk.service" (sessionDbus.before or [ ])) "Session D-Bus starts before Sway kiosk")
  (assertContract (contains "main-space-runtime-dir.service" (portal.after or [ ])) "Portal bootstrap orders after runtime-dir anchor")
  (assertContract (contains "main-space-session-dbus.service" (portal.after or [ ])) "Portal bootstrap orders after session D-Bus")
  (assertContract (contains "main-space-sway-kiosk.service" (portal.after or [ ])) "Portal bootstrap orders after fallback Sway")
  (assertContract (contains "korri-kiosk.service" (portal.after or [ ])) "Portal bootstrap can follow downstream Korri kiosk")
  (assertContract (portal.serviceConfig.Type == "oneshot") "Portal bootstrap is oneshot")
  (assertContract (sway.environment.XDG_CURRENT_DESKTOP == "sway") "Sway kiosk advertises sway desktop for portals")
  (assertContract (sway.environment.CEMU_BIOS_ROOT == "/storage/roms/bios/cemu") "Sway kiosk keeps Cemu BIOS compatibility root")
  (assertContract (sway.environment.CEMU_AFFINITY_MASK == cfg.rocknix.sm8550.performance.cemuAffinityMask) "Sway kiosk consumes SM8550 Cemu affinity default")
  (assertContract (!(contains "multi-user.target" (devSway.after or [ ]))) "dev-env Sway kiosk also avoids After=multi-user.target")
]
