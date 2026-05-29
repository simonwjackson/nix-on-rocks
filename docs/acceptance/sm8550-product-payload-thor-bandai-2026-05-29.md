# SM8550 DeviceAccepted Evidence — bandai / Thor — 2026-05-29

## Result

`DeviceAccepted` for `bandai` / AYN Thor (`ayn,thor`) on the Nix-on-Rocks SM8550 product lane, sourced from the authoritative full `build-sm8550.yml` run using the Thor product selector.

Scope of this evidence:

- `BuildProof`: full `build-sm8550.yml` run completed and verified.
- `ArtifactVerified`: full update tar + full image artifact verified locally, including SM8550 FAT geometry.
- `DeviceAccepted`: update tar applied through the normal `/storage/.update/` path; Thor booted the `120b8d0d857e` Korri guest; host and guest final checks are green.
- `ThreePassAcceptance`: happy/recovery-assisted cutover, no-op reapply, recovery boundary, and restored-normal cleanup were observed.
- `HandsOnAcceptance`: NotRun/Deferred — no screen/input/Moonlight smoke checks were run as part of this acceptance.
- `ReleasePublication`: Thor Korri seed payload was published to `rocknix-product-payload-120b8d0d857e` for this proof.

## Build proof

- Product repo: `https://github.com/simonwjackson/nix-on-rocks`
- Branch: `refactor/product-payload-image-consumption`
- Product SHA: `389adf0fff42c113264bd23300ed19c6d1edbb0e`
- Full-build workflow run: `https://github.com/simonwjackson/nix-on-rocks/actions/runs/26616457343`
- Upstream ROCKNIX SHA: `f080b462f54b5807bdd16ac7cc2ab64528b038b1`
- Source branch SHA: `3ed044db39bcf69256fbae02fa4b17595da3a0c1`
- Patch-series hash: `633f9022a29035af39eca4acc44a5bc47124b3bf17cedc19f3f07b69cde74122`
- Rendered product payload hash: `56b130efdee2b55c75648cd45eeee563dc7c2872a2410ffdd354f82665977ae5`
- Product selector: `thor`

## Active product payload

From `product-payload-thor.lock` at the proven SHA:

- Authority repo: `simonwjackson/korri`
- Product revision: `120b8d0d857e6a34c346975a07b6945dd87625c0`
- Product source SHA256: `83111884ffe60d40392f9b366312172e9e0da77eb4fd0124984c5b9c507b13d4`
- Build target: `.#nixosConfigurations.korri-rocknix-kiosk-thor.config.system.build.toplevel`
- Seed device: `thor`
- Seed compatible: `ayn,thor`
- Seed archive: `rocknix-guest-rootfs-thor-120b8d0d857e.tar.zst`
- Seed SHA256: `7c64da76e49d38629dee7292dcf492ff736c9e957d69483c93ef18f0e4601a65`
- Seed URL authority: `https://github.com/simonwjackson/korri/releases/download/rocknix-product-payload-120b8d0d857e/rocknix-guest-rootfs-thor-120b8d0d857e.tar.zst.part-00`

## Artifacts

Downloaded artifact: `nix-on-rocks-sm8550-thor-26616457343`

Payloads:

- `ROCKNIX-SM8550.aarch64-20260529.tar`
  - SHA256: `1c6c7a323eccfba1ceea05dacc2b0b89661f59322faa0147690a49805dfcf301`
- `ROCKNIX-SM8550.aarch64-20260529.img.gz`
  - SHA256: `aabdfbf2a68d7e451f6be5a6176ad33c54260039e5a66383a41fad86212ab843`

Local verification before install:

- `rocknix_artifact_verify`: passed for both `.img.gz` and `.tar`
- FAT label: `ROCKNIX`
- FAT logical block size: `4096`
- Update tar carried `target/SYSTEM`, `target/KERNEL`, and `target/seed/rocknix-guest-rootfs-thor-120b8d0d857e.tar.zst`
- Embedded Thor seed SHA256 matched `7c64da76e49d38629dee7292dcf492ff736c9e957d69483c93ef18f0e4601a65`

Expected on-device hashes after install:

- KERNEL md5: `5742950b9939f1034060c995d89eab98`
- SYSTEM md5: `507b74e0e8c50b54ee14e0b12420b3f9`

## Pre-install device state

- LAN host: `192.168.1.239`
- Host SSH: port `22`
- Guest SSH: port `2222`
- Hostname before update: `thor` (host), `bandai` (guest)
- Model: `AYN Thor`
- Compatible strings:
  - `ayn,thor`
  - `qcom,qcs8550`
  - `qcom,sm8550`
