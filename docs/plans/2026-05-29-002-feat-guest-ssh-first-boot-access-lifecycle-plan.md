---
title: "feat: Guest SSH first-boot access lifecycle"
type: feat
status: draft
date: 2026-05-29
related-acceptance: docs/acceptance/sm8550-product-payload-thor-bandai-2026-05-29.md
---

# feat: Guest SSH first-boot access lifecycle

## Summary

Guest SSH access today depends on operator keys that happen to already exist on the device. On the first Thor cutover (2026-05-29) the reseeded guest root contained no authorized keys at all, and the operator manually restored keys from the retained `previous/` root before guest SSH `:2222` was usable again. The Thor seed acceptance evidence explicitly flags this:

> Guest SSH keys are intentionally not shipped in the seed. This acceptance restored the prior operator keys from the retained previous root after reseed. Future substrate work should provide an explicit key-preservation/import path for product-seed reseeds.

This is acceptable on a single-operator developer device but is **not acceptable** for any user-facing deployment. It is also a design decision we should make once and write down, not solve ad-hoc per device.

This plan picks a first-boot SSH access model and ships it.

## Two distinct security questions

It is easy to conflate these. We must keep them separate.

### Q1 — Host keys (server identity)

Host keys are what the SSH server presents to clients to prove "I am really this device." If every guest ships the same baked-in host keys:

- Any one device owner can impersonate every other device on the same network or routed reachable from it.
- SSH's host-key warning becomes meaningless across the fleet.

**Required answer:** every guest generates its own host keys on first boot. Never ship them in the seed. NixOS `services.openssh` does this automatically when the host key paths do not already exist; the substrate just has to not pin them.

### Q2 — Authorized keys (who can log in)

Authorized keys decide who is allowed to log in as `root` to the guest.

Options, ordered roughly by security posture:

1. **SSH off by default.** Kiosk does not expose SSH. User opts in via product UI.
2. **SSH on, host keys per-device, `authorized_keys` empty.** User adds their own key via a product flow (UI pairing, QR scan, local console, USB ingestion).
3. **SSH on with a per-device random password printed somewhere** (first-boot screen, sticker, label). User changes it.
4. **SSH on with a developer/operator key baked in.** Current Korri authority posture. **Not acceptable** outside the single-operator case.

For Korri product images shipped to end users, **option 1 or option 2** is the only acceptable answer. Option 3 is an acceptable interim for early bring-up. Option 4 is a permanent backdoor risk and must be removed before any external distribution.

## Two consumers, two policies

The substrate is product-blind. The first-boot SSH policy is therefore product-shaped, not substrate-shaped.

- **Substrate** must guarantee per-device host keys (Q1) and provide the mechanism for the product to declare an SSH policy (Q2).
- **Korri product payload** picks the actual Q2 policy per build target.
- **Operator/developer mode** (this repo, sobo / our Thor) keeps the existing dev keys via a clearly labelled `payload.developer-access` knob that is **off** for any shippable build.

## Goal

After this plan:

1. The substrate provably generates per-device guest SSH host keys on first boot, and survives reseed without leaking host-key identity across devices or losing existing per-device identity.
2. The substrate exposes a documented `payload.guest-ssh` schema with at least three modes: `off`, `bring-your-own-key`, `developer-keys`.
3. Korri can declare its policy per product (odin2portal vs thor) in the product payload.
4. Reseed preserves the existing per-device host keys and previously authorized keys when policy says so, without manual file copying.
5. There is one short acceptance doc per supported mode.

## Non-goals

- Designing the user-facing product flow that ingests a user key. That is Korri product work and lives in a separate Korri plan.
- Changing host (Layer 14) SSH. Host SSH is already its own concern at port 22.
- Building a key-distribution server, pairing protocol, or PKI.
- Ship a UI for option 2 in this plan. The mechanism exists here; the UI is Korri-side follow-on.

## Approach

Six units. Substrate-side first, then Korri payload schema, then proof.

### U1 — Substrate: per-device host-key generation invariant

Document and enforce:

- Guest seed must not contain `/etc/ssh/ssh_host_*` keys. Build-time check.
- Guest first-boot must run host-key generation if keys are absent (already true via NixOS `services.openssh` defaults; pin this as an asserted invariant, not an implicit behavior).
- Host keys must live under a path that survives reseed (e.g. mounted from a per-device persistent location or explicitly preserved across `previous/` rotation).

Static-check assertions:

- The packaged seed does not contain `etc/ssh/ssh_host_*`.
- `services.openssh.enable` is `true` in `guest/profiles/main-space.nix` when SSH is enabled by policy (do not assume; assert from the rendered config).
- `services.openssh.hostKeys` paths point at the persistent location, not under the rootfs that gets rotated.

### U2 — Substrate: host-key preservation through reseed

The reseed flow already retains a `previous/` root. Extend `rocknix-guest-root-ensure` (or a sibling unit ordered before it) to:

- Before deleting `previous/`, harvest `previous/etc/ssh/ssh_host_*` into the persistent host-key location if the persistent copy is missing or older.
- On a fresh device with no previous root and no persistent keys, allow `services.openssh` to generate them on first boot.

