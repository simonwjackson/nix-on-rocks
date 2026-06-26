# Hardware-validated AYN Thor profile.
{ lib, ... }:

{
  networking.hostName = lib.mkForce "bandai";

  rocknix.sm8550.deviceId = "thor";

  # Live-validated AYN Thor speaker facts. Keep the kernel/UCM card names in
  # the substrate device profile so product layers can use the neutral route
  # contract below without knowing Thor-vs-Odin naming details.
  rocknix.device.audio = {
    card = "AYNThor";
    ucmCard = "AYN-Thor";

    # Guest udev hydration lets WirePlumber discover the platform sound card
    # and create the UCM-owned speaker sink, so the substrate selects the graph
    # sink instead of loading a direct module-alsa-sink PCM.
    route = {
      kind = "wireplumber-ucm";
      expectedSink = "alsa_output.platform-sound.HiFi__Speaker__sink";
      pcm = null;
      sinkName = null;
      description = "Built-in speakers";
      ucmVerb = "HiFi";
      ucmDevice = "Speaker";
    };
  };
}
