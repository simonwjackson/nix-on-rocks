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
  uid = toString cfg.uid;
  runtimeDir = "/run/user/${uid}";
  sessionPortalBootstrap = pkgs.writeShellScript "rocknix-session-portal-bootstrap" ''
    set -u

    export XDG_RUNTIME_DIR=${runtimeDir}
    export DBUS_SESSION_BUS_ADDRESS=unix:path=${runtimeDir}/bus
    export XDG_CURRENT_DESKTOP="''${XDG_CURRENT_DESKTOP:-sway}"

    # Portals are activated by the root user D-Bus manager, not by the
    # compositor process. Wait for Sway to publish the session sockets, then
    # teach D-Bus activation how to start display-bound portal backends.
    for _ in $(${pkgs.coreutils}/bin/seq 1 150); do
      wayland_socket=$(${pkgs.findutils}/bin/find "$XDG_RUNTIME_DIR" -maxdepth 1 -type s -name 'wayland-*' | ${pkgs.coreutils}/bin/head -1 || true)
      sway_socket=$(${pkgs.findutils}/bin/find "$XDG_RUNTIME_DIR" -maxdepth 1 -type s -name 'sway-ipc.*.sock' | ${pkgs.coreutils}/bin/head -1 || true)
      if [ -n "$wayland_socket" ] && [ -n "$sway_socket" ]; then
        break
      fi
      ${pkgs.coreutils}/bin/sleep 0.2
    done

    if [ -z "''${WAYLAND_DISPLAY:-}" ] && [ -n "''${wayland_socket:-}" ]; then
      WAYLAND_DISPLAY="$(${pkgs.coreutils}/bin/basename "$wayland_socket")"
      export WAYLAND_DISPLAY
    fi
    if [ -z "''${SWAYSOCK:-}" ] && [ -n "''${sway_socket:-}" ]; then
      export SWAYSOCK="$sway_socket"
    fi

    if [ -z "''${WAYLAND_DISPLAY:-}" ] || [ -z "''${SWAYSOCK:-}" ]; then
      echo "Sway session sockets are not ready; skipping portal bootstrap" >&2
      exit 0
    fi

    ${pkgs.dbus}/bin/dbus-update-activation-environment --systemd \
      XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS WAYLAND_DISPLAY SWAYSOCK XDG_CURRENT_DESKTOP \
      >/dev/null 2>&1 || true

    ${pkgs.coreutils}/bin/timeout 3s ${pkgs.systemd}/bin/systemctl --user reset-failed \
      xdg-desktop-portal.service xdg-desktop-portal-gtk.service xdg-document-portal.service \
      >/dev/null 2>&1 || true
    ${pkgs.coreutils}/bin/timeout 5s ${pkgs.systemd}/bin/systemctl --user start \
      xdg-desktop-portal.service \
      >/dev/null 2>&1 || true
  '';
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
      ExecStart = "${pkgs.dbus}/bin/dbus-daemon --session --address=unix:path=${runtimeDir}/bus --nofork --nopidfile";
      Restart = "on-failure";
      RestartSec = 3;
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };

  # Product-owned Sway services inherit their environment from their systemd
  # units, but D-Bus-activated portal backends inherit from the root user
  # manager. If the manager never learns WAYLAND_DISPLAY/SWAYSOCK, Settings
  # portal activation falls through to gtk.portal with no display and clients
  # such as Gamescope block behind D-Bus timeouts. Bootstrap the activation
  # environment at the substrate layer so downstream kiosks do not need their
  # own gamescope-specific portal workaround.
  systemd.services.main-space-portal-bootstrap = {
    description = "Main-space session portal activation bootstrap";
    wantedBy = [ "multi-user.target" ];
    after = [
      "main-space-runtime-dir.service"
      "main-space-session-dbus.service"
      "main-space-sway-kiosk.service"
      "korri-kiosk.service"
    ];
    requires = [ "main-space-runtime-dir.service" "main-space-session-dbus.service" ];
    partOf = [ "main-space-sway-kiosk.service" "korri-kiosk.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStart = sessionPortalBootstrap;
      RemainAfterExit = true;
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };
}
