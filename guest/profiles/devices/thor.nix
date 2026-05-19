# Hardware-validated AYN Thor profile.
{ lib, ... }:

{
  networking.hostName = lib.mkForce "bandai";

  rocknix.sm8550.deviceId = "thor";
}
