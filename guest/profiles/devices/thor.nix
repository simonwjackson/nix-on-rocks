# Hardware-validated AYN Thor profile.
{ lib, ... }:

{
  networking.hostName = lib.mkForce "bandai";

  rocknix.sm8550 = {
    deviceId = "thor";

    # Live-validated AYN Thor speaker route. The kernel exposes the
    # built-in audio card as `AYNOdin2` with the speaker PCM at
    # `hw:0,0`; activating the HiFi/Speaker UCM pair plus loading a
    # PulseAudio ALSA sink against that PCM makes audible audio reach
    # the device speakers (validated on bandai 2026-05-29 with
    # Neverball/Moonlight stream tones replacing `Dummy Output`).
    audio.defaultSink = {
      pcm = "hw:0,0";
      name = "thor_speaker";
      description = "AYN Thor built-in speakers";
      ucmVerb = "HiFi";
      ucmDevice = "Speaker";
    };
  };
}
