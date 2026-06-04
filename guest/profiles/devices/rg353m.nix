# Initial Anbernic RG353M profile scaffold.
#
# Physical Android ADB evidence captured on 2026-06-04 exposed the generic
# `rockchip,rk3566-rk817-tablet` compatible string for the RG353M support lane.
# This profile deliberately stays minimal until ROCKNIX SD-boot evidence records
# final Linux connector names, mixer routes, input mapping, and networking state.
{ lib, ... }:

{
  networking.hostName = lib.mkForce "rg353m";

  rocknix.rk3566.deviceId = "rg353m";
}
