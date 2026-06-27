# R36T Max profile scaffold.
#
# SD-card ROCKNIX proof verified RK3326 boot, RK915 Wi-Fi, and SSH on the
# physical R36T Max. Guest display/input/audio policy is intentionally
# minimal until hardware acceptance captures those device facts.
{ lib, ... }:

{
  networking.hostName = lib.mkForce "r36tmax";

  rocknix.rk3326.deviceId = "r36tmax";
}
