# Layer 14 moonlight-embedded module.
#
# Wires the moonlight-embedded CLI client into the SM8550 main-space guest:
# installs the binary, declares the persistent keydir under /storage, and
# exposes the package option for profile-level override. Stays narrow on
# purpose — Sunshine pairing, host selection, and portal demote/restore
# policy live in the launcher and the kiosk session, not here.
#
# ---------------------------------------------------------------------------
# Wired into main-space (2026-05-23)
#
# guest/profiles/main-space.nix imports this module. flake.nix's
# mainSpaceConfigurationFor sets rocknix.sm8550.moonlight.enable = true
# and overrides the package with packages.moonlight-embedded from this
# flake (the SM8550 v4l2m2m + SDL NV12 build defined in
# packages/moonlight-embedded/manifest.nix + patches/).
#
# The `enable` option defaults to `false` so the module remains importable
# from non-main-space profiles (dev-env, minimal) without auto-installing
# the client. The `package` option defaults to `pkgs.moonlight-embedded`
# from nixpkgs (upstream, software-decode-only) for the same reason; the
# main-space profile overrides it explicitly.
# ---------------------------------------------------------------------------
{ config, lib, pkgs, ... }:

let
  inherit (lib) mkOption types;
  cfg = config.rocknix.sm8550.moonlight;
in
{
  options.rocknix.sm8550.moonlight = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Install the moonlight-embedded CLI client and stage its persistent
        keydir on /storage. Disabled by default so the module can be staged
        in-tree without affecting unrelated guest profiles.
      '';
    };

    package = mkOption {
      type = types.package;
      default = pkgs.moonlight-embedded;
      defaultText = lib.literalExpression "pkgs.moonlight-embedded";
      description = ''
        moonlight-embedded derivation to install. Defaults to the upstream
        nixpkgs build (software decode only). The main-space profile
        overrides this with the in-repo SM8550 v4l2m2m + SDL NV12 build
        from packages/moonlight-embedded/.
      '';
    };

    keydir = mkOption {
      type = types.str;
      default = "/storage/.cache/moonlight";
      description = ''
        Directory where moonlight-embedded persists its client keys and
        per-host pair certificates. Lives on /storage so it survives rootfs
        swaps (the same property /storage gives to Cemu saves).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    # Persistent keydir on /storage — must exist before the first pair or
    # stream attempt or moonlight-embedded writes to a transient location and
    # subsequent runs fail to recognize the host.
    systemd.tmpfiles.rules = [
      "d ${cfg.keydir} 0700 root root - -"
    ];
  };
}
