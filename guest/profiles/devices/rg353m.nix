# Initial Anbernic RG353M profile scaffold.
#
# Physical Android ADB evidence captured on 2026-06-04 exposed the generic
# `rockchip,rk3566-rk817-tablet` compatible string for one RG353M boot path.
# Official ROCKNIX SD-boot evidence captured later the same day exposed model
# `Anbernic RG353M`, ambiguous compatible `anbernic,rg353p`, DSI-1 640x480
# display, RK817 audio card names, Realtek WiFi/Bluetooth, and core input names.
# This profile still leaves mixer routing, full input policy, and performance
# tuning to their dedicated follow-up tasks.
{ lib, ... }:

{
  networking.hostName = lib.mkForce "rg353m";

  rocknix.rk3566.deviceId = "rg353m";
}
