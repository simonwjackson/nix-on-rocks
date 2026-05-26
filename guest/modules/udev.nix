# Guest-owned udev for the SM8550 main-space container.
#
# NixOS disables udev when boot.isContainer = true, but the ROCKNIX main-space
# guest owns product device policy for input, audio, and compositor startup.
# Force the full NixOS udev module back on while preserving container mode: the
# host remains the substrate/recovery plane, and the guest owns its writable
# /run/udev database. This replaces the host-side rocknix-guest-udev-stage
# cold-boot workaround documented in:
#   docs/solutions/best-practices/rocknix-layer14-main-space-cold-boot-autostart-2026-05-08.md
#   docs/solutions/runtime-errors/guest-pipewire-dummy-sink-missing-udev-sound-records-rocknix-2026-05-13.md
{ lib, ... }:

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
}
