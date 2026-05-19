---
title: refactor: Trim SM8550 minimal host after guest-owned UX
type: refactor
status: active
date: 2026-05-12
verify_command: "sh projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh"
---

# refactor: Trim SM8550 minimal host after guest-owned UX

**Target repo:** `rocknix`

## Summary

Trim the SM8550 ROCKNIX host down to the boot/update/recovery/container substrate now that the NixOS guest owns product UX. This plan removes host graphical/UI roots, host emulation packages, and host-owned Tailscale/WireGuard/netfilter extras while preserving host SSH, `/storage/.update/`, recovery toggles, `systemd-nspawn`, guest promotion, InputPlumber for the current guest input contract, and guest-owned Tailscale.

---

## Problem Frame

The current SM8550 minimal-host branch has proven the architecture: ROCKNIX can boot the guest as main-space, host SSH can remain available, and Tailscale can run inside the guest when the nspawn boundary passes `/dev/net/tun` and network capabilities. But recent full-build logs still show host-side `mesa`, `llvm`, `wlroots`, `sway`, `xwayland`, `mako-osd`, `bemenu`, emulator roots, and network extras entering the SM8550 host build graph. Those packages are now duplicate product UX, not substrate.

This work should convert “thin host” from mostly image-composition trimming into an enforceable SM8550 substrate contract: what remains on the host is there because recovery, update, boot, storage, or guest launch requires it.

---

## Requirements

- R1. Scope all trimming to SM8550 minimal-host builds; non-SM8550 devices must retain existing ROCKNIX package selection and CI behavior.
- R2. Preserve host substrate invariants: kernel/DT/firmware, bootloader/update tooling, initramfs, systemd, `systemd-nspawn`, `/storage`, `/flash`, `/nix`, `nix-integration`, and guest promotion.
- R3. Preserve host SSH indefinitely, including package inclusion, service enablement, persistent keys/config, and reachability in normal and recovery boots.
- R4. Remove host graphical/UI roots from the SM8550 normal image: Sway/wlroots/Xwayland, host OSD/launcher/UI helpers, graphical benchmarks, host EmulationStation surfaces, and host Mesa/LLVM chains that exist only for host UX.
- R5. Remove host emulation packages from SM8550: RetroArch, libretro cores, standalone emulators, host game support payloads, and 32-bit emulator runtime roots.
- R6. Remove host-owned Tailscale/WireGuard/netfilter extras: host Tailscale, WireGuard userspace, and netfilter/firewall services not required by the chosen host network manager. Other product network services such as Samba/NFS/simple HTTP/sync tooling are follow-up unless they are direct dependencies of the targeted extras.
- R7. Preserve guest-owned Tailscale as a normal client by adding or retaining the required nspawn boundary: `/dev/net/tun`, `CAP_NET_ADMIN`, and `CAP_NET_RAW` must be available to `rocknix-guest-v2.service`; host Tailscale must not be required.
- R8. Preserve current guest input/display boot contract by keeping InputPlumber and scrubbed udev staging until a separate input-boundary plan removes them.
- R9. Redefine recovery explicitly before deleting host UI assumptions: recovery is SSH/console-first unless a specific minimal graphical recovery package set is intentionally retained.
- R10. Add negative package/build-graph checks so the removed host roots cannot silently re-enter through image metas, SDL2, gamesupport, workflows, or network virtual packages.
- R11. Use a clean full SM8550 build for the first dependency-graph removal; use image-only fast iteration only after a new full-build baseline exists.

---

## Scope Boundaries

- Do not delete package source directories from the repository; remove them from SM8550 package roots only.
- Do not change non-SM8550 behavior except for shared workflow conditionals that explicitly skip only SM8550 minimal-host emulation artifacts.
- Do not remove InputPlumber in this plan; `rocknix-guest-udev-stage` still relies on InputPlumber hidden-device tags to prevent guest libseat/wlroots failures.
- Do not remove host SSH, update scripts, qcom-abl/rocknix-abl, `nix-integration`, `systemd-nspawn`, or guest promotion.
- Do not combine this trim with unrelated guest product work. Guest pin bumps are allowed only when required to preserve guest-owned Tailscale or docs copied into the host image.
- Do not remove Samba, NFS, simple HTTP, or sync tooling solely under this plan unless implementation proves they are direct dependencies of host Tailscale/WireGuard/netfilter roots. Track them as follow-up product-network trimming otherwise.
- Do not rely on stale fast-iter artifacts to prove dependency removal.

