# Generic device contract consumed by guest substrate modules.
#
# Chipset modules bridge their measured defaults into this interface with
# mkDefault/mkForce. Product layers consume the resulting neutral surface rather
# than chipset-private option paths.
{ lib, ... }:

let
  inherit (lib) mkOption types;
in
{
  options.rocknix.device = {
    id = mkOption {
      type = types.str;
      description = "Device variant selected for the guest profile.";
    };

    display.swayDeviceConfig = mkOption {
      type = types.lines;
      description = "Device-specific sway output and touch-routing block.";
    };

    input = {
      powerEventNames = mkOption {
        type = types.listOf types.str;
        description = "Kernel input device names that may emit KEY_POWER.";
      };

      volumeDownEventNames = mkOption {
        type = types.listOf types.str;
        description = "Kernel input device names that may emit KEY_VOLUMEDOWN.";
      };

      volumeUpLidEventNames = mkOption {
        type = types.listOf types.str;
        description = "Kernel input device names that may emit KEY_VOLUMEUP and/or SW_LID.";
      };

      rawGamepadEventNames = mkOption {
        type = types.listOf types.str;
        description = "Raw gamepad event device names hidden after the input daemon claims them.";
      };

      virtualGamepadEventNames = mkOption {
        type = types.listOf types.str;
        description = "Virtual gamepad event device names that prove the input daemon is ready.";
      };
    };

    audio = {
      ucmPackage = mkOption {
        type = types.package;
        description = "ALSA UCM package used by the guest-owned audio stack.";
      };

      api = mkOption {
        type = types.enum [ "pulseaudio" ];
        description = "Neutral audio API the device exposes to user-space.";
      };

      card = mkOption {
        type = types.str;
        description = "Kernel ALSA card id used for PCM/device addressing.";
      };

      ucmCard = mkOption {
        type = types.str;
        description = "ALSA UCM configuration id used with `alsaucm -c`. This may differ from the kernel card id.";
      };

      route = {
        kind = mkOption {
          type = types.enum [ "none" "wireplumber-ucm" "manual-pcm" ];
          default = "none";
          description = ''
            Declared default-route strategy. `wireplumber-ucm` waits for a
            graph-created WirePlumber sink; `manual-pcm` creates a PulseAudio
            ALSA sink for the declared PCM; `none` means no validated default
            route is available.
          '';
        };

        expectedSink = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Graph-created sink name expected for wireplumber-ucm routes.";
        };

        pcm = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "ALSA PCM used for manual-pcm routes.";
        };

        sinkName = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "PulseAudio sink name to create for manual-pcm routes.";
        };

        description = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Human-readable sink description for manual-pcm routes.";
        };

        ucmVerb = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Optional UCM verb to activate before selecting/loading the route.";
        };

        ucmDevice = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Optional UCM device to enable after the verb is set.";
        };
      };

      # Backward-compatible route fields retained for consumers that have not
      # yet moved to rocknix.device.audio.route.*. New shipped profiles should
      # set the explicit route strategy as the source of truth.
      defaultSink = {
        pcm = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Legacy ALSA PCM backing the default PulseAudio sink.";
        };

        name = mkOption {
          type = types.str;
          default = "main_speaker";
          description = "Legacy PulseAudio sink name created when defaultSink.pcm is set.";
        };

        description = mkOption {
          type = types.str;
          default = "Main speaker";
          description = "Legacy human-readable description applied to the bootstrapped sink.";
        };

        ucmVerb = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Legacy UCM verb to activate before loading the PCM sink.";
        };

        ucmDevice = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Legacy UCM device to enable after the verb is set.";
        };
      };
    };

    performance.cemuAffinityMask = mkOption {
      type = types.str;
      description = "Default Cemu CPU affinity mask for this device.";
    };
  };
}
