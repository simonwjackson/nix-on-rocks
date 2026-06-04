# SM8550 audio module: guest-owned PipeWire + WirePlumber + AYN Odin2 UCM.
#
# The host passes kernel devices and staged udev metadata into the guest, but
# normal audio policy lives here. Do not bind host /usr/share/alsa or host
# PipeWire/PulseAudio sockets into the guest; that would make ROCKNIX the
# audio policy owner again.
#
# When `rocknix.sm8550.audio.defaultSink.pcm` is set, a substrate-owned
# bootstrap service runs the validated `alsaucm + pactl load-module
# module-alsa-sink` recipe so the guest exposes a real default sink instead
# of `auto_null` before product layers launch SDL/Moonlight clients. The
# bootstrap is per-device opt-in: Thor declares its measured speaker PCM and
# UCM verb; Odin 2 Portal leaves the option null until its audio path is
# physically validated.
{ config, lib, pkgs, ... }:

let
  cfg = config.rocknix.sm8550.audio;
  ucmPackage = config.rocknix.device.audio.ucmPackage;
  ucmPath = "${ucmPackage}/share/alsa/ucm2";
  uid = toString config.rocknix.session.runtimeDir.uid;
  runtimeDir = "/run/user/${uid}";
  audioServiceEnvironment = {
    XDG_RUNTIME_DIR = runtimeDir;
    DBUS_SESSION_BUS_ADDRESS = "unix:path=${runtimeDir}/bus";
    PIPEWIRE_RUNTIME_DIR = runtimeDir;
    ALSA_CONFIG_UCM2 = ucmPath;
    PULSE_SERVER = "unix:${runtimeDir}/pulse/native";
  };
  sink = cfg.defaultSink;
  defaultSinkActive = sink.pcm != null;
  optionalLine = predicate: text: if predicate then text else "";
  sinkBootstrapScript = pkgs.writeShellScript "main-space-audio-sink-bootstrap" ''
    set -u

    # Wait for the PulseAudio compatibility socket. PipeWire-pulse listens
    # on $PULSE_SERVER once `main-space-pipewire-pulse.service` is healthy.
    for _ in $(${pkgs.coreutils}/bin/seq 1 60); do
      if ${pkgs.pulseaudio}/bin/pactl info >/dev/null 2>&1; then
        break
      fi
      ${pkgs.coreutils}/bin/sleep 0.5
    done

    if ! ${pkgs.pulseaudio}/bin/pactl info >/dev/null 2>&1; then
      echo "main-space-audio-sink-bootstrap: pactl cannot reach $PULSE_SERVER; skipping sink load" >&2
      exit 0
    fi

    ${optionalLine (sink.ucmVerb != null) ''
      # Activate the substrate-declared UCM verb. Failure is non-fatal:
      # the kernel may not expose the named card yet, and downstream
      # diagnostics still want the sink-loading step to attempt.
      ${pkgs.alsa-utils}/bin/alsaucm -c ${lib.escapeShellArg cfg.card} \
        set _verb ${lib.escapeShellArg sink.ucmVerb} \
        >/dev/null 2>&1 || true
    ''}
    ${optionalLine (sink.ucmDevice != null) ''
      ${pkgs.alsa-utils}/bin/alsaucm -c ${lib.escapeShellArg cfg.card} \
        set _enadev ${lib.escapeShellArg sink.ucmDevice} \
        >/dev/null 2>&1 || true
    ''}

    # Load the ALSA sink if it is not already present. Idempotent across
    # restarts: `pactl list short sinks` returns the existing sink_name
    # after the first successful load and the script does nothing.
    if ! ${pkgs.pulseaudio}/bin/pactl list short sinks \
          | ${pkgs.gnugrep}/bin/grep -q ${lib.escapeShellArg sink.name}; then
      ${pkgs.pulseaudio}/bin/pactl load-module module-alsa-sink \
        device=${lib.escapeShellArg sink.pcm} \
        sink_name=${lib.escapeShellArg sink.name} \
        sink_properties=device.description=${lib.escapeShellArg sink.description} \
        >/dev/null || {
          echo "main-space-audio-sink-bootstrap: pactl load-module module-alsa-sink failed" >&2
          exit 0
        }
    fi

    ${pkgs.pulseaudio}/bin/pactl set-default-sink ${lib.escapeShellArg sink.name} \
      >/dev/null 2>&1 || true
  '';
