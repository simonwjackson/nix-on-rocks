# SM8550 DeviceAccepted: Nix-on-Rocks external build

Date: 2026-05-19
Device: `sobo` / AYN Odin 2 Portal (`ayn,odin2portal`)

## Build proof

- Product repo: `https://github.com/simonwjackson/nix-on-rocks`
- Successful workflow run: `https://github.com/simonwjackson/nix-on-rocks/actions/runs/26075223943`
- Workflow: `Continue SM8550 from Toolchain`
- Product SHA used for artifact: `229f1ffacc06ce76a911b984edfd263fe4cf61da`
- Current follow-up verifier fix SHA: `51320869a59db108f8be2f7b62904527fcba11dd`
- Upstream ROCKNIX SHA: `f080b462f54b5807bdd16ac7cc2ab64528b038b1`
- Source patch branch SHA: `3ed044db39bcf69256fbae02fa4b17595da3a0c1`
- Patch-series hash: `276632e44e95351712e29dadbe3cbe71e72f65eceb345fa02f06c02d2e00280d`

## Artifacts

- Update artifact: `ROCKNIX-SM8550.aarch64-20260519.tar`
  - SHA256: `0ab4d53121916c3bf92386a8c92359aaace395000729c4e39af4dc8c5658bcb6`
- Image artifact: `ROCKNIX-SM8550.aarch64-20260519.img.gz`
  - SHA256: `9325315a4d15fb7d9a7529a2a63ff74d4ebbb4b13ef851684d3ec0ef7c6fb171`
- Expected guest seed: `rocknix-guest-rootfs-odin2portal-4fb6d8f14bae.tar.zst`
  - SHA256: `dc05c42344496c6f0fa66aa7514845cc6ab32a2d61881eb9341843aad39bcdde`

Local artifact verification before install:

- update tar checksum: passed
- image gzip integrity: passed
- update tar contained `target/SYSTEM`
- update tar contained `target/KERNEL`
- update tar contained `target/seed/rocknix-guest-rootfs-odin2portal-4fb6d8f14bae.tar.zst`
- update-tar seed SHA matched the expected guest seed SHA256

## Install path

Installed through the normal ROCKNIX update path:

1. Copied update tar and checksum to `/storage/.update/` on `sobo`.
2. Verified `sha256sum -c ROCKNIX-SM8550.aarch64-20260519.tar.sha256` on-device.
3. Rebooted and let initramfs apply the update.

No Android or bootloader partitions were touched.

## Post-reboot evidence

After the update reboot:

- Hostname: `SM8550`
- Installed `BUILD_ID`: `f080b462f54b5807bdd16ac7cc2ab64528b038b1`
- Compatible strings:
  - `ayn,odin2portal`
  - `qcom,qcs8550`
  - `qcom,sm8550`
- `/storage`: `83.1G` available
- `/flash`: `1.9G` available
- Host system state: `running`
- Host failed units: `0`
- `rocknix-guest.service`: `active`
- Display brightness: `410 / 4096` (persistent 10% dimming preserved)

Validation commands:

- `rocknix-guest-activation-audit --quiet`: passed
- `/usr/lib/rocknix-guest-substrate/tests/guest-substrate-runtime-smoke.sh`: passed
- `ROCKNIX_REQUIRE_HOST_ESSWAY=no rocknix-guest-soak --hours 1 --interval-seconds 1`: passed with zero alarms

## Result

`DeviceAccepted` for the first external Nix-on-Rocks SM8550 patch-product build.
