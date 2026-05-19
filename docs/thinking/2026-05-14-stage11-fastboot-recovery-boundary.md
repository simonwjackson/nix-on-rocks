# Stage 11 Fastboot Recovery Boundary Thinking Memo

Date: 2026-05-14

## Purpose

Capture the stopping point before beginning Stage 11 work. The user wants to pause here and return later with the risk model preserved.

The immediate concern is not ordinary boot failure, black screen, or a bad guest generation. The core concern is avoiding any change that could make the device unrecoverable through the normal button-combo / fastboot-style path and require opening the device, EDL test points, or other invasive recovery.

## Current Strategic Context

The project direction is still:

```text
ROCKNIX host = boot / update / recovery / substrate
NixOS guest = product UX / runtime / device policy
```

Stage 10 has moved the guest toward a Nix-selected system generation. The canonical host-recognized guest selector is:

```text
/nix/var/nix/profiles/per-user/root/rocknix-guest-system
```

The legacy mirror profile is retired:

```text
/nix/var/nix/profiles/system
```

A controlled bad-generation drill has already shown that a bad guest generation can fail safely with bounded retries and manual recovery. That kind of failure is acceptable because the host still boots and recovery remains available.

## Stage 11 Definition

Stage 11 is "Nix-owned boot artifacts": moving from Nix owning the guest/rootfs to Nix building or selecting the artifacts used by the device boot path after the vendor/bootloader boundary.

Sublevels from the Level N report:

1. **11a — Nix-built initramfs proof**
2. **11b — Nix-built kernel + modules + DTB/DTBO**
3. **11c — Nix-built boot image / update artifact**
4. **11d — Nix-managed boot selection + rollback**

The conceptual checkpoint for Stage 11 is:

> Can I point at one Nix derivation and say: "this is the thing my handheld boots"?

## Reassessed Risk Model

The user is specifically worried about this failure mode:

> Even when using the normal button combo / fastboot-style recovery path, the device cannot be recovered easily, requiring the device to be opened or recovered through invasive means.

That reframes risk around the **fastboot/recovery boundary**, not around whether a normal boot succeeds.

### Acceptable / Lower Risk Failures

These are acceptable if host SSH, recovery, or fastboot remains available:

- Bad guest generation
- Bad guest rootfs
- Bad guest service activation
- Guest fails to start
- Main-space does not come up but host still boots
- Black screen caused by the normal OS boot path, if fastboot/reflash still works

These may be annoying but should be recoverable without opening the device.

### Stage 11 Soft-Brick Risk

The following can break the installed OS boot and may cause black screen, no SSH, no Tailscale, no guest, or no host userspace:

- Bad initramfs
- Bad kernel
- Bad modules
- Bad DTB/DTBO
- Bad boot image assembly
- Bad update artifact that replaces boot-path artifacts incorrectly

These are only acceptable after proving the button-combo / fastboot-style recovery path can restore a known-good image.

### No-Go / Invasive-Recovery Risk

Avoid touching these unless a non-invasive recovery method has been proven and rehearsed:

- ABL / bootloader chain
- XBL / Qualcomm early boot firmware
- TZ / hyp / devcfg / keymaster / similar firmware partitions
- GPT / partition table
- storage layout
- anything that could disable fastboot/recovery availability
- anything that requires EDL/firehose unless the exact no-open recovery path is already tested

This is the category that could plausibly require opening the device or using test points. It is outside the intended Stage 11 scope.

## Updated Stage 11 Ordering by Brick Risk

From lowest to highest risk under this recovery-boundary framing:

1. **Artifact-only Nix builds**
   - Build initramfs/kernel/boot image/update artifacts with Nix.
   - Do not flash them.
   - Compare against known-good ROCKNIX artifacts.
   - Very low device risk.

2. **Fastboot recovery rehearsal**
   - Confirm the button-combo path enters fastboot/recovery.
   - Confirm the development machine sees the device.
   - Confirm a known-good artifact can be restored.
   - Confirm restored artifact boots.
   - This is a hard prerequisite before flashing Stage 11 artifacts.

3. **11a — Nix-built initramfs proof**
   - First real boot-path experiment.
   - Existing bootloader/kernel should remain unchanged.
   - Lower risk than changing kernel/DTB.

4. **11c — Nix-built boot image / update artifact**
   - Risk depends on what the artifact contains.
   - Safer if it initially assembles known-good kernel/DTB/initramfs rather than changing their contents.
   - Should be compared structurally or bit-for-bit where possible against known-good ROCKNIX output.

5. **11b — Nix-built kernel + modules + DTB/DTBO**
   - Highest normal Stage 11 risk.
   - Can break display, storage, USB, network, input, or the host OS boot.
   - Only attempt after fastboot restore is proven and known-good artifacts are ready.

6. **Do not touch for Stage 11**
   - Bootloader/vendor firmware/partition table/Qualcomm chain.
   - This is where invasive recovery risk lives.

## Hard Rule for Future Stage 11 Work

> Only modify artifacts above the fastboot recovery boundary, and only after proving the fastboot recovery boundary works.

Put differently:

- Black screen is tolerable if fastboot restore is rehearsed.
- Losing SSH is tolerable if fastboot restore is rehearsed.
- Losing guest boot is tolerable if host or fastboot restore works.
- Losing fastboot/recovery is not tolerable.
- Anything that might require opening the device is out of scope unless explicitly accepted later.

## Suggested Future Gate Before Any Stage 11 Flashing

Before flashing any Nix-built boot artifact, create and run a documented recovery drill:

1. Save the currently installed known-good ROCKNIX boot/update artifacts.
2. Verify checksums and store them somewhere off-device.
3. Enter fastboot/recovery using the physical button combo.
4. Confirm the host computer detects the device.
5. Reflash or restore the known-good artifact.
6. Boot normally.
7. Verify host SSH/recovery and guest main-space still work.
8. Document exact commands and expected outputs.

Only after this drill passes should Stage 11 artifact flashing begin.

## Non-Goals When Resuming

Do not start by:

- flashing a Nix-built kernel
- flashing a Nix-built DTB/DTBO
- modifying bootloader/vendor firmware
- changing partition tables
- relying on untested EDL/firehose recovery
- assuming black-screen recovery is okay without rehearsed fastboot restore

## Best First Resumption Task

When returning to this work, start with a plan or spike for:

> **Stage 11 recovery-boundary proof: document and rehearse non-invasive fastboot restore before any Nix-built boot artifact is flashed.**

Then proceed to artifact-only Nix builds, then 11a initramfs proof.
