# Layer 14 — Nix main-space contract

## Goal

SM8550 ROCKNIX boots a NixOS guest as the primary product experience while
ROCKNIX remains the minimal host substrate for boot, update, rollback, and
explicit recovery. The guest owns product UX: display, audio, input handling,
networking policy, product launch policy, Cemu and product launchers, and
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
- `rocknix-guest-promote.service` applies the packaged product revision to the
  persistent guest rootfs after the old guest boots: it stages
  `/usr/lib/rocknix-guest-substrate/guest` under
  `/storage/nix-on-rock/staging/guest-exchange`, builds the configured product
  target inside the guest namespace with `--impure`, updates the selected guest
  system profile, records `/etc/rocknix-guest-revision`, and restarts the guest
  once so PID 1 boots the promoted generation.
- The default host-promoter entry point is the product build target pinned in
  the installed `product-payload.env` (rendered from the per-product
  `product-payload-<product>.lock`). The product authority's by-compatible
  appliance target reads the normalized `/proc/device-tree/compatible` value
  from the running device through its nix-on-rocks substrate input and selects
  the matching profile from nix-on-rocks' `deviceProfileByCompatible` table.
  The host substrate must not maintain a parallel device list. Off-device
  evaluation must use the product authority's explicit per-device attributes;
  the by-compatible attribute throws a clear error when the compatible string
  is absent.
- `rocknix-recovery-toggle.service` is the explicit safety net: `/flash/rocknix.no-nspawn`
  or `rocknix.safe=1` routes boot to the legacy ROCKNIX target.
- Guest NixOS modules own substrate behavior: display/Sway, audio/PipeWire,
  WirePlumber, NetworkManager, hardware buttons/lid, and Cemu package/launcher
  support. Product/appliance composition imports the substrate contract and owns
  product service selection downstream.

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
5. Build the configured product target read from the installed `product-payload.env` (the lock's `PRODUCT_BUILD_TARGET`).
6. Set `/nix/var/nix/profiles/per-user/root/rocknix-guest-system` to the built toplevel.
7. Write applied revision and system-path markers under guest `/etc`.
8. Restart `rocknix-guest.service` once so the new guest generation boots.

This makes ROCKNIX image updates carry product guest fixes into the persistent
guest without manual `nixos-rebuild` steps on-device. `ROCKNIX_GUEST_BUILD_TARGET`
can override the target for proof runs, but the helper refuses the retired
nix-on-rocks by-compatible product target.

`product-payload.lock` characterizes the current packaged product payload before
Docker work begins. In Phase 1 it mirrors the product authority source pin, build
target, and accepted rootfs seed already hardcoded in patched `package.mk`; the image
path still consumes `package.mk` from `patches/rocknix/0006-rocknix-guest-substrate.patch`.
`scripts/verify-product-payload` renders the generic lock to `PKG_NIX_GUEST_*`
values and fails if the mirror, `guest.lock`, or patched package metadata drift.
Downstream products still consume nix-on-rocks; nix-on-rocks must not import a
downstream product flake to satisfy this contract.

### Boot-splash branding seam

The boot splash is product branding and rides the product payload, not the
substrate patch queue. The per-product lock may pin an optional branding
asset with three fields (all-empty means "no product branding"; the image
keeps the upstream ROCKNIX splash):

- `PRODUCT_BRANDING_SPLASH_PATCH_ARCHIVE` — release asset name of a unified
  diff against the `rocknix-splash` renderer `main.c` (SVG path data plus
  color palette).
- `PRODUCT_BRANDING_SPLASH_PATCH_SHA256` — digest of the patch bytes.
- `PRODUCT_BRANDING_SPLASH_PATCH_URL` — direct product-authority release
  download URL. May stay empty only when the patch is supplied locally via
  `NIX_ON_ROCKS_BRANDING_SPLASH_PATCH=<path>` at patch-staging time.

`scripts/apply-rocknix-patches` fetches the pinned patch (or copies the
local override), verifies the digest, and stages it as
`projects/ROCKNIX/packages/tools/rocknix-splash/patches/rocknix-splash-0001-product-boot-logo.patch`
so the ROCKNIX build applies it like any package patch. When no branding is
pinned the staging step removes any stale staged patch.
`scripts/verify-product-payload` fails if a pinned patch is missing or
drifted, or if an unpinned product leaves a stray staged patch behind.
`scripts/check-boundary-lint` asserts the substrate patch queue itself
carries no product wordmark or palette. The substrate never knows which
product the branding belongs to; it only enforces the pinned bytes.

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

## Substrate contract and downstream product consumption

`nixosModules.rocknix-guest-base` is the product-blind downstream import
contract. It imports the SM8550 guest modules, device/runtime plumbing,
Moonlight support, and the root session D-Bus service without importing product
modules or setting product service options. Product-specific application
runtimes are downstream-owned; the substrate keeps only neutral device/session
anchors. Substrate unit ordering names only substrate-owned units (the
`main-space-*` services); a downstream product orders its own session units
after the substrate anchors from its side. The substrate must not name product
units.

The downstream product consumes nix-on-rocks by importing
`nixosModules.rocknix-guest-base`, a specific SM8550 device profile, and
substrate package outputs from its own flake. The product owns kiosk appliance
composition, product launch chords, client packaging, bridge configuration,
and rootfs artifact publication.

ROCKNIX owns only the guest/session runtime environment a downstream product
needs to start: `HOME=/storage`, `XDG_RUNTIME_DIR=/run/user/<uid>` (with the
UID parameterized by `rocknix.session.runtimeDir.uid`, defaulting to `0`; the
substrate-owned `main-space-runtime-dir.service` anchors all main-space
consumers behind logind's per-uid `user-runtime-dir@<uid>.service` so the
session tmpfs is mounted before any socket is written), the root session
D-Bus socket, PipeWire/Pulse, display/input/audio/device binds, and Sway launch
policy. Do not add a ROCKNIX-owned product package, product flake input, or
duplicate product-owned configuration options here. Legacy nix-on-rocks
product-consuming outputs have been removed after native arm64 rootfs
verification and the executable promotion proof.

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