### Deferred to Follow-Up Work

- Move InputPlumber fully into the guest, or remove the host InputPlumber dependency after a separate input-device ownership plan.
- Remove host audio recovery packages entirely after guest-owned audio has survived cold-boot and recovery validation.
- Trim non-target product network services such as Samba, NFS, simple HTTP, and sync tooling after the Tailscale/WireGuard/netfilter pass.
- Replace ConnMan with an even smaller host network path, if ConnMan's `iptables` dependency proves to be the last netfilter remnant.
- Public-release documentation and user-facing migration story for users who still expect host SMB/NFS/Tailscale services.

---

## Context & Research

### Relevant Code and Patterns

- `projects/ROCKNIX/devices/SM8550/options` already carries the SM8550 minimal-host direction and is the right place for device-scoped package-selection defaults.
- `projects/ROCKNIX/packages/virtual/image/package.mk` is the image root. It currently decides whether UI, sound, sync, multimedia, emulators, debug tools, storage helpers, and `nix-integration` enter the target graph.
- `projects/ROCKNIX/packages/virtual/network/package.mk` is the host network root. It is the place to distinguish recovery substrate from product network services.
- `projects/ROCKNIX/packages/virtual/emulators/package.mk` and `projects/ROCKNIX/packages/virtual/gamesupport/package.mk` expand host emulator/runtime payloads and should become irrelevant for SM8550 minimal host.
- `projects/ROCKNIX/packages/graphics/SDL2/package.mk` can re-enter `swaywm-env` through `DISPLAYSERVER=wl` / `WINDOWMANAGER=swaywm-env`; this is a known backdoor into host Sway.
- `projects/ROCKNIX/packages/apps/mako-osd/package.mk`, `projects/ROCKNIX/packages/apps/screen-switch/package.mk`, and `projects/ROCKNIX/packages/tools/gamepadcalibration/package.mk` are direct or transitive host UI roots to remove or gate.
- `projects/ROCKNIX/packages/tools/nix-integration/system.d/rocknix-guest-v2.service` is the host/guest boundary. It must keep the `/dev/net/tun` bind and `CAP_NET_ADMIN`/`CAP_NET_RAW` retention proven by guest Tailscale testing.
- `.github/workflows/build-device.yml`, `.github/workflows/build-aarch64-image.yml`, and `.github/workflows/build-image-only.yml` still need to reflect that SM8550 minimal-host images should not require emulator artifacts.
- `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh` and `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh` are the contract tests to extend.

### Institutional Learnings

- `rocknix-nix-guest` plan `docs/plans/2026-05-07-003-feat-rocknix-layer-14-thin-host-main-space-plan.md` established the architecture: ROCKNIX is the safety/update/recovery substrate; Nix guest owns product userspace.
- `rocknix-nix-guest` learning `docs/solutions/best-practices/rocknix-layer14-main-space-cold-boot-autostart-2026-05-08.md` documents why raw `/run/udev` is unsafe and why scrubbed staged udev remains part of the host/guest contract.
- `rocknix-nix-guest` plan `docs/plans/2026-05-11-002-refactor-sm8550-guest-owned-audio-plan.md` provides the responsibility-classification pattern: required substrate, measured optimization, temporary adapter, recovery-only, or removable.
- `rocknix-nix-guest` learning `docs/solutions/developer-experience/fast-iter-and-local-rocknix-build-2026-05-08.md` warns that image-only fast iteration is only valid when compiled artifacts still match the dependency graph.
- `rocknix-nix-guest` learning `docs/solutions/developer-experience/custom-fork-update-sm8550-rocknix-2026-05-04.md` captures the `/storage/.update/` deployment path and checksum/ABL precheck discipline that must remain intact.

### External References

External research was not needed. This is a repo-specific build graph and recovery-contract change with sufficient in-tree evidence.

---

## Key Technical Decisions

