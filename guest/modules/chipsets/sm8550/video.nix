# SM8550 video decode capability.
#
# Declares the Linux video-decode backend that the SM8550 substrate exposes
# to user-space. The current shared value is `v4l2m2m`, backed by the Iris
# V4L2 mem2mem decoder in the SM8550 kernel; Thor and Odin 2 Portal both
# inherit it because they share the same SoC video pipeline.
#
# This is intentionally a *substrate* capability, not a Moonlight option.
# Product/appliance layers translate it into the CLI shape required by the
# client they actually launch (e.g. Moonlight Embedded's `-platform v4l2m2m`).
# Keeping the value here means downstream product code does not need to know
# RockNix/Moonlight option paths to discover what hardware decode the SoC
# supports, and per-device profiles can override it without touching the
# product layer when a future SM8550 device ships with a different kernel
# video backend.
{ lib, ... }:

let
  inherit (lib) mkOption types;
in
{
  options.rocknix.sm8550.video = {
    decodeBackend = mkOption {
      type = types.enum [ "v4l2m2m" "sdl" ];
      default = "v4l2m2m";
      description = ''
        Linux video decode backend exposed by the SM8550 substrate. `v4l2m2m`
        is the hardware-accelerated Iris V4L2 mem2mem path validated on Thor
        and Odin 2 Portal. `sdl` is the software-decode fallback retained for
        debugging and devices where the kernel video path is unavailable.

        Per-device profiles may override this value when a specific SM8550
        target ships without a working V4L2 mem2mem decoder.
      '';
    };
  };
}
