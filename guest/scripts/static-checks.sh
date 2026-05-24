#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016
set -euo pipefail

ROOT="$(CDPATH="" cd -- "$(dirname -- "$0")/.." && pwd)"
# After the monorepo merge (plan 001), flake.nix, flake.lock, and packages/
# live at repo root rather than guest/. ROOT continues to anchor at guest/
# for things that stayed there (modules/, profiles/, launchers/, justfile,
# README.md, .github/). REPO_ROOT is used for the moved items.
REPO_ROOT="$(CDPATH="" cd -- "$ROOT/.." && pwd)"
DOCS_ROOT="${NIX_ON_ROCKS_DOCS_ROOT:-}"
if [ -z "${DOCS_ROOT}" ]; then
  if [ -d "$ROOT/docs" ]; then
    DOCS_ROOT="$ROOT/docs"
  elif [ -d "$ROOT/../docs" ]; then
    DOCS_ROOT="$(CDPATH="" cd -- "$ROOT/../docs" && pwd)"
  else
    DOCS_ROOT=""
  fi
fi
fail() { echo "FAIL: $*" >&2; exit 1; }

[ -f "$REPO_ROOT/flake.nix" ] || fail "missing flake.nix"
[ -f "$REPO_ROOT/flake.lock" ] || fail "missing flake.lock"
[ -f "$ROOT/justfile" ] || fail "missing justfile"
[ -f "$ROOT/rocknix-guest.nix" ] || fail "missing default guest config"
[ -f "$ROOT/.github/workflows/build-rootfs-seed.yml" ] || fail "missing rootfs seed publish workflow"
[ -d "$ROOT/modules" ] || fail "missing modules directory"
[ -d "$ROOT/profiles" ] || fail "missing profiles directory"
[ -d "$ROOT/launchers" ] || fail "missing launchers directory"
[ -d "$REPO_ROOT/packages" ] || fail "missing packages directory"

# Flake shape and package exposure.
grep -q 'targetSystem = "aarch64-linux"' "$REPO_ROOT/flake.nix" \
  || fail "guest flake must target aarch64-linux"
grep -q 'x86_64-linux' "$REPO_ROOT/flake.nix" \
  || fail "guest flake must expose x86_64 host build package"
grep -q 'nixos-25.11' "$REPO_ROOT/flake.nix" \
  || fail "guest flake must pin the nixpkgs release input"
! grep -q 'korri.url' "$REPO_ROOT/flake.nix" \
  || fail "guest flake must not keep Korri as an input after dependency inversion"
! grep -q 'korri.nixosModules\|korri.packages\|services.korri' "$REPO_ROOT/flake.nix" \
  || fail "guest flake must not compose Korri product modules or packages after cleanup"
! grep -q 'KORRI_INPUT' "$ROOT/justfile" "$ROOT/README.md" \
  || fail "local Korri override workflow must be removed from nix-on-rocks after cleanup"
grep -q 'Korri consumes nix-on-rocks' "$ROOT/README.md" \
  || fail "README must document Korri as downstream consumer"
! grep -R 'services\.korri\.nativeBridgeUrl\|nativeBridgeUrl = ' "$REPO_ROOT/flake.nix" "$ROOT/profiles" "$ROOT/modules" "$ROOT/README.md" >/tmp/rocknix-nix-guest-korri-bridge-grep.$$ \
  || { cat /tmp/rocknix-nix-guest-korri-bridge-grep.$$ >&2; rm -f /tmp/rocknix-nix-guest-korri-bridge-grep.$$; fail "ROCKNIX must not own Korri nativeBridgeUrl configuration"; }
rm -f /tmp/rocknix-nix-guest-korri-bridge-grep.$$
grep -q 'nixpkgs-sdl2-classic.url = "github:NixOS/nixpkgs/nixos-24.11"' "$REPO_ROOT/flake.nix" \
  || fail "Cemu package must retain narrow classic SDL2 input"
grep -q 'cemu = pkgs.callPackage ./packages/cemu/package.nix' "$REPO_ROOT/flake.nix" \
  || fail "root flake must expose packages.cemu from packages/cemu"
grep -q 'steam = pkgs.callPackage ./packages/steam/package.nix' "$REPO_ROOT/flake.nix" \
  || fail "root flake must expose packages.steam from packages/steam"
grep -q 'default = cemu' "$REPO_ROOT/flake.nix" \
  || fail "default package must alias cemu"
grep -q 'cemu-rocknix-package = cemu' "$REPO_ROOT/flake.nix" \
  || fail "compatibility alias must remain available for current consumers"
grep -q 'cemu = cemu;' "$REPO_ROOT/flake.nix" \
  || fail "guest flake must retain the in-repo Cemu package output"
grep -q 'steam = steam;' "$REPO_ROOT/flake.nix" \
  || fail "guest flake must retain the in-repo Steam package output"
grep -q 'rocknix-guest-base = ./guest/profiles/rocknix-guest-base.nix' "$REPO_ROOT/flake.nix" \
  || fail "guest flake must expose rocknix-guest-base substrate module"
[ -f "$ROOT/profiles/rocknix-guest-base.nix" ] \
  || fail "missing rocknix-guest-base substrate profile"
grep -q './rocknix-guest-base.nix' "$ROOT/profiles/main-space.nix" \
  || fail "legacy main-space profile must build on rocknix-guest-base"
! grep -q 'services\.korri\|korri\.nixosModules\|korri\.packages' "$ROOT/profiles/rocknix-guest-base.nix" \
  || fail "rocknix-guest-base must not write or import Korri product surfaces"
! grep -q 'services\.korri\|korri\.nixosModules\|korri\.packages' "$ROOT/profiles/main-space.nix" \
  || fail "legacy main-space profile must not compose Korri product surfaces after cleanup"
! grep -q 'rocknix-guest-main-space\|rocknix-guest-stage10-proof\|rocknix-stage10-proof-marker' "$REPO_ROOT/flake.nix" \
  || fail "guest flake must remove Korri-era main-space and stage10 product outputs"
grep -q 'deviceProfileByCompatible' "$REPO_ROOT/flake.nix" \
  || fail "guest flake must define deviceProfileByCompatible dispatch table for host-side device selection"
grep -q 'inherit deviceProfileByCompatible selectDeviceProfileFromCompatible' "$REPO_ROOT/flake.nix" \
  || fail "guest flake lib must expose device profile selection helpers for downstream consumers"
grep -q '"ayn,thor" = ./guest/profiles/devices/thor.nix' "$REPO_ROOT/flake.nix" \
  || fail "deviceProfileByCompatible must register Thor (ayn,thor) -> profiles/devices/thor.nix"
grep -q '"ayn,odin2portal" = ./guest/profiles/devices/odin2portal.nix' "$REPO_ROOT/flake.nix" \
  || fail "deviceProfileByCompatible must register Odin 2 Portal (ayn,odin2portal) -> profiles/devices/odin2portal.nix"