- **Use SM8550-specific gates, not global defaults.** The trim is a Thor/Odin2 Portal minimal-host path; other ROCKNIX devices keep the monolithic UX image.
- **Recovery becomes SSH/console-first for this trim.** Keeping a host graphical recovery UI would retain much of the Sway/Mesa stack we are trying to remove. The plan should preserve a usable recovery target through host SSH, local console, `/flash/rocknix.no-nspawn`, and `rocknix.safe=1`.
- **Keep InputPlumber for now.** It is still part of the guest input/udev staging contract and should not be conflated with host graphical UX.
- **Remove host Tailscale, not guest Tailscale.** The guest owns the tailnet identity; the host only provides shared netns, `/dev/net/tun`, and recovery SSH on LAN.
- **Remove netfilter in layers.** Host Tailscale, WireGuard userspace, and standalone firewall services can go first. ConnMan's `iptables` dependency should be removed only if host networking remains proven without it or ConnMan is replaced.
- **Treat build-graph absence as a first-class test.** Success is not just booting; packages like `sway`, `wlroots`, `xwayland`, `mesa:host`, `llvm:host`, `retroarch`, `tailscale`, and `wireguard-tools` must be absent from the SM8550 host graph unless intentionally retained.
- **First pass needs a full SM8550 build.** Removing roots invalidates old aarch64 artifacts; after that succeeds, image-only fast iteration can resume for service/docs/test fixes.

---

## Open Questions

### Resolved During Planning

- **Should host SSH stay?** Yes. It is an indefinite recovery/development invariant.
- **Should recovery require host graphical UI?** No for this trim. Recovery should be SSH/console-first so the host graphical stack can actually disappear.
- **Should host Tailscale remain as off-LAN recovery?** No. Guest Tailscale owns tailnet identity; if the guest is broken, recovery is LAN SSH or physical/update-media based.
- **Should InputPlumber be removed with graphical stack?** No. It is a separate input-boundary question and remains for this plan.
- **Can fast-iter alone prove this trim?** No. Use a full build for the first dependency-graph change.

### Deferred to Implementation

- Exact smallest host network manager set after host VPN extras are removed. Default to keeping ConnMan/iwd active for host SSH in both normal and recovery boots until a smaller host-network plan replaces them.
- Exact negative package denylist after inspecting the final post-build plan; the plan below names the expected core list but implementation may split it into required and aspirational tiers.
- Whether SM8550 workflow simplification can land in the same commit as package trimming or should follow after the image root is proven.

---

## High-Level Technical Design

> *This illustrates the intended approach and is directional guidance for review, not implementation specification. The implementing agent should treat it as context, not code to reproduce.*

```mermaid
flowchart TD
    Image[SM8550 image root] --> Substrate[Host substrate]
    Image -. removed .-> HostUI[Host UI / Sway / Mesa]
    Image -. removed .-> HostEmu[Host emulators / RetroArch / libretro]
    Image -. removed .-> HostVPN[Host Tailscale / WireGuard / extras]

    Substrate --> Boot[Bootloader / kernel / initramfs]
    Substrate --> Storage[/storage, /flash, /nix]
    Substrate --> SSH[Host SSH]
    Substrate --> Nspawn[systemd-nspawn guest]
    Substrate --> Recovery[SSH/console recovery]
    Substrate --> InputPlumber[InputPlumber + staged udev]

    Nspawn --> GuestUX[NixOS guest product UX]
    Nspawn --> GuestTS[Guest Tailscale via /dev/net/tun]
```

---

## Implementation Units

### U1. Add SM8550 build-graph characterization and denylist checks

**Goal:** Make current and future host bloat visible so package-root removals cannot silently regress.

**Requirements:** R1, R4, R5, R6, R10

**Dependencies:** None

