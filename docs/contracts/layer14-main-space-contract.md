# Layer 14 — Nix main-space contract

## Goal

SM8550 ROCKNIX boots a NixOS guest as the primary product experience while
ROCKNIX remains the minimal host substrate for boot, update, rollback, and
explicit recovery. The guest owns product UX: display, audio, input handling,
networking policy, Korri launch policy, Steam/Cemu launchers, and
guest-specific documentation.

## Current contract

In:

- Host installs `rocknix-guest.service`, a narrow `systemd-nspawn` unit for
  `/storage/nix-on-rock/rootfs/current`.
- Host default target is `rocknix-main-space.target` on SM8550. That target pulls
  in the guest and the packaged guest promotion service.
- Host binds only the resources the guest needs: DRM, sound, input, tty, rfkill,
  selected sysfs controls, the scrubbed guest udev DB, and the single
  nix-on-rock exchange directory exposed inside the guest as `/storage/.guest`
  during the compatibility window.
- Host does **not** broad-bind `/usr`, `/lib`, `/etc/profile`, `/etc/resolv.conf`,
  or all of `/storage`.
- `rocknix-guest-prep` repairs the persistent guest rootfs before launch:
  `/init` links, guest `/run/current-system` expectations, the guest-visible
  `/storage/.guest` compatibility mountpoint, and the guest-owned resolv.conf
  marker.
- `rocknix-guest-udev-stage` stages a scrubbed `/run/udev` copy so hidden
  InputPlumber devices do not poison guest libseat/wlroots startup.
- `rocknix-guest-promote.service` applies the packaged guest revision to the
  persistent guest rootfs after the old guest boots: it stages
  `/usr/lib/rocknix-guest-substrate/guest` under
  `/storage/nix-on-rock/staging/guest-exchange`, builds
  `rocknix-guest-main-space-by-compatible` inside the guest namespace with
  `--impure`, updates the selected guest system profile, records
  `/etc/rocknix-guest-revision`, and restarts the guest once so PID 1 boots
  the promoted generation.
- The `rocknix-guest-main-space-by-compatible` flake attribute is the
  host-promoter entry point. It reads `/proc/device-tree/compatible` from
  the running device (visible inside the guest namespace) and selects the
  matching profile from the `deviceProfileByCompatible` table in `flake.nix`.
  Adding a new SM8550 device is a single-PR change in this repo: add
  `profiles/devices/<device>.nix` and one entry mapping the device's first
  device-tree `compatible` string to that profile. The host substrate must
  not maintain a parallel device list. Off-device evaluation must use the
  explicit `rocknix-guest-main-space-<device>` attributes; the by-compatible
  attribute throws a clear error pointing at them when
  `/proc/device-tree/compatible` is absent.
- `rocknix-recovery-toggle.service` is the explicit safety net: `/flash/rocknix.no-nspawn`
  or `rocknix.safe=1` routes boot to the legacy ROCKNIX target.
- Guest NixOS modules own main-space behavior: display/Sway, audio/PipeWire,
  WirePlumber, NetworkManager, hardware buttons/lid, Korri frontend consumption,
  Steam helpers, Cemu package and launchers.

Out:

- Automatic legacy host UI reclaim after guest failure. `rocknix-guest.service`
  may restart the guest via `Restart=on-failure`; if it remains broken, recovery
  is explicit via `/flash/rocknix.no-nspawn` or `rocknix.safe=1`.
- Backwards-compatible host Nix CLIs, host nix-daemon, host PATH hooks, Layer 13
  host modules, and legacy thin-host build variants.
- Non-SM8550 support for this substrate.
- Broad host mutation outside normal ROCKNIX image/update flow.

## Host unit shape

`rocknix-guest.service`:

- `ExecStartPre=/usr/bin/rocknix-guest-prep`
- `ExecStartPre=/usr/bin/rocknix-guest-udev-stage`
- `ExecStart=/usr/bin/systemd-nspawn --machine=rocknix-guest --directory=/storage/nix-on-rock/rootfs/current --boot --register=no --keep-unit ...`
- `Restart=on-failure`
- no `ExecStopPost=` fallback/reclaim hook
- `WantedBy=rocknix-main-space.target`

`rocknix-guest-promote.service`:

- `After=rocknix-guest.service`
- `Wants=rocknix-guest.service`
- `ExecStart=/usr/bin/rocknix-guest-promote`
- `TimeoutStartSec=60min`
- `WantedBy=rocknix-main-space.target`

The promotion helper intentionally enters the already-running guest namespace
rather than trying to mutate host `/usr` or `/storage/nix-on-rock/rootfs/current`
from the host. It uses explicit `/run/current-system/sw/bin/...` paths inside
the guest and `sh -c` (not a login shell) to avoid host/guest logout hooks.

## Boot decision tree

```text
power-on -> ROCKNIX host -> rocknix-recovery-toggle.service
   |
   |- /flash/rocknix.no-nspawn exists -> rocknix.target  (explicit recovery)
   |- rocknix.safe=1 on cmdline       -> rocknix.target  (one-boot recovery)
   |- otherwise                       -> rocknix-main-space.target
                                            |
                                            |- rocknix-guest.service
                                            |- rocknix-guest-promote.service
```

## Guest promotion lifecycle