Static-check assertions:

- Harvest runs before `previous/` delete.
- Harvest never copies host keys *out of* the persistent location into the new root in a way that would let another device clone identity.

### U3 — Substrate: `payload.guest-ssh` schema

Define a tiny declarative schema the product payload can set. Read by the substrate at seed-application time, written into the guest config:

```text
payload.guest-ssh.mode = "off" | "bring-your-own-key" | "developer-keys"
payload.guest-ssh.developer-keys = [ "ssh-ed25519 ..." ]   # only meaningful when mode = developer-keys
payload.guest-ssh.authorized-keys-source = "persistent" | "payload" | "none"
```

Behavior:

- `off`: `services.openssh.enable = false` in the rendered guest. Static check verifies the rendered config and the running unit list contain no `ssh.service`.
- `bring-your-own-key`: SSH on, `authorized_keys` empty in the seed, but a documented persistent path is honored on boot (e.g. `/storage/nix-on-rock/guest/authorized_keys` is copied or symlinked into `/root/.ssh/authorized_keys`). Operator/UI writes that file out-of-band.
- `developer-keys`: SSH on, the listed keys are written into `authorized_keys` on every boot. Big "this is a developer build" log line at boot.

The schema is declared in `docs/contracts/product-payload-contract.md` and validated by `scripts/tests/product-payload-contract.sh --product <id>`.

### U4 — Substrate: reseed-time authorized-keys preservation

Today the manual recovery was "copy authorized_keys from `previous/`." Make this declarative.

When `payload.guest-ssh.authorized-keys-source = persistent`:

- The persistent path (e.g. `/storage/nix-on-rock/guest/authorized_keys`) is the source of truth.
- On reseed, if the persistent path is missing but `previous/root/.ssh/authorized_keys` exists, the substrate harvests it forward into the persistent path **once**, and logs an `authorized-keys: migrated-from-previous` line.
- After harvest, persistent is canonical.

Static-check assertions:

- Migration code runs only when persistent is absent.
- Migration never overwrites a non-empty persistent file.
- Migration logs a single, greppable line.

### U5 — Korri product payload policy

Declare per-product Korri policy in the Korri repo (separate PR), referencing this contract:

- `korri-rocknix-kiosk-odin2portal`: `mode = developer-keys` (current behavior, explicit), with the developer key list pinned in the payload.
- `korri-rocknix-kiosk-thor`: same, for now, with a flagged `# TODO: switch to bring-your-own-key once UI ships` next to it.
- Future shippable Korri build target: `mode = bring-your-own-key`.

This is the only place the Korri-side change lands. No substrate change is required here; substrate U3 already accepts these values.

### U6 — Proof

- Local: `scripts/tests/product-payload-contract.sh --product odin2portal` and `--product thor` pass.
- Image-only CI for both products green.
- Device acceptance:
  - sobo: reseed with current `developer-keys` policy → guest SSH `:2222` works without manual operator action. Capture evidence.
  - sobo: synthetic switch to `bring-your-own-key` (test image only) → guest SSH refuses unknown key; operator writes persistent file; guest SSH accepts. Capture evidence.
  - sobo: synthetic switch to `off` → guest SSH refuses connection; host SSH still works. Capture evidence.
- Thor full re-acceptance is **not** required for this plan; one image-only build + sobo proves the substrate side. Thor inherits via its own payload.

## Validation summary

- 3 static-check additions (U1, U2, U4).
- 1 payload-contract schema change (U3).
- 1 Korri payload PR (U5).
- 1 substrate image-only CI cycle.
- 3 sobo device passes (U6).
- No full SM8550 build required.

## Risks

- **Reseed harvest is subtle.** Getting host-key handoff wrong could either lose identity (annoying) or leak identity between previous and replacement guest roots. Mitigation: keep host keys in a persistent location that is never inside any rootfs that gets rotated; harvest is a one-way migration that runs once, gated by "persistent absent."
- **`authorized_keys` migration could resurrect revoked keys.** Mitigation: migration runs once; subsequent rotations of `authorized_keys` happen in the persistent location only.
- **Developer-keys mode is a backdoor.** Acceptable while we are the only operators. Mitigation: large boot log line, contract assertion, and explicit `# DEVELOPER BUILD` field in the manifest.
- **Substrate ends up encoding product policy.** Mitigation: `payload.guest-ssh` is data, not behavior; the substrate only honors values, the product declares them.

## Open decisions for review

1. Persistent host-key path location. Candidates: `/storage/nix-on-rock/guest/ssh/`, `/flash/...` (no — flash is ro by default), `/storage/.ssh-host-keys/`. Recommendation: `/storage/nix-on-rock/guest/ssh/` to keep all guest persistent data co-located.
2. Should `developer-keys` mode also auto-emit a per-device random root password so a UI can recover access if SSH is hosed? Default: no, out of scope for this plan.
3. Do we need `authorized-keys-source = payload` (list of keys baked into payload, not persistent)? Default: no, payload-baked keys are the `developer-keys` mode in disguise. Keep the schema minimal.

## Lifecycle

`status: draft` → `status: active` after design review and decision on the open items → `status: completed` after U6 evidence lands.