**Files:**
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh`
- Create or modify: `projects/ROCKNIX/packages/tools/nix-integration/scripts/rocknix-guest-soak`

**Approach:**
- Start with characterization/inventory reporting so the first unit can land before removals are complete.
- Add a post-build plan/inventory verification convention that inspects the generated package plan or install inventory after an SM8550 build.
- Promote denylist entries from report-only to enforced checks in the same units that remove those roots: host UI in U2, host emulators in U3, and host Tailscale/WireGuard/netfilter extras in U4.
- Keep conditional denylist entries separate for dependencies that may remain temporarily (`iptables` if ConnMan still requires it).
- Keep must-stay assertions for `nix-integration`, `openssh`, `systemd-nspawn`, `rocknix-guest-v2.service`, `/dev/net/tun` guest support, and InputPlumber.

**Patterns to follow:**
- Existing grep-based architecture assertions in `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`.
- Existing runtime host/guest marker checks in `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh`.

**Test scenarios:**
- Happy path: after the final trimmed build, the SM8550 package plan/inventory does not include selected denylist packages.
- Error path: after the corresponding removal unit lands, reintroducing `sway`, `retroarch`, host `tailscale`, or host `wireguard-tools` into SM8550 roots fails a static or inventory check with a clear message.
- Integration: required substrate packages/services still appear in checks after denylist assertions are added.
- Non-SM8550 parity: denylist checks are SM8550-scoped and do not fail other device package roots.

**Verification:**
- Contract checks clearly distinguish “removed from SM8550 host” from “package source deleted from repo.”
- The initial branch can show known offenders before later units remove them; the final branch shows absence.

---

### U2. Remove host graphical/UI roots from SM8550 image composition

**Goal:** Stop host Sway/wlroots/Xwayland/Mesa/LLVM chains from entering the SM8550 host image through image roots, SDL2, OSD, screen-switch, gamepad calibration, or graphical demos.

**Requirements:** R1, R4, R9, R10

**Dependencies:** U1

**Files:**
- Modify: `projects/ROCKNIX/devices/SM8550/options`
- Modify: `projects/ROCKNIX/packages/virtual/image/package.mk`
- Modify if needed: `projects/ROCKNIX/packages/graphics/SDL2/package.mk`
- Modify if needed: `projects/ROCKNIX/packages/apps/mako-osd/package.mk`
- Modify if needed: `projects/ROCKNIX/packages/apps/screen-switch/package.mk`
- Modify if needed: `projects/ROCKNIX/packages/tools/gamepadcalibration/package.mk`
- Test: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`

**Approach:**
- Gate `PKG_UI`, `PKG_UI_TOOLS`, host graphical demos/benchmarks, and host OSD roots away from SM8550 minimal host. Gate broader `PKG_GRAPHICS` or `PKG_MULTIMEDIA` only when a specific package is proven to be a host graphical re-entry path rather than a substrate dependency.
- Use SM8550 device options to disable host display/window-manager selection for host packages. Prefer values that packages consistently interpret as disabled; fix package conditionals if `none` and `no` are inconsistent.
- Remove `screen-switch` and `gamepadcalibration` from SM8550 host `ADDITIONAL_PACKAGES` unless implementation proves they are substrate-critical.
- Keep `rocknix-abl` and InputPlumber in SM8550 additional packages.
- Update recovery docs/tests in U5 rather than keeping host graphical UI solely for fallback.

**Patterns to follow:**
- Existing SM8550 minimal-host conditionals in `projects/ROCKNIX/devices/SM8550/options`.
- Existing image-level guardrails near the SM8550 minimal-host comments in `projects/ROCKNIX/packages/virtual/image/package.mk`.

**Test scenarios:**
- Happy path: SM8550 package graph no longer includes `sway`, `wlroots`, `xwayland`, `swaywm-env`, `mako-osd`, `screen-switch`, `gamepadcalibration`, `mesa-demos`, `glmark2`, or `vkmark` as host image roots.
- Integration: normal boot still reaches `rocknix-graphical.target`, starts `rocknix-guest-v2.service`, and paints guest UI.
- Error path: SDL2 consumer packages do not re-enter `swaywm-env` when host `DISPLAYSERVER` is disabled for SM8550.
- Regression: host `/usr`, `/lib`, host Wayland runtime, and host X11 paths remain absent from the guest nspawn binds.

**Verification:**
- The post-build graph shows no host UI path to `mesa:target`, `mesa:host`, or `llvm:host` caused by removed roots.
- Thor still boots to guest main-space and host SSH remains reachable.

---

### U3. Remove SM8550 host emulation and gamesupport payloads

**Goal:** Stop building and shipping host RetroArch, libretro cores, standalone emulators, host game support packages, and 32-bit emulator runtime roots for SM8550 minimal host.

**Requirements:** R1, R5, R10, R11

**Dependencies:** U1, U2

