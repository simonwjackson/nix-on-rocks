# Initial Anbernic RG353M profile scaffold.
#
# This profile deliberately stays minimal until the physical device arrives and
# the probe protocol records model, compatible strings, display connector,
# input names, audio topology, and networking devices.
{ lib, ... }:

{
  networking.hostName = lib.mkForce "rg353m";

  rocknix.rk3566.deviceId = "rg353m";
}
