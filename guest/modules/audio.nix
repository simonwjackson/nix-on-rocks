# Guest-owned main-space PipeWire + WirePlumber audio substrate.
#
# The host passes kernel devices and narrow metadata into the guest, but normal
# audio policy lives here. Do not bind host /usr/share/alsa or host
# PipeWire/PulseAudio sockets into the guest; that would make ROCKNIX the audio
# policy owner again.
{ config, lib, pkgs, ... }:

let
  cfg = config.rocknix.device.audio;
  ucmPackage = cfg.ucmPackage;
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
  legacySink = cfg.defaultSink;
  explicitRoute = cfg.route;
  effectiveRoute =
    if explicitRoute.kind != "none" then
      explicitRoute
    else if legacySink.pcm != null then {
      kind = "manual-pcm";
      expectedSink = null;
      pcm = legacySink.pcm;
      sinkName = legacySink.name;
      description = legacySink.description;
      ucmVerb = legacySink.ucmVerb;
      ucmDevice = legacySink.ucmDevice;
    }
    else
      explicitRoute;
  routeActive = effectiveRoute.kind != "none";
  routeHasUcmVerb = effectiveRoute.ucmVerb != null;
  routeHasUcmDevice = effectiveRoute.ucmDevice != null;
  routeHasFullUcm = routeHasUcmVerb && routeHasUcmDevice;
  optionalLine = predicate: text: if predicate then text else "";
  routeTarget =
    if effectiveRoute.kind == "wireplumber-ucm" then
      (if effectiveRoute.expectedSink != null then effectiveRoute.expectedSink else "")
    else
      (if effectiveRoute.sinkName != null then effectiveRoute.sinkName else "");
  manualPcm = if effectiveRoute.pcm != null then effectiveRoute.pcm else "";
  manualDescription = if effectiveRoute.description != null then effectiveRoute.description else "Main speaker";
  sinkBootstrapScript = pkgs.writeShellScript "main-space-audio-sink-bootstrap" ''
    set -u

    sink_exists() {
      ${pkgs.pulseaudio}/bin/pactl list short sinks \
        | ${pkgs.coreutils}/bin/cut -f2 \
        | ${pkgs.gnugrep}/bin/grep -Fxq -- "$1"
    }

    # Wait for the PulseAudio compatibility socket. PipeWire-pulse listens
    # on $PULSE_SERVER once `main-space-pipewire-pulse.service` is healthy.
    for _ in $(${pkgs.coreutils}/bin/seq 1 60); do
      if ${pkgs.pulseaudio}/bin/pactl info >/dev/null 2>&1; then
        break
      fi
      ${pkgs.coreutils}/bin/sleep 0.5
    done

    if ! ${pkgs.pulseaudio}/bin/pactl info >/dev/null 2>&1; then
      echo "main-space-audio-sink-bootstrap: pactl cannot reach $PULSE_SERVER for declared ${effectiveRoute.kind} route" >&2
      exit 1
    fi

    ${optionalLine routeHasFullUcm ''
      ${pkgs.alsa-utils}/bin/alsaucm -c ${lib.escapeShellArg cfg.card} \
        set _verb ${lib.escapeShellArg effectiveRoute.ucmVerb} \
        set _enadev ${lib.escapeShellArg effectiveRoute.ucmDevice} \
        >/dev/null || {
          echo "main-space-audio-sink-bootstrap: failed to activate UCM ${effectiveRoute.ucmVerb}/${effectiveRoute.ucmDevice} on ${cfg.card}" >&2
          exit 1
        }
    ''}
    ${optionalLine (routeHasUcmVerb && !routeHasUcmDevice) ''
      ${pkgs.alsa-utils}/bin/alsaucm -c ${lib.escapeShellArg cfg.card} \
        set _verb ${lib.escapeShellArg effectiveRoute.ucmVerb} \
        >/dev/null || {
          echo "main-space-audio-sink-bootstrap: failed to activate UCM verb ${effectiveRoute.ucmVerb} on ${cfg.card}" >&2
          exit 1
        }
    ''}

    ${optionalLine (effectiveRoute.kind == "wireplumber-ucm") ''
      if [ -z ${lib.escapeShellArg routeTarget} ]; then
        echo "main-space-audio-sink-bootstrap: wireplumber-ucm route is missing expectedSink" >&2
        exit 1
      fi

      for _ in $(${pkgs.coreutils}/bin/seq 1 60); do
        if sink_exists ${lib.escapeShellArg routeTarget}; then
          break
        fi
        ${pkgs.coreutils}/bin/sleep 0.5
      done

      if ! sink_exists ${lib.escapeShellArg routeTarget}; then
        echo "main-space-audio-sink-bootstrap: expected WirePlumber sink ${routeTarget} was not discovered" >&2
        exit 1
      fi
    ''}

    ${optionalLine (effectiveRoute.kind == "manual-pcm") ''
      if [ -z ${lib.escapeShellArg manualPcm} ] || [ -z ${lib.escapeShellArg routeTarget} ]; then
        echo "main-space-audio-sink-bootstrap: manual-pcm route is missing pcm or sinkName" >&2
        exit 1
      fi

      # Load the ALSA sink if it is not already present. Idempotent across
      # restarts: `pactl list short sinks` returns the existing sink_name
      # after the first successful load and the script does nothing.
      if ! sink_exists ${lib.escapeShellArg routeTarget}; then
        ${pkgs.pulseaudio}/bin/pactl load-module module-alsa-sink \
          device=${lib.escapeShellArg manualPcm} \
          sink_name=${lib.escapeShellArg routeTarget} \
          sink_properties=device.description=${lib.escapeShellArg manualDescription} \
          >/dev/null || {
            echo "main-space-audio-sink-bootstrap: pactl load-module module-alsa-sink failed for ${manualPcm}" >&2
            exit 1
          }
      fi
    ''}

    if ! ${pkgs.pulseaudio}/bin/pactl set-default-sink ${lib.escapeShellArg routeTarget}; then
      echo "main-space-audio-sink-bootstrap: failed to select declared default sink ${routeTarget}" >&2
      exit 1
    fi
    ${pkgs.pulseaudio}/bin/pactl set-sink-volume ${lib.escapeShellArg routeTarget} 10% \
      >/dev/null 2>&1 || true
  '';