grep -q '/proc/device-tree/compatible' "$REPO_ROOT/flake.nix" \
  || fail "by-compatible dispatch must read /proc/device-tree/compatible"
! grep -q 'mainSpaceByCompatibleConfiguration\|mainSpaceConfigurationFor selectDeviceProfileFromCompatible' "$REPO_ROOT/flake.nix" \
  || fail "guest flake must remove the retired by-compatible product NixOS configuration"
! grep -q '"rootfs-odin2portal"\|"rootfs-thor"\|rootfs = rootfsThor' "$REPO_ROOT/flake.nix" \
  || fail "guest flake must remove product rootfs aliases after Korri cutover"
grep -q 'output DSI-1 transform 270' "$ROOT/profiles/devices/odin2portal.nix" \
  || fail "Odin 2 Portal profile must keep its upright DSI-1 orientation"
grep -q 'input type:touch map_to_output DSI-1' "$ROOT/profiles/devices/odin2portal.nix" \
  || fail "Odin 2 Portal profile must route touch to its single DSI-1 panel"
old_package_repo="nix-sm${SM8550_SUFFIX:-8550}"
! grep -R "github:simonwjackson/$old_package_repo\|nix.registry.$old_package_repo\|$old_package_repo.packages" \
  "$REPO_ROOT/flake.nix" "$REPO_ROOT/flake.lock" "$ROOT/README.md" "$ROOT/launchers" >/tmp/rocknix-nix-guest-old-package-repo-grep.$$ \
  || { cat /tmp/rocknix-nix-guest-old-package-repo-grep.$$ >&2; rm -f /tmp/rocknix-nix-guest-old-package-repo-grep.$$; fail "guest repo must not depend on the former external package flake"; }
rm -f /tmp/rocknix-nix-guest-old-package-repo-grep.$$
grep -q 'root/etc/ssh/authorized_keys.d/root' "$REPO_ROOT/flake.nix" \
  || fail "rootfs must provide regular authorized_keys target for StrictModes"
grep -q 'root/usr/bin/nix' "$REPO_ROOT/flake.nix" \
  || fail "rootfs must expose /usr/bin/nix for bridge/smoke contracts"

ROCKNIX_SUBSTRATE_PATCH="$REPO_ROOT/patches/rocknix/0006-rocknix-guest-substrate.patch"
grep -q 'PKG_NIX_GUEST_AUTHORITY_REPO="simonwjackson/korri"' "$ROCKNIX_SUBSTRATE_PATCH" \
  || fail "ROCKNIX substrate patch must package Korri as product authority during cutover"
grep -q 'PKG_NIX_GUEST_BUILD_TARGET=' "$ROCKNIX_SUBSTRATE_PATCH" \
  || fail "ROCKNIX guest promotion must make the flake build target configurable"
grep -q 'korri-rocknix-kiosk-by-compatible' "$ROCKNIX_SUBSTRATE_PATCH" \
  || fail "ROCKNIX guest promotion must target Korri's by-compatible appliance output"
promote_section="$(sed -n '/scripts\/rocknix-guest-promote /,/scripts\/rocknix-guest-root-ensure /p' "$ROCKNIX_SUBSTRATE_PATCH")"
! printf '%s\n' "$promote_section" | grep -q '.#nixosConfigurations.rocknix-guest-main-space-by-compatible.config.system.build.toplevel' \
  || fail "ROCKNIX guest promotion must not hard-code the retired nix-on-rocks by-compatible product target"
[ -x "$REPO_ROOT/scripts/verify-korri-promotion-proof" ] \
  || fail "missing executable Korri promotion proof script"
grep -q 'promotion-proof passed' "$REPO_ROOT/scripts/verify-korri-promotion-proof" \
  || fail "Korri promotion proof script must exercise the configured target"

ROOTFS_SEED_WORKFLOW="$ROOT/.github/workflows/build-rootfs-seed.yml"
grep -q 'Retired legacy rootfs seed fallback' "$ROOTFS_SEED_WORKFLOW" \
  || fail "rootfs seed workflow must be retired after Korri cutover"
! grep -q 'nix build ".#${{ steps.meta.outputs.package }}"\|rootfs-thor\|rootfs-odin2portal' "$ROOTFS_SEED_WORKFLOW" \
  || fail "retired rootfs seed workflow must not build removed product rootfs aliases"
! grep -q 'sha256sum\|split -b 1900m\|softprops/action-gh-release\|actions/upload-artifact' "$ROOTFS_SEED_WORKFLOW" \
  || fail "retired rootfs seed workflow must not publish nix-on-rocks product rootfs artifacts"
grep -q 'nix-on-rocks no longer publishes Korri product/appliance rootfs' "$ROOTFS_SEED_WORKFLOW" \
  || fail "retired rootfs seed workflow must direct operators to Korri artifacts"
grep -q 'Retired legacy rootfs seed fallback' "$ROOT/README.md" \
  || fail "README must document retired rootfs seed publishing workflow"

# Guest baseline.
grep -R -q 'boot.isContainer = true' "$ROOT" \
  || fail "guest must be a container-style rootfs"
grep -R -q 'services.openssh = {' "$ROOT" \
  || fail "guest must define locked-down OpenSSH"
grep -R -q 'ports = \[ 2222 \];' "$ROOT" \
  || fail "guest SSH must listen on Layer 12 default port 2222"
grep -q 'profiles/ssh.nix' "$ROOT/rocknix-guest.nix" \
  || fail "default guest config must import SSH-capable modular profile"

# Guest-internal files (live under guest/).
for f in \
  modules/base.nix \
  modules/device.nix \
  modules/tools.nix \
  modules/ssh.nix \
  modules/display.nix \
  modules/audio.nix \
  modules/input.nix \
  modules/network.nix \
  modules/lid.nix \
  modules/steam.nix \
  modules/session.nix \
  profiles/minimal.nix \
  profiles/ssh.nix \
  profiles/rocknix-guest-base.nix \
  profiles/main-space.nix \
  profiles/dev-env.nix \
  profiles/devices/thor.nix \
  profiles/devices/odin2portal.nix; do
  [ -f "$ROOT/$f" ] || fail "missing guest module/profile: $f"
done

# Package files (moved to repo root by the monorepo merge).
for f in \
  packages/cemu/package.nix \
  packages/cemu/manifest.nix \
  devices/sm8550/cemu/settings.xml \
  packages/steam/package.nix \
  packages/steam/manifest.nix \
  packages/inputplumber/default.nix \
  packages/inputplumber/maps/devices/02-ayn-controller.yaml \
  packages/inputplumber/maps/capability_maps/ayn_mcu.yaml; do
  [ -f "$REPO_ROOT/$f" ] || fail "missing package file: $f"
done

