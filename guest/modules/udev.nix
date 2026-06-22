# Guest-owned udev for main-space containers.
#
# NixOS disables udev when boot.isContainer = true, but the ROCKNIX main-space
# guest owns product device policy for input, audio, and compositor startup.
# Force the full NixOS udev module back on while preserving container mode: the
# host remains the substrate/recovery plane, and the guest owns its writable
# /run/udev database. This replaces the host-side rocknix-guest-udev-stage
# cold-boot workaround documented in:
#   docs/solutions/best-practices/rocknix-layer14-main-space-cold-boot-autostart-2026-05-08.md
#   docs/solutions/runtime-errors/guest-pipewire-dummy-sink-missing-udev-sound-records-rocknix-2026-05-13.md
{ lib, pkgs, ... }:

let
  soundCardHydrateScript = pkgs.writeShellScript "rocknix-sound-card-udev-hydrate" ''
    set -eu

    mkdir -p /run/udev/data

    card_ready() {
      props="$(${pkgs.systemd}/bin/udevadm info -q property -p "$1" 2>/dev/null || true)"
      ${pkgs.coreutils}/bin/printf '%s\n' "$props" | ${pkgs.gnugrep}/bin/grep -q '^SOUND_INITIALIZED=1$' \
        && ${pkgs.coreutils}/bin/printf '%s\n' "$props" | ${pkgs.gnugrep}/bin/grep -q '^ID_PATH=' \
        && ${pkgs.coreutils}/bin/printf '%s\n' "$props" | ${pkgs.gnugrep}/bin/grep -q '^ID_PATH_TAG='
    }

    for sys_card in /sys/class/sound/card*; do
      [ -e "$sys_card" ] || continue
      card="$(${pkgs.coreutils}/bin/basename "$sys_card")"
      data_file="/run/udev/data/+sound:$card"

      if card_ready "$sys_card"; then
        continue
      fi

      # Prefer normal udev processing. In systemd-nspawn guests sysfs is often
      # read-only, so trigger may fail with EROFS; that is expected and should
      # not prevent the synthetic guest-owned /run/udev record below.
      ${pkgs.systemd}/bin/udevadm trigger --subsystem-match=sound --sysname-match="$card" --action=change \
        >/dev/null 2>&1 || true
      ${pkgs.systemd}/bin/udevadm settle --timeout=2 >/dev/null 2>&1 || true

      if card_ready "$sys_card"; then
        continue
      fi

      devpath="$(${pkgs.coreutils}/bin/readlink -f "$sys_card" | ${pkgs.gnused}/bin/sed 's#^/sys##')"
      path_props="$(${pkgs.systemd}/bin/udevadm test-builtin path_id "$sys_card" 2>&1 || true)"
      id_path="$(${pkgs.coreutils}/bin/printf '%s\n' "$path_props" | ${pkgs.gnused}/bin/sed -n 's/^ID_PATH=//p' | ${pkgs.coreutils}/bin/tail -1)"
      id_path_tag="$(${pkgs.coreutils}/bin/printf '%s\n' "$path_props" | ${pkgs.gnused}/bin/sed -n 's/^ID_PATH_TAG=//p' | ${pkgs.coreutils}/bin/tail -1)"

      if [ -z "$id_path" ]; then
        id_path="$(${pkgs.coreutils}/bin/printf '%s\n' "$devpath" | ${pkgs.gnused}/bin/sed -n 's#^/devices/platform/\([^/]*\)/sound/.*#platform-\1#p')"
      fi
      if [ -z "$id_path" ]; then
        id_path="$card"
      fi
      if [ -z "$id_path_tag" ]; then
        id_path_tag="$(${pkgs.coreutils}/bin/printf '%s' "$id_path" | ${pkgs.coreutils}/bin/tr -c 'A-Za-z0-9_' '_' | ${pkgs.gnused}/bin/sed 's/_$//')"
      fi

      tmp_file="$data_file.$$"
      {
        ${pkgs.coreutils}/bin/printf 'I:0\n'
        ${pkgs.coreutils}/bin/printf 'E:DEVPATH=%s\n' "$devpath"
        ${pkgs.coreutils}/bin/printf 'E:SUBSYSTEM=sound\n'
        ${pkgs.coreutils}/bin/printf 'E:SOUND_INITIALIZED=1\n'
        ${pkgs.coreutils}/bin/printf 'E:SOUND_FORM_FACTOR=internal\n'
        ${pkgs.coreutils}/bin/printf 'E:ID_PATH=%s\n' "$id_path"
        ${pkgs.coreutils}/bin/printf 'E:ID_PATH_TAG=%s\n' "$id_path_tag"
        ${pkgs.coreutils}/bin/printf 'E:ID_FOR_SEAT=sound-%s\n' "$id_path_tag"
        ${pkgs.coreutils}/bin/printf 'G:seat\n'
        ${pkgs.coreutils}/bin/printf 'Q:seat\n'
        ${pkgs.coreutils}/bin/printf 'E:TAGS=:seat:\n'
        ${pkgs.coreutils}/bin/printf 'E:CURRENT_TAGS=:seat:\n'
      } > "$tmp_file" || {
        echo "rocknix-sound-card-udev-hydrate: failed to write $data_file" >&2
        exit 1
      }
      ${pkgs.coreutils}/bin/mv "$tmp_file" "$data_file" || {
        echo "rocknix-sound-card-udev-hydrate: failed to install $data_file" >&2
        exit 1
      }
      echo "rocknix-sound-card-udev-hydrate: hydrated $card with ID_PATH=$id_path" >&2
    done
  '';
in
{
  services.udev.enable = lib.mkForce true;

  # boot.isContainer normally suppresses the coldplug trigger unit entirely.
  # Re-add the upstream unit, then force-enable it so settle has a real trigger
  # to wait for instead of settling an empty queue.
  systemd.additionalUpstreamSystemUnits = [ "systemd-udev-trigger.service" ];

  systemd.services.systemd-udevd = {
    enable = lib.mkForce true;
    # nspawn provides a read-only sysfs view, but guest udev still needs to run
    # so InputPlumber-created uinput devices get /run/udev records and group
    # ownership. The upstream unit's container-hostile /sys write condition
    # otherwise skips udevd entirely.
    unitConfig.ConditionPathIsReadWrite = lib.mkForce "";
  };
  systemd.services.systemd-udev-trigger = {
    enable = lib.mkForce true;
    unitConfig.ConditionPathIsReadWrite = lib.mkForce "";
  };
  systemd.services.systemd-udev-settle = {
    enable = lib.mkForce true;
    unitConfig.ConditionPathIsReadWrite = lib.mkForce "";
  };

  systemd.services.rocknix-sound-card-udev-hydrate = {
    description = "Hydrate host-bound sound card udev records";
    wantedBy = [ "multi-user.target" ];
    wants = [ "systemd-udevd.service" "systemd-udev-trigger.service" "systemd-udev-settle.service" ];
    after = [ "systemd-udevd.service" "systemd-udev-trigger.service" "systemd-udev-settle.service" ];
    before = [ "main-space-wireplumber.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStart = soundCardHydrateScript;
      RemainAfterExit = true;
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };
}