in
{
  imports = [ ./session.nix ];

  assertions = [
    {
      assertion = cfg.route.kind != "wireplumber-ucm" || (cfg.route.expectedSink != null && cfg.route.expectedSink != "");
      message = "rocknix.device.audio.route.expectedSink is required for wireplumber-ucm routes";
    }
    {
      assertion = cfg.route.kind != "manual-pcm" || (cfg.route.pcm != null && cfg.route.pcm != "" && cfg.route.sinkName != null && cfg.route.sinkName != "");
      message = "rocknix.device.audio.route.pcm and sinkName are required for manual-pcm routes";
    }
  ];

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
    wants = [ "systemd-udev-settle.service" "rocknix-sound-card-udev-hydrate.service" ];
    after = [ "systemd-udev-settle.service" "rocknix-sound-card-udev-hydrate.service" "main-space-runtime-dir.service" "main-space-pipewire.service" "main-space-session-dbus.service" ];
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

  # Substrate-owned default-route bootstrap. Per-device profiles declare a
  # route strategy: WirePlumber/UCM routes select an already-discovered graph
  # sink, while manual PCM routes load an explicit PulseAudio ALSA sink.
  systemd.services.main-space-audio-sink-bootstrap = lib.mkIf routeActive {
    description = "Bootstrap substrate-owned default audio route";
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
    # Substrate fallback compositor only; product sessions order after
    # the audio stack from their side.
    before = [ "main-space-sway-kiosk.service" ];
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
  ];
}