ROCKNIX image updates replace `/usr/lib/rocknix-guest-substrate/guest`, but the running
NixOS rootfs lives persistently under `/storage/nix-on-rock/rootfs/current`. The
host therefore carries two revision markers:

- Packaged revision: `/usr/lib/rocknix-guest-substrate/guest-revision`
- Applied revision: `/storage/nix-on-rock/rootfs/current/etc/rocknix-guest-revision`

If the markers match, promotion exits without changing the guest. If they differ:

1. Copy the packaged guest source to `/storage/nix-on-rock/staging/guest-exchange/rocknix-nix-guest-packaged`.
2. Run guest repo static checks from the staged source.
3. Enter the running guest namespace via the `systemd-nspawn` payload PID.
4. Wait for guest `NetworkManager.service` so Nix can fetch/substitute.
5. Build `.#nixosConfigurations.rocknix-guest-main-space-by-compatible.config.system.build.toplevel`.
6. Set `/nix/var/nix/profiles/per-user/root/rocknix-guest-system` to the built toplevel.
7. Write applied revision and system-path markers under guest `/etc`.
8. Restart `rocknix-guest.service` once so the new guest generation boots.

This makes ROCKNIX image updates carry guest repo fixes into the persistent guest
without manual `nixos-rebuild` steps on-device.

## Recovery contract

Two override mechanisms have OR semantics:

1. Sticky flag file: `/flash/rocknix.no-nspawn`.
2. Per-boot kernel cmdline: `rocknix.safe=1`.

Either toggle present routes boot to ROCKNIX recovery. Both absent routes to
Nix main-space. Recovery is explicit; the host does not automatically restart
legacy Sway/EmulationStation when the guest crashes.

## Soak gate

`rocknix-guest-soak` samples the current main-space invariants:

1. Guest resolv.conf ownership marker exists.
2. Guest `/etc/resolv.conf` is not clobbered by host resolvconf.
3. Guest `/run/current-system` resolves.
4. Guest PATH does not contain raw host `/usr/bin`/`/usr/sbin`.
5. Guest Sway is alive.
6. Guest PipeWire/WirePlumber/Pulse bridge are alive.
7. Host SSH on `:22` remains responsive.
8. Memory stays within the expected budget.

Logs live under `/var/log/rocknix-guest-soak*.log`.

## Korri frontend consumption

Layer 14 consumes Korri through the Korri-owned flake API instead of carrying
Korri packaging logic in the ROCKNIX guest repo:

- `korri.nixosModules.korri-frontend` is imported into main-space.
- `services.korri.enable = true` installs the configured package.
- `services.korri.package = korri.packages.${targetSystem}.korri-desktop-odin`
  selects the available Odin desktop package variant that owns Korri's
  build-time frontend configuration, including the native bridge URL. Keep this
  explicit until Korri publishes a stable device alias.
- The Sway kiosk service PATH includes `config.services.korri.package` so Sway
  keybinds can launch the configured package binary.
- The main-space Sway Home chord launches Korri with Home then `k`.

ROCKNIX owns the guest/session runtime environment that Korri needs to start:
`HOME=/storage`, `XDG_RUNTIME_DIR=/run/user/0`, the root session D-Bus socket,
PipeWire/Pulse, display/input/audio/device binds, and Sway launch policy. Korri
owns the frontend package, Electrobun wrapper, module API, and build-time
frontend configuration. Do not add a ROCKNIX-owned Korri package or duplicate
Korri's native bridge URL option here.

## Cemu compatibility state

Layer 14 does not broad-bind `/storage`. Cemu-specific state is exposed through
narrow compatibility binds and normalized inside the guest by guest-owned
launchers/adapters:

- `/storage/.config/Cemu` — settings and seeded default settings destination.
- `/storage/.local` — historical `~/.local/share/Cemu` state visible with
  `HOME=/storage`.
- `/storage/roms/bios` — writable compatibility root for `online`, `mlc01`,
  and `keys`; this overrides the read-only `/storage/roms` bind for that
  sub-tree only.
- `/storage/.config/MangoHud` — validation overlay config.

This is a guest adapter contract, not a generic Cemu package contract. The
package-owned `bin/cemu` entry point owns package-relative runtime setup and
must stay free of `/storage`, BOTW, and SM8550 policy.

## Cemu SM8550 performance policy

Cemu performance controls live in the guest/session layer, not in the generic
package wrapper. `cemu-sm8550-performance.sh` owns measured SM8550 profiles for
CPU caps, best-effort GPU devfreq, and thread affinity. The guest Sway session
exports `CEMU_AFFINITY_MASK=0xF8` as the default big-core mask; validation
harnesses may set `CEMU_AFFINITY_MASK=none` for paired scheduler tests.

`host-tune.sh` remains a temporary host adapter for privileged sysfs controls
the guest cannot safely own yet, especially GPU devfreq writes. It must stay
explicit and validation-scoped; the Cemu package entry point must never learn
about SM8550 sysfs paths.

## Sibling profiles

- `dev-env` — interactive Sway session for on-device development. Same nspawn
  substrate, different guest profile. See `layer14-dev-env-profile.md`.

## Origin and references

- Predecessor contracts:
  - `layer10-guest-lifecycle-contract.md` — guest lifecycle
  - `layer12-guest-ssh-contract.md` — opt-in SSH on port 2222
  - `layer13-modules-contract.md` — declarative module evaluator
