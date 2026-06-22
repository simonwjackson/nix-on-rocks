# Hardware-validated AYN Thor profile.
{ lib, ... }:

{
  networking.hostName = lib.mkForce "bandai";

  rocknix.sm8550.deviceId = "thor";

  # Live-validated AYN Thor speaker route. Guest udev hydration lets
  # WirePlumber discover the platform sound card and create the UCM-owned
  # speaker sink, so the substrate selects the graph sink instead of loading
  # a direct module-alsa-sink PCM.
  rocknix.device.audio.route = {
    kind = "wireplumber-ucm";
    expectedSink = "alsa_output.platform-sound.HiFi__Speaker__sink";
    pcm = null;
    sinkName = null;
    description = "AYN Thor built-in speakers";
    ucmVerb = "HiFi";
    ucmDevice = "Speaker";
  };
}
