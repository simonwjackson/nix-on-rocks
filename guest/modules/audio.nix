# Layer 14 audio module: guest-owned PipeWire + WirePlumber + AYN Odin2 UCM.
#
# The host passes kernel devices and staged udev metadata into the guest, but
# normal audio policy lives here. Do not bind host /usr/share/alsa or host
# PipeWire/PulseAudio sockets into the guest; that would make ROCKNIX the audio
# policy owner again.
{ config, pkgs, ... }:

let
  ucmPackage = config.rocknix.sm8550.audio.ucmPackage;
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