**Files:**
- Modify: `projects/ROCKNIX/devices/SM8550/options`
- Modify: `projects/ROCKNIX/packages/virtual/image/package.mk`
- Review/modify if needed: `projects/ROCKNIX/packages/virtual/emulators/package.mk`
- Review/modify if needed: `projects/ROCKNIX/packages/virtual/gamesupport/package.mk`
- Modify: `.github/workflows/build-device.yml`
- Modify: `.github/workflows/build-aarch64.yml`
- Modify: `.github/workflows/build-arm.yml`
- Modify: `.github/workflows/build-aarch64-image.yml`
- Modify: `.github/workflows/build-image-only.yml`
- Test: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`

**Approach:**
- Force SM8550 minimal-host image composition to exclude `emulators`, `gamesupport`, `retroarch`, libretro cores, standalone emulators, and `lib32`.
- Ensure guest-side emulator availability is not inferred from host package presence; the guest remains the product UX owner.
- Update workflow conditionals so SM8550 minimal-host builds skip emulator jobs, 32-bit arm runtime jobs/artifacts, and emulator artifact downloads only after the image package roots no longer need them.
- Preserve non-SM8550 workflow paths unchanged.

**Patterns to follow:**
- Existing SM8550-specific workflow skips for MAME/QT/emulator jobs where already present.
- Existing fast-iter artifact reuse pattern in `.github/workflows/build-image-only.yml`.

**Test scenarios:**
- Happy path: SM8550 build graph has no `emulators`, `gamesupport`, `retroarch`, `*-lr` libretro cores, host standalone emulator targets, or `lib32` roots.
- Integration: SM8550 full build succeeds without requiring emulator or 32-bit arm runtime artifacts.
- Fast-iter: SM8550 image-only workflow does not attempt to download emulator or 32-bit arm artifacts after the first new full-build baseline.
- Non-SM8550 parity: at least one representative non-SM8550 workflow path still includes expected emulator artifacts.

**Verification:**
- The SM8550 artifact contains only guest-provided product emulator path, not host emulator payloads.
- CI no longer spends time on host emulation artifacts for SM8550 minimal host.

---

### U4. Trim host Tailscale/WireGuard/netfilter extras while preserving SSH and guest Tailscale

**Goal:** Remove host-owned Tailscale/WireGuard/netfilter-adjacent extras while keeping the minimum host network path required for SSH/recovery and guest launch.

**Requirements:** R3, R6, R7, R10

**Dependencies:** U1

**Files:**
- Modify: `projects/ROCKNIX/packages/virtual/network/package.mk`
- Modify if needed: `projects/ROCKNIX/packages/network/connman/package.mk`
- Modify: `projects/ROCKNIX/packages/network/openssh/package.mk`
- Modify: `projects/ROCKNIX/packages/network/openssh/system.d/sshd.service`
- Modify if needed: `projects/ROCKNIX/devices/SM8550/options`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/system.d/rocknix-guest-v2.service`
- Test: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`
- Test: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh`

**Approach:**
- Keep host network substrate for SSH/recovery: `openssh`, basic network identity, ConnMan/iwd or the chosen Wi-Fi/DHCP components needed before guest starts, and transfer tooling explicitly retained for `/storage/.update/` workflows such as `rsync`.
- Remove host targeted extras from SM8550 network root: host `tailscale`, `wireguard-tools`, and standalone netfilter/firewall services not required by ConnMan/iwd. Defer unrelated product network services unless they are direct dependencies of those targeted roots.
- Add or confirm `rocknix-guest-v2.service` has `/dev/net/tun`, `CAP_NET_ADMIN`, and `CAP_NET_RAW` so guest Tailscale can create `tailscale0`.
- Treat `iptables` separately from host VPN removal. If ConnMan still needs it for host recovery networking, keep it temporarily and document it as a ConnMan dependency rather than a product netfilter service.
- Preserve host SSH activation deterministically for minimal-host images rather than relying on removed UI/autostart flows. If the current `sshd.service` condition remains, ensure the SM8550 image creates or documents the required condition path.

**Patterns to follow:**
- Current minimal-host branch pattern in `projects/ROCKNIX/packages/virtual/network/package.mk` that already separates product-facing network services from recovery substrate.
- Guest Tailscale config in `rocknix-nix-guest` that uses `--accept-dns=false` and `--netfilter-mode=off` to avoid host-resolved/netfilter assumptions.

