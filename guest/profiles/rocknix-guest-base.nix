# Product-blind SM8550 guest substrate contract.
#
# Downstream appliance flakes import this profile to get the ROCKNIX/Nix-on-Rocks
# guest substrate: container baseline, SM8550 device facts, session plumbing,
# display/audio/input/network/lid modules, Steam runtime plumbing, and app
# package helpers. Product composition (Korri client/server/kiosk selection,
# Home-chord app launch policy, rootfs authority) lives downstream.
{ config
, pkgs
, ...
}:

let
  cfg = config.rocknix.session.runtimeDir;
in
{
  imports = [
    ../modules/base.nix
    ../modules/device.nix
    ../modules/tools.nix
    ../modules/ssh.nix
    ../modules/display.nix
    ../modules/audio.nix
    ../modules/input.nix
    ../modules/network.nix
    ../modules/lid.nix
    ../modules/steam.nix
    ../modules/moonlight.nix
    ../modules/session.nix
  ];

  # Layer 14 default hostname: distinguish from the Layer 10b minimal
  # "rocknix-guest" while allowing device profiles to provide stable
  # per-device names for SSH, Tailscale, and journals.
  networking.hostName = "rocknix-nix";

  # Tier E2 surfaced tz-data.service 203/EXEC on every switch because
  # ROCKNIX's tz-data unit ExecStart=/bin/ln -sf /usr/share/zoneinfo/${TIMEZONE}
  # and the variable was empty. Setting time.timeZone declaratively here
  # avoids the noise (NixOS owns its own zoneinfo path).
  time.timeZone = "America/New_York";

  # Stop the rate-limited journal-flush noise that fires when the guest's
  # /run is tmpfs and journald can't pre-allocate.
  services.journald.extraConfig = ''
    Storage=volatile
    RuntimeMaxUse=64M
  '';

  # Stable root session bus for whichever compositor owner the downstream
  # appliance chooses. The After=/Requires=main-space-runtime-dir.service
  # ordering ensures logind's per-uid tmpfs mount has happened before the
  # bus socket is written. See ../modules/session.nix for the substrate-
  # owned runtime-dir anchor and the rocknix.session.runtimeDir.uid option.
  # Runtime service-name references support both the legacy main-space
  # fallback compositor and the Korri-owned kiosk compositor without
  # importing or configuring Korri product modules here.
  systemd.services.main-space-session-dbus = {
    description = "Main-space root session D-Bus";
    wantedBy = [ "multi-user.target" ];
    after = [ "main-space-runtime-dir.service" ];
    requires = [ "main-space-runtime-dir.service" ];
    before = [
      "main-space-sway-kiosk.service"
      "korri-kiosk.service"
    ];
    serviceConfig = {
      Type = "simple";
      User = "root";
      ExecStart = "${pkgs.dbus}/bin/dbus-daemon --session --address=unix:path=/run/user/${toString cfg.uid}/bus --nofork --nopidfile";
      Restart = "on-failure";
      RestartSec = 3;
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };
}
