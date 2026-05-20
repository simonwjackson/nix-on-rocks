# SM8550 Phase 5 CI and Device Acceptance

Date: 2026-05-20
Device: `sobo` / AYN Odin 2 Portal (`ayn,odin2portal`)

## Scope

Phase 5 hardened the Nix-on-Rocks SM8550 build lanes so packaging-only changes can be proven without rebuilding the full toolchain/base each time.

Accepted surfaces:

- reusable SM8550 base-artifact workflow;
- image-only workflow using a saved base run;
- explicit SM8550 lock and payload verifiers;
- public `nix-on-rocks` repository fetch posture;
- normal ROCKNIX update deployment to `sobo`.

## Repository visibility and checksum fix

`https://github.com/simonwjackson/nix-on-rocks` was made public before the final Phase 5 proof.

Making the repo public changed the GitHub-generated tarball bytes for the pinned product source revision even though the commit did not change. The first image-only run failed correctly in `rocknix-guest-substrate` with a tarball SHA mismatch:

- expected private/authenticated tarball SHA256: `fbbb3f7110b5d31df9b93d180659b41d995a1959b9499d9a96b2294ec528d8fd`
- observed public tarball SHA256: `013b47b315843efc10bd81e4eb2f5e32672bc23b5ddc8a0b7dc0ada9d21549e9`

Fix:

- Commit: `56fb5bf02fa13a1e2370ca50d235a36d2c020507`
- Subject: `fix: update public product tarball checksum`

The failure is useful evidence: the host package refuses to extract a product tarball whose bytes do not match the pinned checksum.

## CI proof

### Preflight

- Workflow run: `https://github.com/simonwjackson/nix-on-rocks/actions/runs/26148417386`
- Product SHA: `56fb5bf02fa13a1e2370ca50d235a36d2c020507`
- Result: success

Preflight verified:

- patch replay;
- SM8550 contract;
- SM8550 guest lock/package alignment.

### Prepare base artifacts

- Workflow run: `https://github.com/simonwjackson/nix-on-rocks/actions/runs/26148449934`
- Product SHA: `56fb5bf02fa13a1e2370ca50d235a36d2c020507`
- Toolchain source run: `26037562850`
- Result: success

Uploaded reusable artifacts:

- `aarch64 (SM8550)`
- `aarch64 build (SM8550)`

This proves the reusable base lane can rebuild SM8550 base artifacts from the known-good saved toolchain after the public tarball checksum fix.

### Image only

- Workflow run: `https://github.com/simonwjackson/nix-on-rocks/actions/runs/26152901081`
- Product SHA: `56fb5bf02fa13a1e2370ca50d235a36d2c020507`
- Base run: `26148449934`
- Result: success
- Uploaded artifact: `nix-on-rocks-sm8550-image-only-26152901081`

Image-only manifest:

- Upstream ROCKNIX SHA: `f080b462f54b5807bdd16ac7cc2ab64528b038b1`
- Source branch SHA: `3ed044db39bcf69256fbae02fa4b17595da3a0c1`
- Patch-series hash: `9708e12b68513a996db8b695e46b5544438a9cc6c74ddd7475758cfb417912aa`
- Guest seed: `rocknix-guest-rootfs-odin2portal-d5d00fe4b588.tar.zst`
- Guest seed SHA256: `650dafebc88abdc3581cb67dd05d825b54dc8807930898713b8086f5dda21a1f`

Payloads:

- `ROCKNIX-SM8550.aarch64-20260520.img.gz`
  - SHA256: `5520db591ad1bef18d29d65cf07ca569e341c3ef59e7fed2f6e2deba8322a5c9`
- `ROCKNIX-SM8550.aarch64-20260520.tar`
  - SHA256: `c470e6b403a50be8dc469a7df8ee9a1221e7222578e1fc21834b55f6170e181f`

Local artifact verification before install:

- `scripts/verify-sm8550-payloads /tmp/nix-on-rocks-image-only-26152901081/work/rocknix/target`: passed
- `sha256sum -c *.sha256`: passed
- update tar contained `target/SYSTEM`
- update tar contained `target/KERNEL`
- update tar contained `target/seed/rocknix-guest-rootfs-odin2portal-d5d00fe4b588.tar.zst`

## Install path

Installed through the normal ROCKNIX update path:

1. Copied `ROCKNIX-SM8550.aarch64-20260520.tar` and sidecar `.sha256` to `/storage/.update/` on `sobo`.
2. Verified `sha256sum -c ROCKNIX-SM8550.aarch64-20260520.tar.sha256` on-device.
3. Rebooted and let initramfs apply the update.

No Android, firmware, or bootloader partitions were touched.

## Post-reboot device evidence

After update application:

- Hostname: `SM8550`
- Installed `BUILD_ID`: `f080b462f54b5807bdd16ac7cc2ab64528b038b1`
- Host system state: `running`
- Host failed units: `0`
- `rocknix-guest.service`: `active`
- `rocknix-guest-promote.service`: `inactive`
- `/storage/.update`: empty after update consumption
- Current rootfs revision: `d5d00fe4b58822da8ab0a0c21ea4306a92c65c2a`
- Current seed archive: `rocknix-guest-rootfs-odin2portal-d5d00fe4b588.tar.zst`
- Stored seed SHA256: `650dafebc88abdc3581cb67dd05d825b54dc8807930898713b8086f5dda21a1f`
- Auto-reseed fix: present (`packaged_seed_update_available` in `rocknix-guest-root-ensure`)
- Display brightness: `410 / 4096`

Validation commands:

- `rocknix-guest-activation-audit --quiet`: passed
- `rocknix-guest-soak --hours 0 --interval-seconds 5`: passed with zero alarms

## Result

`DeviceAccepted` for Phase 5 on Odin2Portal.

The reusable base lane and image-only lane are now proven on public `nix-on-rocks`, and the produced image-only update artifact was installed successfully on `sobo` through the standard ROCKNIX update path.
