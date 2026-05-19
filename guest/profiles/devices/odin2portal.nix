# Initial AYN Odin 2 Portal profile.
#
# Odin 2 Portal is an SM8550-family target. The first measured difference from
# Thor is display topology/orientation: Portal exposes one 1080x1920 DSI panel
# as DSI-1, and the Thor transform=90 default renders upside down. Use
# transform=270 to present the panel in handheld landscape orientation.
{ lib, ... }:

{
  networking.hostName = lib.mkForce "sobo";

  rocknix.sm8550 = {
    deviceId = "odin2portal";

    display.swayDeviceConfig = ''
      # ROCKNIX Layer 14 sway device block (Odin 2 Portal, SM8550).
      # Live-adjusted on Odin 2 Portal 2026-05-12: DSI-1 is the only
      # active 1080x1920 panel and needs transform 270 instead of Thor's 90.
      output DSI-1 enable
      output DSI-1 transform 270
      output DSI-1 scale 2.0
      output DSI-1 pos 0 0
      output DSI-1 bg #000000 solid_color
      output DSI-1 allow_tearing yes
      output DSI-1 max_render_time off

      # Portal currently exposes a single touchscreen; keep the routing broad
      # until its kernel name is made stable.
      input type:touch map_to_output DSI-1
    '';
  };
}
