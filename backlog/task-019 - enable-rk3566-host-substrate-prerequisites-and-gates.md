---
id: task-019
title: Enable RK3566 host substrate prerequisites and gates
status: In Progress
priority: high
labels:
  - rk3566
  - before-device
  - substrate
  - rocknix-patches
  - kernel-config
  - nspawn
created: 2026-06-04
source: user
---

# Enable RK3566 host substrate prerequisites and gates

## Why it matters

RK3566 images cannot include or run the NixOS guest substrate until the ROCKNIX patch queue makes device support explicit and enables the host kernel/systemd prerequisites.

## Acceptance Criteria

- [ ] `rocknix-guest-substrate` gating is changed from SM8550-only to an explicit supported-device or capability table that includes RK3566 only where intended.
- [ ] Systemd/nspawn packaging guards are relaxed or parameterized without changing SM8550 behavior.
- [ ] ROCKNIX RK3566 options or kernel config patches enable the required cgroup v2 and systemd hierarchy settings for nspawn.
- [ ] RK3566 kernel config is checked for required namespace and overlay filesystem support, with patches added where missing.
- [ ] A RK3566 minimal-host knob or equivalent strips conflicting host UI assumptions only when the guest substrate lane is enabled.
- [ ] Static checks assert unsupported devices fail clearly and supported SM8550/RK3566 prerequisites are preserved.
- [ ] No RK3566 image is claimed bootable solely from this gate/prerequisite work.

## Related

- `patches/rocknix/0006-rocknix-guest-substrate.patch`
- `patches/rocknix/series`
- `patches/rocknix/`
- `work/rocknix/projects/ROCKNIX/devices/RK3566/options`
- `work/rocknix/projects/ROCKNIX/devices/RK3566/linux/linux.aarch64.conf`
- `scripts/verify-sm8550-contract`
- `scripts/verify-rk3566-contract`

## Notes

Logical work group: host substrate patch-queue enablement. Consolidates task-006 and task-007.
