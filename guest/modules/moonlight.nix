# Layer 14 moonlight-embedded module.
#
# Wires the moonlight-embedded CLI client into the SM8550 main-space guest:
# installs the binary, declares the persistent keydir under /storage, and
# exposes the launcher script. Stays narrow on purpose — Sunshine pairing,
# host selection, and portal demote/restore policy live in the launcher and
# the kiosk session, not here.
#
# ---------------------------------------------------------------------------
# Refactor staging note (2026-05-22)
#
# This module is currently inert: no profile in guest/profiles/ imports it.
# It is staged at the post-refactor target path called out by
# docs/plans/2026-05-22-001-refactor-monorepo-merge-layered-restructure-plan.md
# (U9), so when the monorepo merge collapses guest/flake.nix into a
# top-level flake the wiring step is just a profile import and a default
# override on the `package` option below.
#
# Today `rocknix.sm8550.moonlight.package` defaults to `pkgs.moonlight-embedded`
# from nixpkgs — the upstream binary, software-decode-only, no v4l2m2m HW
# decode. Once the refactor exposes `packages.moonlight-embedded` from the
# top-level flake (carrying the SM8550 patch stack defined in
# packages/moonlight-embedded/manifest.nix + patches/), the main-space
# profile should override the default with that patched derivation.
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
        nixpkgs build (software decode only). Override with the SM8550
        zero-copy v4l2m2m derivation from packages/moonlight-embedded/ once
        the monorepo merge restructure exposes it as a flake package
        (see docs/plans/2026-05-22-002-feat-moonlight-embedded-v4l2m2m-zero-copy-plan.md).
      '';
    };

    keydir = mkOption {
      type = types.str;
      default = "/storage/.cache/moonlight";
      description = ''
        Directory where moonlight-embedded persists its client keys and
        per-host pair certificates. Lives on /storage so it survives rootfs
        swaps (the same property /storage gives to Cemu saves and Steam).
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