**Test scenarios:**
- Happy path: host package graph excludes host `tailscale`, `tailscaled`, `wireguard-tools`, and standalone netfilter/firewall services targeted by this unit for SM8550.
- Integration: host SSH is reachable after normal boot and recovery boot on LAN.
- Integration: guest `tailscaled.service` is active, `tailscale0` exists after auth/state is present, and Tailscale reports no DNS/netfilter health warnings.
- Error path: if ConnMan still pulls `iptables`, tests classify it as an accepted recovery-network dependency rather than failing the whole trim.
- Scope guard: unrelated Samba/NFS/simple HTTP/sync packages are neither removed nor asserted absent by this unit unless implementation proves they are direct dependencies of the targeted extras.
- Regression: host Tailscale binaries and services are absent after install.

**Verification:**
- Guest Tailscale remains usable without host Tailscale.
- Host recovery access does not depend on guest Tailscale.

---

### U5. Redefine recovery as SSH/console-first and update recovery validation

**Goal:** Make the fallback contract truthful after host graphical UI removal.

**Requirements:** R3, R4, R9, R10

**Dependencies:** U2, U4

**Files:**
- Modify if needed: `projects/ROCKNIX/packages/rocknix/system.d/rocknix.target`
- Modify if needed: `projects/ROCKNIX/packages/tools/nix-integration/scripts/rocknix-recovery-toggle`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/scripts/rocknix-guest-soak`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh`
- Modify: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`
- Modify source docs copied into `/flash`: `projects/ROCKNIX/packages/tools/nix-integration/package.mk` inputs from guest docs as needed

**Approach:**
- Replace any recovery checks that assume `essway`, host Sway, host PipeWire, or host EmulationStation with checks for SSH, storage, update path, recovery target, and guest-disabled state.
- Ensure `/flash/rocknix.no-nspawn` and `rocknix.safe=1` route to a usable recovery state even if no host UI exists.
- Keep `/flash/HOW-TO-FALL-BACK.md` accurate: users should expect SSH/console recovery, not legacy graphical recovery.
- Preserve normal boot default to `rocknix-graphical.target` for guest main-space.

**Patterns to follow:**
- Existing `rocknix-recovery-toggle` flag/cmdline pattern.
- Runtime smoke style in `nix-integration-runtime-smoke.sh`.

**Test scenarios:**
- Happy path: normal boot reaches guest main-space and host SSH.
- Recovery flag: `/flash/rocknix.no-nspawn` causes recovery target selection, does not start the guest, and leaves host SSH reachable.
- Recovery cmdline: `rocknix.safe=1` causes the same recovery state for that boot.
- Return path: clearing the flag returns to guest main-space on the next boot.
- Error path: failed guest startup does not erase the host SSH/update recovery path.

**Verification:**
- Recovery instructions match actual services available in the trimmed image.
- No host graphical package is kept solely because an obsolete recovery smoke expects it.

---

### U6. Validate with clean full build, update install, and non-SM8550 guard

**Goal:** Prove the trimmed graph is real, shippable, and scoped.

**Requirements:** R1-R11

**Dependencies:** U1, U2, U3, U4, U5

**Files:**
- Modify as needed: `.github/workflows/build-device.yml`
- Modify as needed: `.github/workflows/build-aarch64-image.yml`
- Modify as needed: `.github/workflows/build-image-only.yml`
- Test: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-static-checks.sh`
- Test: `projects/ROCKNIX/packages/tools/nix-integration/tests/nix-integration-runtime-smoke.sh`

**Approach:**
- Trigger a clean full SM8550 build after dependency roots are removed.
- Use image-only fast iteration only after the full build establishes fresh minimal-host artifacts.
- Install through the normal `/storage/.update/` path with checksum verification and ABL precheck discipline.
- Validate on Thor before merging into `custom`.
- Run or inspect at least one representative non-SM8550 path so SM8550-only gates did not leak globally.

**Patterns to follow:**
- `/storage/.update/` custom-fork procedure from `docs/solutions/developer-experience/custom-fork-update-sm8550-rocknix-2026-05-04.md`.
- Fast-iter workflow constraints from `docs/solutions/developer-experience/fast-iter-and-local-rocknix-build-2026-05-08.md`.