- Pre-install guest seed revision: `d5d00fe4b58822da8ab0a0c21ea4306a92c65c2a`
- Pre-install seed archive: `rocknix-guest-rootfs-thor-d5d00fe4b588.tar.zst`
- Pre-install `/storage` free: about `659G`
- Pre-install ABL checksums:

  ```text
  91037267a0578fee2e43ca2a8f109120ce055829edcd860cd117645563bdead6  /dev/disk/by-partlabel/abl_a
  91037267a0578fee2e43ca2a8f109120ce055829edcd860cd117645563bdead6  /dev/disk/by-partlabel/abl_b
  ```

## Install path

Installed through the normal ROCKNIX host update path:

1. Verified the local update tar with `sha256sum -c`.
2. Confirmed host `/proc/device-tree/compatible` contained exact `ayn,thor` before host mutation.
3. Cleared host `/storage/.update/`.
4. Copied `ROCKNIX-SM8550.aarch64-20260529.tar` and `.sha256` to host `/storage/.update/`.
5. Verified on-device:

   ```text
   ROCKNIX-SM8550.aarch64-20260529.tar: OK
   ```

6. Rebooted the host and let initramfs apply the update.

No Android or firmware partitions were intentionally touched. The update tar carries an ABL payload, but `3rdparty/bootloader/update.sh` skips ABL unless `ROCKNIX_ALLOW_ABL_UPDATE=yes`; this acceptance did not set that variable.

ABL precheck before host reboot showed the tar ABL differed from device ABL, so the explicit skip behavior was confirmed before proceeding:

```text
tar_abl_sha256=d0cf9dc0228aea259d672ef9679639834cd2ba1b50d998c180dcd2b4baaf12d5
host_abl_a=91037267a0578fee2e43ca2a8f109120ce055829edcd860cd117645563bdead6
host_abl_b=91037267a0578fee2e43ca2a8f109120ce055829edcd860cd117645563bdead6
```

## Pass A — update apply and Thor rootfs cutover

The update was consumed and the host booted the 20260529 image. The first guest reseed attempt failed on stale immutable metadata under the retained previous root:

```text
rocknix-guest-root-ensure: packaged seed revision 120b8d0d857e6a34c346975a07b6945dd87625c0 replaces current seed revision d5d00fe4b58822da8ab0a0c21ea4306a92c65c2a; reseeding before guest start
rm: can't remove '/storage/nix-on-rock/rootfs/previous/var/empty': Operation not permitted
rocknix-guest-root-ensure: FAIL: failed to remove previous guest root: /storage/nix-on-rock/rootfs/previous
```

Recovery action:

- Cleared immutable bits on stale `/storage/nix-on-rock/rootfs/previous` and failed `current.tmp.*`.
- Removed stale `previous` and failed `current.tmp.*`.
- Reran `rocknix-guest-root-ensure.service`.
- Started `rocknix-guest.service`, `rocknix-guest-wifi-ready.service`, and `rocknix-guest-promote.service`.
- Restored guest SSH authorized keys from the retained previous root because the reseeded Thor root contains no default keys by design.

Result after recovery:

- Host compatible: `ayn,thor`
- Host `BUILD_ID`: `f080b462f54b5807bdd16ac7cc2ab64528b038b1`
- `/storage/.update/`: empty (update consumed)
- `rocknix-guest-root-ensure.service`: `active`
- `rocknix-guest.service`: `active`
- `rocknix-guest-wifi-ready.service`: `active`
- `rocknix-guest-promote.service`: `inactive` after successful no-op promotion
- Current guest revision: `120b8d0d857e6a34c346975a07b6945dd87625c0`
- Current seed marker:

  ```text
  seed_revision=120b8d0d857e6a34c346975a07b6945dd87625c0
  seed_device=thor
  seed_compatible=ayn,thor
  seed_sha256=7c64da76e49d38629dee7292dcf492ff736c9e957d69483c93ef18f0e4601a65
  seed_archive=rocknix-guest-rootfs-thor-120b8d0d857e.tar.zst
  ```

- Guest SSH on `:2222`: restored and accepted the existing operator key.

## Pass B — no-op reapply of the same update

The same `ROCKNIX-SM8550.aarch64-20260529.tar` was staged to host `/storage/.update/`, verified on-device, and the host was rebooted again.

Observed after reboot:

- Host compatible: `ayn,thor`
- Host `BUILD_ID`: `f080b462f54b5807bdd16ac7cc2ab64528b038b1`
- `/storage/.update/`: empty
- `rocknix-guest-root-ensure.service`: `active`
- `rocknix-guest.service`: `active`
- Current guest revision remained `120b8d0d857e6a34c346975a07b6945dd87625c0`
- Current seed revision remained `120b8d0d857e6a34c346975a07b6945dd87625c0`
- Host and guest SSH both returned normally.

## Pass C — recovery boundary (`/flash/rocknix.no-nspawn`)

Pre-reboot setup:

```sh
mount -o remount,rw /flash
printf UPDATE > /storage/.boot.hint
touch /flash/rocknix.no-nspawn
mount -o remount,ro /flash
reboot
```

Observed in recovery boot:

- Host compatible: `ayn,thor`
- `default.target`: `multi-user.target`
- `systemctl is-system-running`: `running`
- `rocknix-main-space.target`: `inactive`
- `rocknix-guest.service`: `inactive`
- `/flash/rocknix.no-nspawn`: present
- `/storage/.boot.hint`: still `UPDATE`
- `rocknix-post-update.service`: `inactive`
- `systemctl --failed`: none

Cleanup pass:

```sh
mount -o remount,rw /flash
rm -f /flash/rocknix.no-nspawn
rm -f /storage/.boot.hint
mount -o remount,ro /flash
reboot
```

Observed after restored normal boot:

- `default.target`: `rocknix-main-space.target`
- `systemctl is-system-running`: `running`
- `rocknix-main-space.target`: `active`
- `rocknix-guest.service`: `active`
- `rocknix-guest-root-ensure.service`: `active`
- `/flash/rocknix.no-nspawn`: absent
- `/storage/.boot.hint`: absent
- Current guest revision: `120b8d0d857e6a34c346975a07b6945dd87625c0`

## Final host and guest state

Host final:

```text
identity=ayn,thor
host_build=BUILD_ID="f080b462f54b5807bdd16ac7cc2ab64528b038b1"
default_target=rocknix-main-space.target
system_running=running
failed_units=
rocknix-guest-root-ensure.service=active
rocknix-guest.service=active
rocknix-guest-wifi-ready.service=active
rocknix-guest-promote.service=inactive
markers=clean
revision=120b8d0d857e6a34c346975a07b6945dd87625c0
seed_revision=120b8d0d857e6a34c346975a07b6945dd87625c0
audit=passed
runtime_smoke=passed
quick_soak=passed
```

Guest final:

```text
hostname=bandai
compatible=ayn,thor,qcom,qcs8550,qcom,sm8550
system_running=running
failed_units=
korri-server.service=active
korri-sessiond.service=active
korri-inputd.service=active
korri-compositor.service=active
main-space-pipewire.service=active
main-space-wireplumber.service=active
revision=120b8d0d857e6a34c346975a07b6945dd87625c0
seed_revision=120b8d0d857e6a34c346975a07b6945dd87625c0
```

On-device `/flash` hashes after install:

```text
507b74e0e8c50b54ee14e0b12420b3f9  /flash/SYSTEM
5742950b9939f1034060c995d89eab98  /flash/KERNEL
```

Final ABL checksums remained unchanged from pre-install:

```text
91037267a0578fee2e43ca2a8f109120ce055829edcd860cd117645563bdead6  /dev/disk/by-partlabel/abl_a
91037267a0578fee2e43ca2a8f109120ce055829edcd860cd117645563bdead6  /dev/disk/by-partlabel/abl_b
```

## Caveats / follow-ups

- The first Thor cutover required manual recovery because stale `previous/var/empty` had the immutable bit set. This is already a known operational edge in `docs/ops/sm8550-full-install-safety-audit-2026-05-20.md`; future substrate work should make `rocknix-guest-root-ensure` clear helper-owned immutable metadata before deleting retained previous roots.
- Guest SSH keys are intentionally not shipped in the seed. This acceptance restored the prior operator keys from the retained previous root after reseed. Future substrate work should provide an explicit key-preservation/import path for product-seed reseeds.
- `HandsOnAcceptance` remains deferred: no screen, controller, Moonlight, or gameplay smoke was run.

## Validation summary

- `scripts/tests/product-payload-contract.sh --product thor`: passed
- `scripts/verify-product-payload-fetches --product thor`: verified source/rootfs bytes
- `rocknix_artifact_verify` on run `26616457343`: passed
- Device-side `sha256sum -c ROCKNIX-SM8550.aarch64-20260529.tar.sha256`: passed
- `rocknix-guest-activation-audit --quiet`: passed
- `ROCKNIX_GUEST_LIVE_SMOKE=1 /usr/lib/rocknix-guest-substrate/tests/guest-substrate-runtime-smoke.sh`: passed
- `rocknix-guest-soak --hours 0 --interval-seconds 5`: passed

## Acceptance

`DeviceAccepted` for Nix-on-Rocks on `bandai` / AYN Thor (`ayn,thor`) for the SM8550 Thor product-payload lane.

- `BuildProof`: full `build-sm8550.yml` run `26616457343` succeeded end-to-end with `product=thor`.
- `ArtifactVerified`: full update tar + full image artifact verified locally; SM8550 FAT geometry verified; manifest carries Thor product payload facts.
- `DeviceAccepted`: update applied, KERNEL/SYSTEM md5 match the update tar, ABL unchanged, host running, guest active, active rootfs and substrate facts match the Korri Thor payload.
- `ThreePassAcceptance`: cutover with recovery action, no-op reapply, recovery boundary, and restored-normal cleanup all observed.
- `HandsOnAcceptance`: NotRun/Deferred.
- `ReleasePublication`: Thor seed assets published under `rocknix-product-payload-120b8d0d857e`.
