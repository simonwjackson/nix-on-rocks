# Shared SM8550 device policy with small per-device overrides.
#
# The default remains the hardware-validated Thor behavior. Additional
# devices (Odin 2 Portal, etc.) should override only the measured differences: display
# layout, input event names, audio UCM package/card names, and performance
# policy. Main-space modules consume these options instead of hardcoding Thor
# assumptions inline.
{ config, lib, pkgs, ... }:

let
  inherit (lib) mkOption types;
  aynOdin2Ucm = pkgs.callPackage ../packages/audio/ayn-odin2-ucm { };
in
{
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
        # landscape orientation on DSI-2 with these transforms.
        output DSI-2 transform 90
        output DSI-2 scale 2.0
        output DSI-2 pos 0 0
        output DSI-2 bg #000000 solid_color
        output DSI-2 allow_tearing yes
        output DSI-2 max_render_time off

        # Thor's bottom panel: 1080x1240 native, same physical orientation
        # as DSI-2 (panel is portrait, device is held landscape). transform
        # 90 + scale 2.0 yields 620x540 logical, stacked under DSI-2's
        # 960x540 starting at y=540. Both panels share the device's full
        # physical width but the bottom panel is shorter, so its logical
        # width is narrower.
        output DSI-1 enable
        output DSI-1 transform 90
        output DSI-1 scale 2.0
        output DSI-1 pos 0 540
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
    };

    audio.ucmPackage = mkOption {
      type = types.package;
      default = aynOdin2Ucm;
      description = "ALSA UCM package used by the guest-owned audio stack.";
    };

    performance.cemuAffinityMask = mkOption {
      type = types.str;
      default = "0xF8";
      description = "Default Cemu CPU affinity mask for this SM8550 device.";
    };
  };
}
