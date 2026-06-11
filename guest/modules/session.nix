# Main-space session runtime-dir ownership.
#
# /run/user/<uid> is owned by NixOS logind's user-runtime-dir@<uid>
# service template, which mounts a tmpfs at that path early in boot.
# Without explicit ordering, substrate services that create sockets
# under /run/user/<uid> race against the tmpfs mount: the sockets
# land in the pre-mount plain directory, then the tmpfs masks them
# one second later. The processes stay alive bound to orphaned
# inodes, but every caller that opens the socket by path fails with
# ENOENT until something restarts the service inside the mounted
# tmpfs.
#
# `main-space-runtime-dir.service` is a thin oneshot anchor that
# orders After=/Requires= the per-uid logind unit. Every main-space
# consumer (session D-Bus, PipeWire, PipeWire-Pulse, WirePlumber,
# sway kiosk in both main-space and dev-env profiles) orders After=
# this anchor so its sockets land inside the already-mounted tmpfs
# and persist for the lifetime of the session.
#
# The option `rocknix.session.runtimeDir.uid` parameterizes the
# whole substrate on a single UID value (default 0). A downstream
# product that runs the kiosk as a non-root user changes only this
# option -- the anchor's After=, the consumer ordering, and the env
# triplets in audio.nix/main-space.nix/dev-env.nix all
# derive their /run/user/<uid> path from it.
#
# This module is imported by both rocknix-guest-base.nix (the
# substrate contract downstream products consume) and dev-env.nix (the
# substrate-local fallback profile that does not go through
# rocknix-guest-base), so the option and anchor are visible to
# every profile that exercises the main-space session topology.
#
# Diagnosis evidence:
#   docs/thinking/SM8550/2026-05-24-main-space-runtime-dir-wipe-trace.md
# Plan:
#   docs/plans/2026-05-24-001-fix-main-space-pipewire-runtime-dir-plan.md
{ config
, lib
, pkgs
, ...
}:

let
  cfg = config.rocknix.session.runtimeDir;
in
{
  options.rocknix.session.runtimeDir = {
    uid = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 0;
      example = 1000;
      description = ''
        UID whose /run/user/<uid> tmpfs is the substrate session
        runtime directory. Defaults to 0 (root) for the kiosk-as-root
        deployment shape. A downstream product that runs the kiosk as
        a non-root user changes only this value; the anchor service,
        consumer ordering, and env triplets all derive their
        /run/user/<uid> path from this option.
      '';
    };
  };

  config = {
    systemd.services.main-space-runtime-dir = {
      description = "Main-space session runtime-dir anchor (orders after logind user-runtime-dir@${toString cfg.uid})";
      wantedBy = [ "multi-user.target" ];
      after = [ "user-runtime-dir@${toString cfg.uid}.service" ];
      requires = [ "user-runtime-dir@${toString cfg.uid}.service" ];
      # Substrate consumers only. Downstream product session units order
      # themselves After=/Requires= this anchor from their side; the
      # substrate does not know product unit names.
      before = [
        "main-space-session-dbus.service"
        "main-space-pipewire.service"
        "main-space-pipewire-pulse.service"
        "main-space-wireplumber.service"
        "main-space-sway-kiosk.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # logind has already created /run/user/<uid> inside its tmpfs;
        # this anchor exists only to give consumers a named unit to
        # depend on. Verify the directory is present and walk away.
        ExecStart = "${pkgs.coreutils}/bin/test -d /run/user/${toString cfg.uid}";
      };
    };
  };
}