grep -q 'programs.sway' "$ROOT/modules/display.nix" \
  || fail "display module must enable sway"
grep -q 'hardware.graphics' "$ROOT/modules/display.nix" \
  || fail "display module must enable hardware.graphics"
grep -q 'services.pipewire' "$ROOT/modules/audio.nix" \
  || fail "audio module must enable pipewire"
grep -q 'services.dbus' "$ROOT/modules/audio.nix" \
  || fail "audio module must enable D-Bus"
grep -q 'hardware.bluetooth' "$ROOT/modules/audio.nix" \
  || fail "audio module must enable bluetooth"
grep -q 'powerOnBoot = true' "$ROOT/modules/audio.nix" \
  || fail "guest Bluetooth must power on at boot for trusted HID reconnect"
grep -q 'systemd.services.bluetooth.wantedBy = \[ "multi-user.target" \]' "$ROOT/modules/audio.nix" \
  || fail "guest Bluetooth service must start during main-space boot"
grep -q 'systemd.services.main-space-pipewire' "$ROOT/modules/audio.nix" \
  || fail "audio module must configure a root-scoped PipeWire service for the kiosk session"
grep -q 'systemd.services.main-space-pipewire-pulse' "$ROOT/modules/audio.nix" \
  || fail "audio module must configure a root-scoped PipeWire PulseAudio service"
grep -q 'systemd.services.main-space-wireplumber' "$ROOT/modules/audio.nix" \
  || fail "audio module must configure a root-scoped WirePlumber service"
grep -q 'wantedBy = \[ "multi-user.target" \]' "$ROOT/modules/audio.nix" \
  || fail "audio module must start audio services in the kiosk boot target"
grep -q 'ALSA_CONFIG_UCM2 = ucmPath' "$ROOT/modules/audio.nix" \
  || fail "audio module must pass guest-owned UCM path to audio services"
grep -qE 'PULSE_SERVER = "unix:/run/user/[^"]*/pulse/native"' "$ROOT/modules/audio.nix" \
  || fail "audio module must point clients at the root PipeWire Pulse socket (literal /run/user/0/... or parameterized /run/user/\${...}/...)"
grep -q 'services.inputplumber' "$ROOT/modules/input.nix" \
  || fail "input module must enable guest-owned InputPlumber"
grep -q '0.75.2' "$REPO_ROOT/packages/inputplumber/default.nix" \
  || fail "guest InputPlumber package must match the validated ROCKNIX host version"
grep -q 'name: AYN Layout' "$REPO_ROOT/packages/inputplumber/maps/devices/02-ayn-controller.yaml" \
  || fail "guest InputPlumber package must include ROCKNIX SM8550 AYN controller map"
grep -q 'ayn_mcu' "$REPO_ROOT/packages/inputplumber/maps/capability_maps/ayn_mcu.yaml" \
  || fail "guest InputPlumber package must include ROCKNIX SM8550 AYN capability map"
grep -q 'c /dev/uinput' "$ROOT/modules/input.nix" \
  || fail "input module must create /dev/uinput for guest-owned virtual devices"
grep -q '"korri-kiosk.service"' "$ROOT/modules/input.nix" \
  && grep -q '"main-space-sway-kiosk.service"' "$ROOT/modules/input.nix" \
  || fail "guest InputPlumber must order before Korri and fallback sway sessions"
grep -q '../modules/input.nix' "$ROOT/profiles/rocknix-guest-base.nix" \
  || fail "rocknix-guest-base profile must import the guest input module"
grep -q 'ayn-odin2-ucm' "$REPO_ROOT/flake.nix" \
  || fail "root flake must expose the guest-owned AYN Odin2 UCM package"
grep -q 'ALSA_CONFIG_UCM2' "$ROOT/modules/audio.nix" \
  || fail "audio module must route ALSA UCM lookup to the guest-owned UCM package"
grep -q 'devices/sm8550/audio/ayn-odin2-ucm' "$ROOT/modules/device.nix" \
  || fail "SM8550 device defaults must consume the in-repo AYN Odin2 UCM package"
grep -q 'Use case configuration for AYN Odin2' "$REPO_ROOT/devices/sm8550/audio/ayn-odin2-ucm/ucm2/AYN/Odin2/AYN-Odin2.conf" \
  || fail "AYN Odin2 UCM package must include the card use-case file"
grep -q 'PlaybackPCM "hw:${CardId},0"' "$REPO_ROOT/devices/sm8550/audio/ayn-odin2-ucm/ucm2/AYN/Odin2/HiFi.conf" \
  || fail "AYN Odin2 UCM package must expose the speaker playback PCM"
[ -L "$REPO_ROOT/devices/sm8550/audio/ayn-odin2-ucm/ucm2/conf.d/sm8550/AYN-Odin2.conf" ] \
  || fail "AYN Odin2 UCM package must include the SM8550 card-name symlink"
[ -L "$REPO_ROOT/devices/sm8550/audio/ayn-odin2-ucm/ucm2/conf.d/sm8550/ayn-AYNOdin2-.conf" ] \
  || fail "AYN Odin2 UCM package must include the EFI-compatible card-name symlink"
[ -L "$REPO_ROOT/devices/sm8550/audio/ayn-odin2-ucm/ucm2/conf.d/sm8550/AYN-Thor.conf" ] \
  || fail "AYN Odin2 UCM package must include Thor long-name card symlink"
[ -L "$REPO_ROOT/devices/sm8550/audio/ayn-odin2-ucm/ucm2/conf.d/sm8550/AYNThor.conf" ] \
  || fail "AYN Odin2 UCM package must include Thor card-id symlink"
! grep -q 'module-alsa-sink\|sink_name=thor_hw0\|rocknix-audio-alsa-sink' "$ROOT/modules/audio.nix" "$ROOT/modules/lid.nix" \
  || fail "audio path must not depend on the diagnostic thor_hw0 module-alsa-sink workaround"

# ==========================================================================
# main-space /run/user/<uid> ownership (plan
# docs/plans/2026-05-24-001-fix-main-space-pipewire-runtime-dir-plan.md).
#
# Per the U1 diagnostic trace, /run/user/<uid> is owned by logind's
# user-runtime-dir@<uid>.service template (which mounts the tmpfs one
# second after main-space-pipewire wrote its sockets into a plain
# directory, masking them). main-space-* consumers must order After= a
# thin substrate-owned anchor unit that itself orders After= and
# Requires= user-runtime-dir@${uid}.service, so logind's tmpfs mount
# happens before any session socket is written.
# ==========================================================================
grep -q 'options\.rocknix\.session\.runtimeDir' "$ROOT/modules/session.nix" \
  || fail "modules/session.nix must declare the main-space runtime-dir UID option (rocknix.session.runtimeDir.uid)"
grep -q 'systemd.services.main-space-runtime-dir' "$ROOT/modules/session.nix" \
  || fail "modules/session.nix must define the main-space runtime-dir anchor service"
