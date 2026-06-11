# Substrate product surface contract

This contract enumerates every substrate-owned name, path, and output shape
that a downstream product is allowed to consume. The substrate is
product-blind: it ships no product code, names no product units, and validates
product payloads only through the generic `PRODUCT_*` lock vocabulary. In the
other direction, a product may depend on the substrate — but only on the
surface listed here. Anything not listed is an internal detail the substrate
may rename or remove without notice; depending on it recreates the coupling
this contract exists to prevent.

When a name below must change, treat it as a breaking contract change: update
this document in the same commit and announce it so product flakes can adapt
before their next payload promotion.

## 1. Flake exports

- `nixosModules.rocknix-guest-base` — the product-blind guest base profile
  (also exported as `nixosModules.default`).
- `nixosModules.odin2portal`, `nixosModules.thor`, `nixosModules.rg353m` —
  device profiles.
- `lib.mkGuestRootfs` — packages a guest `nixosConfiguration` as a deployable
  rootfs artifact. Output shape (stable): a store path containing a `tarball/`
  directory with exactly one `*.tar.zst` archive inside it. Consumers must not
  assume the archive's file name beyond the `.tar.zst` suffix.
- `lib.selectDeviceProfileFromCompatible`, `lib.selectDeviceProfileFromIdentity`,
  `lib.deviceProfileByCompatible`, `lib.deviceProfileByModel`,
  `lib.deviceProfileKeyFromIdentity` — device-profile selection helpers for
  downstream flakes (on-device rebuild lanes).

## 2. Systemd unit names (main-space session)

The substrate-owned main-space units a product may order against, disable, or
replace are exactly:

- `main-space-runtime-dir.service`
- `main-space-session-dbus.service`
- `main-space-sway-kiosk.service` (fallback kiosk compositor)
- `main-space-pipewire.service`
- `main-space-pipewire-pulse.service`
- `main-space-wireplumber.service`

These names are stable. No other unit name is contract; in particular,
products must not depend on units that previously existed (for example a
removed audio bootstrap unit) — a disable of a nonexistent unit is a silent
no-op, and a dependency on one is a deploy failure. The substrate never orders
its units against product unit names; products declare their own ordering from
their side.

## 3. Guest generation promotion

The host promotion helper reads and writes the guest generation profile at:

- `/nix/var/nix/profiles/per-user/root/rocknix-guest-system`

A product activation script that records its own toplevel must use exactly
this path (see `layer14-main-space-contract.md` for the promotion sequence and
the packaged/applied revision markers).

## 4. Product payload seam

The only inbound product coupling the substrate accepts is the per-product
lock file `product-payload-<device>.lock` carrying the Phase 1 `PRODUCT_*`
vocabulary (authority repo, revision, source hash, build target, rootfs seed
archive/URLs/hash, optional branding splash patch archive/hash/URL). The
substrate validates these fields generically; their values are opaque data.
The optional branding asset must be a single unified-diff `.patch` file against
the `rocknix-splash` source, staged by `scripts/apply-rocknix-patches` and
verified by `scripts/verify-product-payload`.

## 5. Session environment guarantees

The guest base profile guarantees logind is running with
`user-runtime-dir@` managing `XDG_RUNTIME_DIR` (`/run/user/<uid>`); the
substrate fallback session runs as uid 0. Products that run their session
under a different uid own that user's creation, lingering, and runtime-dir
lifecycle themselves; the substrate does not reserve any product uid, user
name, or home directory layout beyond what `rocknix-guest-base` configures.
