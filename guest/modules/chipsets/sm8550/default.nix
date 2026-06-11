# Collapsed SM8550 chipset substrate.
#
# This module is the single import surface for SM8550 chipset facts. It owns:
#
#   - chipsets/sm8550/default.nix : shared chipset/device options, form-factor
#                                    overrides, and main-space audio/video imports.
#   - chipsets/sm8550/audio.nix   : PipeWire/PulseAudio/WirePlumber substrate
#                                    + neutral audio API capability.
#   - chipsets/sm8550/video.nix   : neutral SM8550 video decode capability.
#
# The default remains the hardware-validated Thor behavior. Additional
# devices (Odin 2 Portal, etc.) should override only the measured differences:
# display layout, input event names, audio UCM package/card/sink names, and
# performance policy. Substrate modules consume these options instead of
# hardcoding Thor assumptions inline. The product/appliance layer reads the
# neutral video/audio capabilities to compose its launch environment without
# learning RockNix-specific option paths.
{ config, lib, pkgs, ... }:

let
  inherit (lib) mkDefault mkOption types;
  aynOdin2Ucm = pkgs.callPackage ../../../../devices/sm8550/audio/ayn-odin2-ucm { };
in
{
  imports = [
    ./audio.nix
    ./video.nix
  ];

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
        description = "ALSA card name used for optional UCM activation.";
      };

      defaultSink = {
        pcm = mkOption {
          type = types.nullOr types.str;
          description = "ALSA PCM backing the substrate-bootstrapped default PulseAudio sink.";
        };

        name = mkOption {
          type = types.str;
          description = "PulseAudio sink name created when defaultSink.pcm is set.";
        };

        description = mkOption {
          type = types.str;
          description = "Human-readable description applied to the bootstrapped sink.";
        };

        ucmVerb = mkOption {
          type = types.nullOr types.str;
          description = "Optional UCM verb to activate before loading the sink.";
        };

        ucmDevice = mkOption {
          type = types.nullOr types.str;
          description = "Optional UCM device to enable after the verb is set.";
        };
      };
    };

    performance.cemuAffinityMask = mkOption {
      type = types.str;
      description = "Default Cemu CPU affinity mask for this device.";
    };
  };

  options.rocknix.sm8550 = {
    deviceId = mkOption {
      type = types.enum [ "thor" "odin2portal" ];
      default = "thor";
      description = "SM8550 handheld variant targeted by this guest profile.";
    };

    display.swayDeviceConfig = mkOption {
      type = types.lines;
      default = ''
        # ROCKNIX Layer 14 sway device block (Thor, SM8550).
        # Validated on Thor 2026-05-08: foot terminal renders readably in
        # landscape orientation on DSI-2 with this transform.
        output DSI-2 transform 90
        output DSI-2 pos 0 0
        output DSI-2 bg #000000 solid_color
        output DSI-2 allow_tearing yes
        output DSI-2 max_render_time off

        # Thor's bottom panel: 1080x1240 native, same physical orientation
        # as DSI-2 (panel is portrait, device is held landscape). Leave Sway
        # at its default scale and stack the bottom panel below DSI-2's
        # 1920x1080 logical surface.
        output DSI-1 enable
        output DSI-1 transform 90
        output DSI-1 pos 0 1080
        output DSI-1 bg #000000 solid_color

        # Touch routing for Thor's dual-screen design.
        #
        # Default: pin all touch sources to the active (top) panel. This
        # is the safe behaviour on kernels that don't yet name the two
        # ft5x06 controllers distinctly -- without it, bottom-panel taps
        # would either be dropped or land on the wrong surface because
        # both controllers report identical libinput identifiers
        # (vendor:product:name = 0:0:generic_ft5x06_(8d)).
        input type:touch map_to_output DSI-2

        # After-patch identifiers (see SM8550 kernel patch
        # 0054-edt-ft5x06-honour-DT-input-name.patch and DT input-name
        # properties on the touchscreen@38 nodes in qcs8550-ayn-thor.dts):
        # the two controllers expose distinct names that sway can address
        # individually, and these per-device rules override the type:touch
        # default above (last-write-wins on map_to_output). On older
        # kernels both rules are no-ops because no input matches them.
        input "0:0:ft5x06-top"    map_to_output DSI-2
        input "0:0:ft5x06-bottom" map_to_output DSI-1

        # The panels are physically portrait and displayed with transform 90.
        # Rotate touch coordinates the same way or taps land offset/rotated from
        # the rendered surface. Validated live on Thor 2026-05-11.
        input "0:0:ft5x06-top"    calibration_matrix 0 -1 1 1 0 0
        input "0:0:ft5x06-bottom" calibration_matrix 0 -1 1 1 0 0
      '';
      description = "Device-specific sway output and touch-routing block.";
    };

    input = {
      powerEventNames = mkOption {
        type = types.listOf types.str;
        default = [ "pmic_pwrkey" ];
        description = "Kernel input device names that may emit KEY_POWER.";
      };

      volumeDownEventNames = mkOption {
        type = types.listOf types.str;
        default = [ "pmic_resin" ];
        description = "Kernel input device names that may emit KEY_VOLUMEDOWN.";
      };

      volumeUpLidEventNames = mkOption {
        type = types.listOf types.str;
        default = [ "gpio-keys" ];
        description = "Kernel input device names that may emit KEY_VOLUMEUP and/or SW_LID.";
      };

      rawGamepadEventNames = mkOption {
        type = types.listOf types.str;
        default = [ "AYN Odin2 Gamepad" ];
        description = "Raw SM8550 gamepad event device names hidden after InputPlumber claims them.";
      };

      virtualGamepadEventNames = mkOption {
        type = types.listOf types.str;
        default = [
          # Live Thor/Bandai and RK3566 evidence: InputPlumber v0.75.2's
          # xbox-series target exposes this name. Keep the older Xbox 360
          # spelling as a compatibility fallback for older maps/targets.
          "Microsoft Xbox Series S|X Controller"
          "Microsoft X-Box 360 pad"
        ];
        description = "Virtual gamepad event device names that prove InputPlumber is ready.";
      };
    };

    audio = {
      ucmPackage = mkOption {
        type = types.package;
        default = aynOdin2Ucm;
        description = "ALSA UCM package used by the guest-owned audio stack.";
      };

      api = mkOption {
        type = types.enum [ "pulseaudio" ];
        default = "pulseaudio";
        description = ''
          Neutral audio API the SM8550 substrate exposes to user-space.
          Product layers translate this into client-specific environment
          (e.g. `SDL_AUDIODRIVER=pulseaudio`); the substrate itself only
          guarantees that a PulseAudio-compatible socket is reachable
          via `$PULSE_SERVER` because the main-space audio graph runs
          PipeWire's PulseAudio compatibility module.
        '';
      };

      card = mkOption {
        type = types.str;
        default = "AYNOdin2";
        description = ''
          ALSA card name used to drive UCM verbs and the default sink
          bootstrap. The SM8550 chipset ships with the AYNOdin2 UCM
          tree by default; per-device profiles may override when a
          different card name is exposed by the kernel.
        '';
      };

      defaultSink = {
        pcm = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "hw:0,0";
          description = ''
            ALSA PCM device backing the substrate-bootstrapped default
            PulseAudio sink. When null, the substrate does not create a
            sink and the system falls back to whatever WirePlumber
            auto-discovers (typically `auto_null` on devices where the
            UCM speaker path is not yet active).

            Setting this on a device profile is the supported way to
            promise a non-dummy default sink before product launches.
          '';
        };

        name = mkOption {
          type = types.str;
          default = "main_speaker";
          description = ''
            PulseAudio sink name created when `defaultSink.pcm` is set.
            Used both as the `pactl load-module` `sink_name` and as the
            argument to `pactl set-default-sink`.
          '';
        };

        description = mkOption {
          type = types.str;
          default = "Main speaker";
          description = ''
            Human-readable description applied to the bootstrapped sink
            via `device.description`.
          '';
        };

        ucmVerb = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "HiFi";
          description = ''
            UCM verb to activate via `alsaucm` before loading the PCM
            sink. Skipped when null. Required on devices where the
            speaker output is gated behind an explicit UCM verb.
          '';
        };

        ucmDevice = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "Speaker";
          description = ''
            UCM device to enable (`_enadev`) after the verb is set.
            Skipped when null.
          '';
        };
      };
    };

    performance.cemuAffinityMask = mkOption {
      type = types.str;
      default = "0xF8";
      description = "Default Cemu CPU affinity mask for this SM8550 device.";
    };
  };

  config.rocknix.device = {
    id = mkDefault config.rocknix.sm8550.deviceId;
    display.swayDeviceConfig = mkDefault config.rocknix.sm8550.display.swayDeviceConfig;
    input = {
      powerEventNames = mkDefault config.rocknix.sm8550.input.powerEventNames;
      volumeDownEventNames = mkDefault config.rocknix.sm8550.input.volumeDownEventNames;
      volumeUpLidEventNames = mkDefault config.rocknix.sm8550.input.volumeUpLidEventNames;
      rawGamepadEventNames = mkDefault config.rocknix.sm8550.input.rawGamepadEventNames;
      virtualGamepadEventNames = mkDefault config.rocknix.sm8550.input.virtualGamepadEventNames;
    };
    audio = {
      ucmPackage = mkDefault config.rocknix.sm8550.audio.ucmPackage;
      api = mkDefault config.rocknix.sm8550.audio.api;
      card = mkDefault config.rocknix.sm8550.audio.card;
      defaultSink = {
        pcm = mkDefault config.rocknix.sm8550.audio.defaultSink.pcm;
        name = mkDefault config.rocknix.sm8550.audio.defaultSink.name;
        description = mkDefault config.rocknix.sm8550.audio.defaultSink.description;
        ucmVerb = mkDefault config.rocknix.sm8550.audio.defaultSink.ucmVerb;
        ucmDevice = mkDefault config.rocknix.sm8550.audio.defaultSink.ucmDevice;
      };
    };
    performance.cemuAffinityMask = mkDefault config.rocknix.sm8550.performance.cemuAffinityMask;
  };
}