grep -q 'user-runtime-dir@' "$ROOT/modules/session.nix" \
  || fail "main-space runtime-dir anchor must order against logind user-runtime-dir@<uid>.service"
grep -q '../modules/session.nix' "$ROOT/profiles/rocknix-guest-base.nix" \
  || fail "rocknix-guest-base profile must import the session module"
grep -q '../modules/session.nix' "$ROOT/profiles/dev-env.nix" \
  || fail "dev-env profile must import the session module (so its main-space-sway-kiosk can order behind the runtime-dir anchor)"
! grep -qE 'systemd\.tmpfiles\.rules.*"d /run/user' "$ROOT/modules/session.nix" "$ROOT/profiles/rocknix-guest-base.nix" \
  || fail "session module / rocknix-guest-base must NOT declare a tmpfiles rule for /run/user/<uid> (U1 verdict: logind creates the dir inside its tmpfs; a second creator races the same way today's code does)"
! grep -qE 'KillUserProcesses|RemoveIPC' "$ROOT"/modules/*.nix "$ROOT"/profiles/*.nix \
  || fail "main-space runtime-dir fix must NOT introduce KillUserProcesses/RemoveIPC logind knobs (U1 verdict: logind is not implicated as a session-reaper, only as a too-late tmpfs mounter; ordering against user-runtime-dir@ is sufficient)"

# Consumer-ordering assertions, the install-d removal assertions, the
# dev-env audit-gap assertion, and the env-triplet parameterization
# assertion all land with the U3 implementation commit so this script
# stays green commit-by-commit.

grep -q 'main-space-hardware-button-handler' "$ROOT/modules/lid.nix" \
  || fail "lid module must own guest hardware button handling"
grep -q 'rocknix-volume' "$ROOT/modules/lid.nix" \
  || fail "lid module must provide a guest volume helper"
grep -q 'powerEventNames = mkOption' "$ROOT/modules/device.nix" \
  || fail "SM8550 device module must declare overrideable power input names"
grep -q 'volumeDownEventNames = mkOption' "$ROOT/modules/device.nix" \
  || fail "SM8550 device module must declare overrideable volume-down input names"
grep -q 'volumeUpLidEventNames = mkOption' "$ROOT/modules/device.nix" \
  || fail "SM8550 device module must declare overrideable volume-up/lid input names"
grep -q 'find_event_by_names' "$ROOT/modules/lid.nix" \
  || fail "hardware button handler must discover input devices from the SM8550 device profile"
grep -q 'HandlePowerKey = "ignore"' "$ROOT/modules/lid.nix" \
  || fail "logind must not race the guest hardware button handler for power key events"
grep -q 'wantedBy = \[ "multi-user.target" \]' "$ROOT/modules/lid.nix" \
  || fail "hardware button handler must be wanted by multi-user.target"
! grep -q '"rocknix-sway-kiosk.service"' "$ROOT/modules/lid.nix" \
  || fail "hardware button handler must not be ordered behind the compositor"
grep -q 'rocknix-steam-ensure-uinput' "$ROOT/modules/steam.nix" \
  || fail "Steam module must repair guest /dev/uinput before Steam Input starts"
grep -q '/sys/devices/virtual/misc/uinput/dev' "$ROOT/modules/steam.nix" \
  || fail "Steam uinput prep must derive the device number from sysfs when available"
grep -q '/proc/misc' "$ROOT/modules/steam.nix" \
  || fail "Steam uinput prep must fall back to kernel misc device discovery"
! grep -q 'mknod /dev/uinput c 10 223' "$ROOT/modules/steam.nix" \
  || fail "Steam uinput prep must not hardcode the live Thor uinput device number"
grep -q 'PRESSURE_VESSEL_FILESYSTEMS_RW' "$REPO_ROOT/packages/steam/scripts/steam-guest-run" \
  || fail "Steam package run capsule must expose uinput/input devices to pressure-vessel"
! grep -q 'PRESSURE_VESSEL_FILESYSTEMS_RW' "$ROOT/modules/steam.nix" \
  || fail "Steam module must not own pressure-vessel input exposure after runtime capsule refactor"
grep -q 'networking.networkmanager' "$ROOT/modules/network.nix" \
  || fail "network module must enable NetworkManager"
grep -q 'wifi.backend = "iwd"' "$ROOT/modules/network.nix" \
  || fail "NetworkManager must use guest-owned iwd for Wi-Fi"
grep -q 'networking.nftables' "$ROOT/modules/network.nix" \
  || fail "network module must use nftables"
grep -q 'networking.resolvconf' "$ROOT/modules/network.nix" \
  || fail "network module must explicitly handle resolvconf"
grep -q 'services.tailscale' "$ROOT/modules/network.nix" \
  || fail "network module must make Tailscale guest-owned"
grep -q 'useRoutingFeatures = "client"' "$ROOT/modules/network.nix" \
  || fail "guest Tailscale must use client routing features"
grep -q 'extraSetFlags' "$ROOT/modules/network.nix" \
  || fail "guest Tailscale must set container-safe client preferences"
grep -q -- '--accept-dns=false' "$ROOT/modules/network.nix" \
  || fail "guest Tailscale must not manage DNS without systemd-resolved"
grep -q -- '--netfilter-mode=off' "$ROOT/modules/network.nix" \
  || fail "guest Tailscale must avoid unsupported netfilter MARK rules"
grep -q 'environment.etc."resolv.conf".source = "/run/NetworkManager/no-stub-resolv.conf"' "$ROOT/modules/network.nix" \
  || fail "guest resolv.conf must point at NetworkManager's non-stub resolver file"
grep -q 'AmbientCapabilities' "$ROOT/modules/network.nix" \
  || fail "guest Tailscale service must receive ambient network capabilities"
grep -q 'CAP_NET_ADMIN' "$ROOT/modules/network.nix" \
  || fail "guest Tailscale service must be able to create tailscale0"
grep -q 'CAP_NET_RAW' "$ROOT/modules/network.nix" \
  || fail "guest Tailscale service must be able to open raw network sockets"
grep -q 'tailscale' "$ROOT/modules/network.nix" \
  || fail "network module must include the tailscale CLI package"
grep -q 'iwd' "$ROOT/modules/network.nix" \
  || fail "network module must include guest iwd for Wi-Fi ownership"
grep -q 'time.timeZone' "$ROOT/profiles/rocknix-guest-base.nix" \
  || fail "rocknix-guest-base profile must set time.timeZone"
grep -q 'systemd.services.main-space-sway-kiosk' "$ROOT/profiles/main-space.nix" \
  || fail "main-space profile must define the fallback sway kiosk service"
grep -q 'wantedBy = \[ "multi-user.target" \]' "$ROOT/profiles/main-space.nix" \
  || fail "sway kiosk service must be wanted by multi-user.target"
grep -q '"systemd-user-sessions.service"' "$ROOT/profiles/main-space.nix" \
  && grep -q '"main-space-session-dbus.service"' "$ROOT/profiles/main-space.nix" \
  || fail "sway kiosk service must order only after concrete prerequisites"
! grep -q 'after = \[ "multi-user.target"' "$ROOT/profiles/main-space.nix" \
  || fail "sway kiosk service must not order After=multi-user.target"
grep -q 'CEMU_BIOS_ROOT = "/storage/roms/bios/cemu"' "$ROOT/profiles/main-space.nix" \
  || fail "main-space session must own temporary Cemu BIOS compatibility root"
grep -q 'CEMU_AFFINITY_MASK = sm8550.performance.cemuAffinityMask' "$ROOT/profiles/main-space.nix" \
  || fail "main-space session must consume the SM8550 device Cemu affinity default"
! grep -q 'korri-desktop-device' "$ROOT/profiles/main-space.nix" \
  || fail "legacy main-space profile must not bind Korri launch after cleanup"
grep -q 'default = "0xF8"' "$ROOT/modules/device.nix" \
  || fail "SM8550 device defaults must retain measured Odin2 Cemu affinity default"
for profile in main-space dev-env; do
  profile_path="$ROOT/profiles/$profile.nix"
  grep -q 'bindsym Home mode "\$home_chord_mode"' "$profile_path" \
    || fail "$profile profile must bind custom chords to Home"
  grep -q 'bindsym XF86HomePage mode "\$home_chord_mode"' "$profile_path" \
    || fail "$profile profile must accept XF86HomePage as a Home-chord prefix"
  grep -q 'mode "\$home_chord_mode"' "$profile_path" \
    || fail "$profile profile must define a Home chord mode"
  ! grep -q 'set \$mod Mod4\|bindsym \$mod' "$profile_path" \
    || fail "$profile profile must not use AYN/Mod4 for custom chords"
done

# Launch adapters.
for launcher in \
  botw-guest.sh \
  cemu-sm8550-performance.sh \
  cemu-storage-adapter.sh \
  games-launcher.sh \
  host-tune.sh \
  launch-host-cemu-through-guest-display.sh \
  remote-cemu-build-fingerprint.sh \
  remote-cemu-cleanup.sh \
  remote-cemu-live-campaign.sh \
  remote-cemu-import.sh \
  remote-cemu-promote.sh \
  remote-cemu-runner.sh \
  remote-cemu-runtime-ab.sh \
  remote-cemu-single-run-validation.sh \
  start_cemu_guest.sh \
  start_cemu_guest_candidate.sh \
  start_cemu_guest_gamescope.sh \
  start_cemu_guest_mangohud.sh \
  start_cemu_guest_rocknixmesa.sh; do
  path="$ROOT/launchers/$launcher"
  [ -f "$path" ] || fail "missing launcher: $launcher"
  bash -n "$path" || fail "launcher has syntax errors: $launcher"
done

grep -q 'SYSTEM_CEMU=' "$ROOT/launchers/start_cemu_guest.sh" \
  || fail "start_cemu_guest.sh must default through the main-space system Cemu package"
grep -q 'PROMOTED_CEMU=' "$ROOT/launchers/start_cemu_guest.sh" \
  || fail "start_cemu_guest.sh must retain promoted Cemu fallback"
grep -q 'REQUESTED_CEMU=${CEMU_BIN:-$SYSTEM_CEMU}' "$ROOT/launchers/start_cemu_guest.sh" \
  || fail "start_cemu_guest.sh must preserve CEMU_BIN override over system Cemu"
! grep -q 'CEMU_VULKAN_LOADER_LIB_PATH\|LD_LIBRARY_PATH' "$ROOT/launchers/start_cemu_guest.sh" \
  || fail "start_cemu_guest.sh must not own Vulkan loader setup"
grep -q 'cemu-storage-adapter.sh' "$ROOT/launchers/start_cemu_guest.sh" \
  || fail "start_cemu_guest.sh must delegate Cemu /storage layout to cemu-storage-adapter.sh"
grep -q 'bootstrap_session_portals' "$ROOT/launchers/start_cemu_guest.sh" \
  || fail "start_cemu_guest.sh must prewarm session portals before wxGTK startup"
grep -q 'dbus-update-activation-environment --systemd' "$ROOT/launchers/start_cemu_guest.sh" \
  || fail "start_cemu_guest.sh must import the Sway env for D-Bus activation"
grep -q 'rocknix-portal-bootstrap' "$ROOT/profiles/main-space.nix" \
  || fail "main-space profile must bootstrap xdg-desktop-portal from the Sway session"
grep -q 'exec_always ${portalBootstrap}' "$ROOT/profiles/main-space.nix" \
  || fail "main-space sway config must run the portal bootstrap after compositor startup"
grep -q 'XDG_CURRENT_DESKTOP = "sway"' "$ROOT/profiles/main-space.nix" \
  || fail "sway kiosk service must identify the desktop for portal backend selection"
grep -q 'CEMU_DEFAULT_SETTINGS' "$ROOT/launchers/cemu-storage-adapter.sh" \
  || fail "cemu-storage-adapter.sh must own fresh-state settings seeding"
grep -q 'normalize_audio_settings' "$ROOT/launchers/cemu-storage-adapter.sh" \
  || fail "cemu-storage-adapter.sh must normalize stale Cemu audio device settings"
grep -q 'bak.audio' "$ROOT/launchers/cemu-storage-adapter.sh" \
  || fail "cemu-storage-adapter.sh must back up settings before audio migration"
grep -q '<TVDevice></TVDevice>' "$ROOT/launchers/cemu-storage-adapter.sh" \
  || fail "Cemu audio migration must clear stale TV device IDs"
grep -q 'cemu-sm8550-performance.sh' "$ROOT/launchers/botw-guest.sh" \
  || fail "botw-guest.sh must delegate SM8550 performance policy"
grep -q 'quote_for_sway_exec' "$ROOT/launchers/botw-guest.sh" \
  || fail "botw-guest.sh must quote ROM/CEMU_BIN values passed through swaymsg exec"
grep -q 'env CEMU_BIN=' "$ROOT/launchers/botw-guest.sh" \
  || fail "botw-guest.sh must preserve candidate CEMU_BIN overrides across swaymsg exec"
! grep -q 'P3_MAX=\|GPU_MIN=\|taskset -p' "$ROOT/launchers/botw-guest.sh" \
  || fail "botw-guest.sh must not own CPU/GPU/affinity policy directly"
grep -q 'AFFINITY_MASK="${CEMU_AFFINITY_MASK:-0xF8}"' "$ROOT/launchers/cemu-sm8550-performance.sh" \
  || fail "cemu-sm8550-performance.sh must own default Cemu big-core affinity policy"
grep -q 'temporary host adapter' "$ROOT/launchers/host-tune.sh" \
  || fail "host-tune.sh must document temporary host-adapter status"
for cemu_remote in remote-cemu-build-fingerprint.sh remote-cemu-cleanup.sh remote-cemu-runner.sh remote-cemu-runtime-ab.sh remote-cemu-promote.sh; do
  grep -q 'GUEST_SERVICE="${ROCKNIX_GUEST_SERVICE:-rocknix-guest.service}"' "$ROOT/launchers/$cemu_remote" \
    || fail "$cemu_remote must default to current rocknix-guest.service with override"
done
grep -q 'pactl list sink-inputs short' "$ROOT/launchers/remote-cemu-runner.sh" \
  || fail "remote Cemu runner must collect Pulse/PipeWire sink-input evidence"
grep -q 'cubeb-backend-evidence.txt' "$ROOT/launchers/remote-cemu-build-fingerprint.sh" \
  || fail "Cemu build fingerprint must report Cubeb backend evidence"
grep -q 'remote-cemu-import.sh' "$ROOT/launchers/remote-cemu-promote.sh" \
  || fail "Cemu promotion help must point to candidate closure import helper"

# Package contracts migrated from the former package-only repo.
grep -F -q 'exec "\$cemu_wrapper_dir/Cemu"' "$REPO_ROOT/packages/cemu/package.nix" \
  || fail "package wrapper must exec real Cemu binary"
grep -q 'vulkan_loader_lib_path=' "$REPO_ROOT/packages/cemu/package.nix" \
  || fail "package wrapper must own Vulkan loader path"
grep -q 'audio_backend_lib_path=' "$REPO_ROOT/packages/cemu/package.nix" \
  || fail "package wrapper must expose Pulse/ALSA backend library path for bundled Cubeb"
grep -q 'libpulseaudio' "$REPO_ROOT/packages/cemu/package.nix" \
  || fail "Cemu package must include Pulse headers/runtime for bundled Cubeb"
grep -q 'alsa-lib' "$REPO_ROOT/packages/cemu/package.nix" \
  || fail "Cemu package must include ALSA headers/runtime for bundled Cubeb fallback"
grep -q 'USE_PULSE' "$REPO_ROOT/packages/cemu/package.nix" \
  || fail "Cemu package must gate on bundled Cubeb Pulse backend evidence"
grep -q 'USE_ALSA' "$REPO_ROOT/packages/cemu/package.nix" \
  || fail "Cemu package must gate on bundled Cubeb ALSA backend evidence"
grep -q 'cubeb_pulse.c' "$REPO_ROOT/packages/cemu/package.nix" \
  || fail "Cemu package must prove bundled Cubeb Pulse source was compiled"
grep -q 'cubeb_alsa.c' "$REPO_ROOT/packages/cemu/package.nix" \
  || fail "Cemu package must prove bundled Cubeb ALSA source was compiled"
grep -q 'cubeb-backend-evidence.txt' "$REPO_ROOT/packages/cemu/package.nix" \
  || fail "Cemu package must persist Cubeb backend evidence"
grep -q 'cubeb-backend-strings.txt' "$REPO_ROOT/packages/cemu/package.nix" \
  || fail "Cemu package must persist Cubeb runtime string evidence"
grep -q 'SDL_VIDEO_ALLOW_SCREENSAVER' "$REPO_ROOT/packages/cemu/package.nix" \
  || fail "package wrapper must own SDL screensaver guard"
grep -q 'ROCKNIX cemu-sa package contract' "$REPO_ROOT/packages/cemu/manifest.nix" \
  || fail "Cemu manifest must document ROCKNIX package contract source"

grep -q 'ROCKNIX Steam ARM64 guest-native package contract' "$REPO_ROOT/packages/steam/manifest.nix" \
  || fail "Steam manifest must document ROCKNIX package contract source"
grep -q 'rev = "[0-9a-f]\{40\}"' "$REPO_ROOT/packages/steam/manifest.nix" \
  || fail "Steam manifest must record pinned ROCKNIX source revision"
grep -q 'guest-native-steam-target=true' "$REPO_ROOT/packages/steam/package.nix" \
  || fail "Steam package evidence must target guest-native Steam"
grep -q 'host-steam-fallback=false' "$REPO_ROOT/packages/steam/package.nix" \
  || fail "Steam package must not fall back to host Steam"
grep -q 'immutable-nix-store-valve-arm64-seed-artifacts=false' "$REPO_ROOT/packages/steam/package.nix" \
  || fail "Steam v1 package must not claim immutable Nix-store Valve ARM64 seed artifacts"
grep -q 'steam-arm64-bootstrap' "$REPO_ROOT/packages/steam/package.nix" \
  || fail "Steam package must install bootstrap helper"
grep -q 'steam-arm64-seed' "$REPO_ROOT/packages/steam/package.nix" \
  || fail "Steam package must install ARM64 seed helper"
grep -q 'steam-guest-native' "$REPO_ROOT/packages/steam/package.nix" \
  || fail "Steam package must install guest-native launcher helper"
grep -q 'steam-guest-runtime-prep' "$REPO_ROOT/packages/steam/package.nix" \
  || fail "Steam package must install runtime prep helper"
grep -q 'steam-guest-run' "$REPO_ROOT/packages/steam/package.nix" \
  || fail "Steam package must install run capsule helper"
grep -q 'steam-arm64-fhs' "$REPO_ROOT/packages/steam/package.nix" \
  || fail "Steam package must define the aarch64 FHS run capsule"
grep -q 'STEAM_HOME' "$REPO_ROOT/packages/steam/scripts/steam-arm64-bootstrap" \
  || fail "Steam bootstrap helper must require explicit STEAM_HOME"
grep -q 'STEAM_GAMES_ROOT' "$REPO_ROOT/packages/steam/scripts/steam-arm64-bootstrap" \
  || fail "Steam bootstrap helper must require explicit STEAM_GAMES_ROOT"
grep -q 'STEAM_DOT' "$REPO_ROOT/packages/steam/scripts/steam-arm64-bootstrap" \
  || fail "Steam bootstrap helper must require explicit STEAM_DOT"
grep -q -- '--dry-run' "$REPO_ROOT/packages/steam/scripts/steam-arm64-bootstrap" \
  || fail "Steam bootstrap helper must support dry-run mode"
grep -q 'STEAM_MANIFEST_URL' "$REPO_ROOT/packages/steam/scripts/steam-arm64-seed" \
  || fail "Steam seed helper must know the ARM64 client manifest endpoint"
grep -q 'steamrtarm64/steam' "$REPO_ROOT/packages/steam/scripts/steam-guest-native" \
  || fail "Steam guest-native helper must execute the ARM64 Steam client"
grep -q 'NIX_LD' "$REPO_ROOT/packages/steam/scripts/steam-guest-native" \
  || fail "Steam guest-native helper must preflight NixOS dynamic linker strategy"
grep -q 'FEX_ROOTFS' "$REPO_ROOT/packages/steam/scripts/steam-guest-runtime-prep" \
  || fail "Steam runtime prep helper must preserve FEX wrapper semantics"
grep -q 'steamrtarm64' "$REPO_ROOT/packages/steam/scripts/steam-guest-run" \
  || fail "Steam run capsule helper must execute the mutable ARM64 Steam client"
grep -q 'options.rocknix.steam' "$ROOT/modules/steam.nix" \
  && grep -q 'package = lib.mkOption' "$ROOT/modules/steam.nix" \
  || fail "Steam module must consume the package through an explicit option"
! grep -q 'rocknix-steam-prepare-runtime' "$ROOT/modules/steam.nix" \
  || fail "Steam module must not embed runtime prep implementation"
! grep -q 'buildFHSEnv' "$ROOT/modules/steam.nix" \
  || fail "Steam module must not own the FHS Steam run capsule"
for resource in compatibilitytool.vdf registry.vdf toolmanifest.vdf; do
  [ -f "$REPO_ROOT/packages/steam/resources/${resource}" ] \
    || fail "Steam resource missing: ${resource}"
done

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck "$REPO_ROOT/packages/steam/scripts/steam-arm64-bootstrap" \
    "$REPO_ROOT/packages/steam/scripts/steam-arm64-seed" \
    "$REPO_ROOT/packages/steam/scripts/steam-guest-native" \
    "$REPO_ROOT/packages/steam/scripts/steam-guest-runtime-prep" \
    "$REPO_ROOT/packages/steam/scripts/steam-guest-run"
fi

bash "$REPO_ROOT/packages/steam/tests/steam-package-contract.sh"
bash "$REPO_ROOT/packages/steam/tests/steam-guest-runtime-prep-smoke.sh"
bash "$REPO_ROOT/packages/steam/tests/steam-guest-run-smoke.sh"

! grep -R 'systemctl\|swaymsg\|FEXRootFSFetcher\|gamescope\|/storage' \
  "$REPO_ROOT/packages/steam/package.nix" "$REPO_ROOT/packages/steam/scripts" >/tmp/rocknix-nix-guest-steam-boundary-grep.$$ \
  || { cat /tmp/rocknix-nix-guest-steam-boundary-grep.$$ >&2; rm -f /tmp/rocknix-nix-guest-steam-boundary-grep.$$; fail "Steam package executable logic must not own ROCKNIX host/session/storage policy"; }
rm -f /tmp/rocknix-nix-guest-steam-boundary-grep.$$

grep -q 'packages/cemu' "$ROOT/README.md" \
  || fail "README must document in-repo Cemu package"
grep -q 'packages/steam' "$ROOT/README.md" \
  || fail "README must document in-repo Steam package"
grep -q 'free of default passwords' "$ROOT/README.md" \
  || fail "README must document credential boundary"


# ==========================================================================
# Host<->guest contract assertions (moved from rocknix host repo
# projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh
# when the contract docs themselves were centralized here under docs/contracts/).
# These guarantee the docs continue to publish the textual contracts the host
# nix-integration build depends on.
# ==========================================================================
# When this guest flake is evaluated as a standalone Nix flake, the parent
# product docs are outside the flake source and these assertions are skipped;
# product-repo preflight runs the same script from a full checkout and exercises them.
if [ -n "${DOCS_ROOT}" ]; then
[ -f "$DOCS_ROOT/contracts/layer6-activation-contract.md" ] || fail "missing Layer 6 activation contract doc"
grep -q '/storage/bin' "$DOCS_ROOT/contracts/layer6-activation-contract.md" || fail "Layer 6 contract missing storage bin surface"
grep -q '/storage/.config/profile.d' "$DOCS_ROOT/contracts/layer6-activation-contract.md" || fail "Layer 6 contract missing profile.d surface"
[ -f "$DOCS_ROOT/contracts/layer7-app-experiment-contract.md" ] || fail "missing Layer 7 app experiment contract doc"
grep -q 'standard `nix profile`' "$DOCS_ROOT/contracts/layer7-app-experiment-contract.md" || fail "Layer 7 contract missing standard nix profile split"
grep -q '/storage/.local/share/nix-apps/layer7' "$DOCS_ROOT/contracts/layer7-app-experiment-contract.md" || fail "Layer 7 contract missing safe app state root"
grep -q '/storage/.cache/nix-apps/layer7' "$DOCS_ROOT/contracts/layer7-app-experiment-contract.md" || fail "Layer 7 contract missing safe app cache root"
grep -q 'Nix-backed binary' "$DOCS_ROOT/contracts/layer7-app-experiment-contract.md" || fail "Layer 7 contract missing Nix-backed binary proof"
[ -f "$DOCS_ROOT/contracts/layer9-nspawn-guest-contract.md" ] || fail "missing Layer 9 nspawn guest contract doc"
grep -q '/storage/machines/rocknix-guest' "$DOCS_ROOT/contracts/layer9-nspawn-guest-contract.md" || fail "Layer 9 contract missing guest root path"
grep -q '/dev/dri' "$DOCS_ROOT/contracts/layer9-nspawn-guest-contract.md" || fail "Layer 9 contract missing GPU passthrough prohibition"
grep -q 'PipeWire' "$DOCS_ROOT/contracts/layer9-nspawn-guest-contract.md" || fail "Layer 9 contract missing audio passthrough prohibition"
grep -q '/dev/input' "$DOCS_ROOT/contracts/layer9-nspawn-guest-contract.md" || fail "Layer 9 contract missing input passthrough prohibition"
grep -q 'Fallback does' "$DOCS_ROOT/contracts/layer9-nspawn-guest-contract.md" || fail "Layer 9 contract missing fallback boundary"
grep -q 'Guest state can be stopped and removed without touching host Nix state' "$DOCS_ROOT/contracts/layer9-nspawn-guest-contract.md" || fail "Layer 9 contract missing cleanup boundary"
[ -f "$DOCS_ROOT/contracts/layer10-guest-lifecycle-contract.md" ] || fail "missing Layer 10 guest lifecycle contract doc"
grep -q '/storage/.config/nix-integration/layer10' "$DOCS_ROOT/contracts/layer10-guest-lifecycle-contract.md" || fail "Layer 10 contract missing state dir path"
grep -q '/storage/machines/rocknix-guest' "$DOCS_ROOT/contracts/layer10-guest-lifecycle-contract.md" || fail "Layer 10 contract missing guest root path"
grep -q -- '--register=no' "$DOCS_ROOT/contracts/layer10-guest-lifecycle-contract.md" || fail "Layer 10 contract missing no-machined nspawn flag"
grep -q 'machinectl' "$DOCS_ROOT/contracts/layer10-guest-lifecycle-contract.md" || fail "Layer 10 contract missing no machinectl dependency"
grep -q 'proof' "$DOCS_ROOT/contracts/layer10-guest-lifecycle-contract.md" || fail "Layer 10 contract missing proof rootfs mode"
grep -q 'bootable' "$DOCS_ROOT/contracts/layer10-guest-lifecycle-contract.md" || fail "Layer 10 contract missing bootable rootfs mode"
grep -q 'must not call `systemctl enable`' "$DOCS_ROOT/contracts/layer10-guest-lifecycle-contract.md" || fail "Layer 10 contract missing no-autostart policy"
grep -q '/dev/dri' "$DOCS_ROOT/contracts/layer10-guest-lifecycle-contract.md" || fail "Layer 10 contract missing GPU passthrough prohibition"
grep -q 'PipeWire' "$DOCS_ROOT/contracts/layer10-guest-lifecycle-contract.md" || fail "Layer 10 contract missing audio passthrough prohibition"
grep -q '/dev/input' "$DOCS_ROOT/contracts/layer10-guest-lifecycle-contract.md" || fail "Layer 10 contract missing input passthrough prohibition"
grep -q 'Layer 10b bootable rootfs artifact boundary' "$DOCS_ROOT/contracts/layer10-guest-lifecycle-contract.md" || fail "Layer 10 contract missing Layer 10b bootable artifact boundary"
grep -q 'source/provenance, sha256, imported timestamp' "$DOCS_ROOT/contracts/layer10-guest-lifecycle-contract.md" || fail "Layer 10b contract missing provenance/checksum metadata rule"
grep -q 'must not depend on binding host `/nix`' "$DOCS_ROOT/contracts/layer10-guest-lifecycle-contract.md" || fail "Layer 10b contract missing first-validation host /nix sharing prohibition"
grep -q 'no guest SSH, password login, default credentials' "$DOCS_ROOT/contracts/layer10-guest-lifecycle-contract.md" || fail "Layer 10b contract missing guest SSH/default credential prohibition"
grep -q 'minimal init fixture.*not sufficient hardware evidence' "$DOCS_ROOT/contracts/layer10-guest-lifecycle-contract.md" || fail "Layer 10b contract must distinguish fixtures from hardware Go"
[ -f "$DOCS_ROOT/contracts/layer11-bridge-contract.md" ] || fail "missing Layer 11 bridge contract doc"
grep -q '/storage/.config/nix-integration/layer11' "$DOCS_ROOT/contracts/layer11-bridge-contract.md" || fail "Layer 11 contract missing state dir path"
grep -q '/storage/bin' "$DOCS_ROOT/contracts/layer11-bridge-contract.md" || fail "Layer 11 contract missing storage bin target surface"
grep -q 'nixctl guest run' "$DOCS_ROOT/contracts/layer11-bridge-contract.md" || fail "Layer 11 contract missing Layer 10 guest run dependency"
grep -q 'one-shot bridges only' "$DOCS_ROOT/contracts/layer11-bridge-contract.md" || fail "Layer 11 contract missing one-shot scope"
grep -q 'must not.*guest SSH' "$DOCS_ROOT/contracts/layer11-bridge-contract.md" || fail "Layer 11 contract missing guest SSH prohibition"
grep -q 'must not.*systemd service' "$DOCS_ROOT/contracts/layer11-bridge-contract.md" || fail "Layer 11 contract missing no service/autostart policy"
grep -q '/dev/input' "$DOCS_ROOT/contracts/layer11-bridge-contract.md" || fail "Layer 11 contract missing input passthrough prohibition"
grep -q 'no guest process remains' "$DOCS_ROOT/contracts/layer11-bridge-contract.md" || fail "Layer 11 contract missing no residual guest process rule"
grep -q 'Cemu compatibility state' "$DOCS_ROOT/contracts/layer14-main-space-contract.md" \
  || fail "layer14 main-space contract must document Cemu compatibility state ownership"
grep -q 'guest-owned runtime peelback baseline' "$DOCS_ROOT/solutions/performance-issues/rocknix-layer14-cemu-performance-audit-2026-05-09.md" \
  || fail "Cemu performance audit must document guest-owned peelback baseline"
L14_FALLBACK_DOC="$DOCS_ROOT/contracts/HOW-TO-FALL-BACK.md"
[ -f "${L14_FALLBACK_DOC}" ] || fail "missing HOW-TO-FALL-BACK.md (U9)"
grep -q '/flash/rocknix.no-nspawn' "${L14_FALLBACK_DOC}" \
  || fail "HOW-TO-FALL-BACK.md missing flag-file recovery instructions (U9)"
grep -q 'rocknix.safe=1' "${L14_FALLBACK_DOC}" \
  || fail "HOW-TO-FALL-BACK.md missing kernel cmdline recovery instructions (U9)"

# U10: Layer 14 contract doc.
L14_CONTRACT="$DOCS_ROOT/contracts/layer14-main-space-contract.md"
[ -f "${L14_CONTRACT}" ] || fail "missing Layer 14 contract doc (U10)"
! grep -q 'THIN_HOST' "${L14_CONTRACT}" \
  || fail "Layer 14 contract must not document removed THIN_HOST build flag (U10)"
grep -q 'rocknix-guest.service' "${L14_CONTRACT}" \
  || fail "Layer 14 contract must document the guest unit (U10)"
grep -q 'rocknix-guest-promote.service' "${L14_CONTRACT}" \
  || fail "Layer 14 contract must document guest promotion service (U10)"
grep -q 'no `ExecStopPost=` fallback/reclaim hook' "${L14_CONTRACT}" \
  || fail "Layer 14 contract must document removal of automatic host reclaim (U10)"
grep -q 'soak' "${L14_CONTRACT}" \
  || fail "Layer 14 contract must document the soak gate (U10)"
grep -q 'rocknix-guest-revision' "${L14_CONTRACT}" \
  || fail "Layer 14 contract must document guest revision markers (U10)"
grep -q 'SM8550' "${L14_CONTRACT}" \
  || fail "Layer 14 contract must document SM8550-only scope (U10)"
grep -q 'downstream product consumption' "${L14_CONTRACT}" \
  || fail "Layer 14 contract must document downstream product consumption"
grep -q 'Korri consumes nix-on-rocks' "${L14_CONTRACT}" \
  || fail "Layer 14 contract must document Korri as downstream consumer"
grep -q 'Do not add a ROCKNIX-owned Korri package, Korri flake input' "${L14_CONTRACT}" \
  || fail "Layer 14 contract must document the Korri ownership boundary"
! grep -q 'korri.nixosModules\|services.korri.package\|Home then `k`' "${L14_CONTRACT}" \
  || fail "Layer 14 contract must not document removed nix-on-rocks Korri composition"
else
  printf 'skipping product doc assertions: docs root is outside this flake source\n'
fi

printf 'static checks passed\n'