**Test scenarios:**
- Happy path: clean full SM8550 build completes and artifact names still identify the thin-host SM8550 image/update tar.
- Image inventory: final artifact excludes selected host graphical/emulation/VPN packages.
- Install path: update tar applies via `/storage/.update/`, clears the update directory, and boots to guest main-space.
- Runtime: host SSH, `rocknix-guest-v2.service`, guest promotion, runtime smoke, guest Tailscale, and recovery target checks pass.
- Non-SM8550 parity: representative non-SM8550 build/config path is unchanged.

**Verification:**
- The first trimmed image is validated on hardware, not just in CI.
- Subsequent tweaks can safely return to image-only iteration.

---

## System-Wide Impact

- **Interaction graph:** Image package roots, device options, network virtual packages, nspawn service boundary, recovery target selection, CI artifact flow, and live update path all interact.
- **Error propagation:** A dependency trim can fail at build time, image assembly time, boot target selection, guest launch, or recovery validation. Each failure needs a clear gate.
- **State lifecycle risks:** Host Tailscale state may remain on `/storage` but no longer represents an active service; guest Tailscale state/auth is separate. Host ConnMan/iwd and guest NetworkManager share the host network namespace; this plan keeps host networking for SSH/recovery until a separate smaller-network plan proves a replacement.
- **API surface parity:** `/flash/rocknix.no-nspawn`, `rocknix.safe=1`, host SSH on port 22, `/storage/.update/`, and guest promotion markers remain public operational contracts.
- **Integration coverage:** Unit/static checks alone will not prove this; the first trimmed image needs CI plus Thor install validation.
- **Unchanged invariants:** Non-SM8550 devices keep the normal ROCKNIX host UX/emulation stack. Guest remains the product UX owner on SM8550.

---

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| Recovery boots to a blank or unusable target after Sway removal | Redefine recovery as SSH/console-first and update runtime smoke before relying on it. |
| Host SSH is condition-gated and not actually active | Make SM8550 minimal-host SSH enablement explicit and validate SSH on normal and recovery boots. |
| SDL2/gamesupport/mako re-enter the graphics stack | Add build-graph denylist checks and remove each re-entry path deliberately. |
| Guest Tailscale regresses after host network trim | Preserve `/dev/net/tun` and nspawn network capabilities; validate guest `tailscaled.service` and health. |
| ConnMan keeps `iptables` alive | Treat ConnMan/iptables as a separate network-substrate dependency; remove host Tailscale/WireGuard/standalone firewall services first. |
| CI still spends hours on SM8550 emulator artifacts | Update workflow conditionals after image roots no longer require those artifacts. |
| Fast-iter masks stale package outputs | Require a full SM8550 build for the first graph-removal change. |
| Non-SM8550 devices accidentally lose ROCKNIX UX | Scope gates by `DEVICE=SM8550` and validate a representative non-SM8550 path. |

---

## Documentation / Operational Notes

- Update fallback docs copied into `/flash` so recovery is described as SSH/console-first.
- Document that host Tailscale/off-LAN host recovery is intentionally gone; guest Tailscale is the tailnet identity when the guest is healthy.
- Document which host transfer tools remain for `/storage/.update/` workflows, especially if other sync services are deferred.
- Document that the first trim iteration needs a full SM8550 build; image-only fast iteration resumes after a fresh full-build baseline.
- Capture package-graph size/build-time delta after the first successful clean build so future trim work can measure impact.

---

## Sources & References

- Related `rocknix-nix-guest` plan: `docs/plans/2026-05-07-003-feat-rocknix-layer-14-thin-host-main-space-plan.md`
- Related `rocknix-nix-guest` plan: `docs/plans/2026-05-11-002-refactor-sm8550-guest-owned-audio-plan.md`
- Related `rocknix-nix-guest` plan: `docs/plans/2026-05-12-001-refactor-upstream-rebase-checkpoint-plan.md`
- Related `rocknix-nix-guest` learning: `docs/solutions/developer-experience/custom-fork-update-sm8550-rocknix-2026-05-04.md`
- Related `rocknix-nix-guest` learning: `docs/solutions/developer-experience/fast-iter-and-local-rocknix-build-2026-05-08.md`
- Related code: `projects/ROCKNIX/devices/SM8550/options`
- Related code: `projects/ROCKNIX/packages/virtual/image/package.mk`
- Related code: `projects/ROCKNIX/packages/virtual/network/package.mk`
- Related code: `projects/ROCKNIX/packages/tools/nix-integration/system.d/rocknix-guest-v2.service`
