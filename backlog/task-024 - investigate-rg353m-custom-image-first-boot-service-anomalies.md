---
id: task-024
title: Investigate RG353M custom image first-boot service anomalies
status: To Do
priority: medium
labels:
  - rg353m
  - rk3566
  - first-boot
  - hardware-validation
created: 2026-06-05
source: user
---

# Investigate RG353M custom image first-boot service anomalies

## Why it matters

The first custom RK3566/RG353M SD boot reached WiFi and SSH, but `volume-fixup.service` failed and `input_sense` repeatedly restarted evtest workers. These may affect audio volume defaults, input handling, logs, and system stability during longer validation.

## Acceptance Criteria

- [ ] `systemctl --failed` is clean or any remaining failures are documented as benign on the RG353M custom SD image.
- [ ] `journalctl -b` no longer shows continuous `input_sense` evtest restart spam for RG353M input devices.
- [ ] A targeted RG353M SSH evidence capture records the resolved service status after the fix.

## Related

- `docs/brainstorms/evidence/2026-06-05-rg353m-custom-rocknix-sd-first-boot.md`

## Notes

Observed on custom image ROCKNIX-RK3566.aarch64-20260605-Generic.img.gz from Actions run 26996116801 at root@192.168.1.140.