in
{
  # Keep NixOS PipeWire configuration available, but do not rely on its user
  # units: the main-space kiosk bypasses PAM/logind user sessions. The
  # root-owned main-space-* services below run the graph in the same
  # /run/user/<uid> runtime as Sway and launched apps. They are ordered
  # After=main-space-runtime-dir.service (defined in ../modules/session.nix)
  # so logind's per-uid tmpfs mount has already happened before any socket
  # is written; see that module's comment for the original wipe race.
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
    wireplumber.enable = true;
  };

  services.dbus.enable = true;

  hardware.bluetooth = {
    enable = true;
    # The guest owns Bluetooth HID pairing/connection in main-space mode.
    # Power the controller at boot so trusted mice/keyboards reconnect without
    # a host-side bluetoothd or manual bluetoothctl power-on.
    powerOnBoot = true;
    settings = {
      General = {
        FastConnectable = "true";
        JustWorksRepairing = "always";
      };
    };
  };

  # NixOS' bluez unit is WantedBy=bluetooth.target, but our nspawn main-space
  # boot does not otherwise pull bluetooth.target into the transaction. Start
  # bluetoothd as part of the guest boot so paired HID devices reconnect.
  systemd.services.bluetooth.wantedBy = [ "multi-user.target" ];

  systemd.services.main-space-pipewire = {
    description = "Main-space root PipeWire service";
    wantedBy = [ "multi-user.target" ];
    after = [ "main-space-runtime-dir.service" "main-space-session-dbus.service" ];
    requires = [ "main-space-runtime-dir.service" ];
    serviceConfig = {
      Type = "simple";
      User = "root";
      ExecStart = "${pkgs.pipewire}/bin/pipewire";
      Restart = "on-failure";
      RestartSec = 3;
    };
    environment = audioServiceEnvironment;
  };

  systemd.services.main-space-pipewire-pulse = {
    description = "Main-space root PipeWire PulseAudio service";
    wantedBy = [ "multi-user.target" ];
    after = [ "main-space-runtime-dir.service" "main-space-pipewire.service" "main-space-session-dbus.service" ];
    requires = [ "main-space-runtime-dir.service" "main-space-pipewire.service" ];
    serviceConfig = {
      Type = "simple";
      User = "root";
      ExecStart = "${pkgs.pipewire}/bin/pipewire-pulse";
      Restart = "on-failure";
      RestartSec = 3;
    };
    environment = audioServiceEnvironment;
  };

  systemd.services.main-space-wireplumber = {
    description = "Main-space root WirePlumber service";
    wantedBy = [ "multi-user.target" ];
    wants = [ "systemd-udev-settle.service" ];
    after = [ "systemd-udev-settle.service" "main-space-runtime-dir.service" "main-space-pipewire.service" "main-space-session-dbus.service" ];
    requires = [ "main-space-runtime-dir.service" "main-space-pipewire.service" ];
    serviceConfig = {
      Type = "simple";
      User = "root";
      ExecStart = "${pkgs.wireplumber}/bin/wireplumber";
      Restart = "on-failure";
      RestartSec = 3;
    };
    environment = audioServiceEnvironment;
  };

  # Substrate-owned default-sink bootstrap. Per-device profiles opt in by
  # setting `rocknix.sm8550.audio.defaultSink.pcm`. When unset (e.g. Odin 2
  # Portal until its audio path is physically validated), the service is
  # omitted entirely and WirePlumber's `auto_null` fallback remains the
  # default sink. Either way, no product/kiosk service has to know about
  # alsaucm or PCM identifiers to get audible audio.
  systemd.services.main-space-audio-sink-bootstrap = lib.mkIf defaultSinkActive {
    description = "Bootstrap substrate-owned default ALSA sink";
    wantedBy = [ "multi-user.target" ];
    after = [
      "main-space-runtime-dir.service"
      "main-space-session-dbus.service"
      "main-space-pipewire.service"
      "main-space-pipewire-pulse.service"
      "main-space-wireplumber.service"
    ];
    requires = [
      "main-space-runtime-dir.service"
      "main-space-pipewire.service"
      "main-space-pipewire-pulse.service"
    ];
    before = [
      "main-space-sway-kiosk.service"
      "korri-kiosk.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStart = sinkBootstrapScript;
      RemainAfterExit = true;
      StandardOutput = "journal";
      StandardError = "journal";
    };
    environment = audioServiceEnvironment;
  };

  environment.variables = audioServiceEnvironment;

  environment.systemPackages = with pkgs; [
    alsa-utils
    pipewire
    wireplumber
    pulseaudio
    ucmPackage
    bluez
    bluez-tools
  ];
}
