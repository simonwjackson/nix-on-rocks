---
title: ROCKNIX Stage 10 SM8550 guest generation switch proof
date: 2026-05-13
last_updated: 2026-05-13
category: developer-experience
module: ROCKNIX Nix guest
problem_type: architecture_proof
component: generation-management
severity: medium
applies_when:
  - Proving the selected guest system is a Nix generation rather than mutable host-prepared state
  - Importing an off-device NixOS guest generation into an SM8550 ROCKNIX thin-host image
  - Switching and rolling back the guest generation without product UX
resolution_type: proof_record
related_components:
  - rocknix-guest-generation-import
  - rocknix-guest-generation-switch
  - rocknix-guest-activation-audit
  - systemd-nspawn
  - SM8550
  - Odin 2 Portal
tags: [rocknix, nix, stage-10, sm8550, generation-switch, nspawn, odin2portal]
---

# ROCKNIX Stage 10 SM8550 guest generation switch proof

## Result

Stage 10 guest generation authority was proven on **sobo / Odin 2 Portal** on 2026-05-13.

The successful proof showed that an off-device NixOS guest generation can be imported into the persistent guest store, selected as the canonical guest system, booted, audited, and rolled back to the original generation without using host product UX.

Validated sequence:

1. Clean generation A audit passed.
2. Generation B import succeeded through healthy running generation A.
3. Switch A → B succeeded.
4. B booted with selected = legacy = running = B.
5. B proof marker was visible from the live guest namespace at `/etc/rocknix-stage10-proof-marker`.
6. Restore B → A succeeded.
7. A booted with selected = legacy = running = A.
8. Manual generation hold was cleared.
9. `rocknix-guest-promote.service` was started and no-op'd because A was already applied.
10. Host and guest failed units were both `0`.
11. Runtime smoke and live guest smoke passed.

## Evidence

Target device:

```text
hostname: sobo
hardware: Odin 2 Portal
compatible: ayn,odin2portal
LAN IP used during proof: 192.168.1.239
```

Always verify the target identity before repeating this proof:

```sh
tr '\0' '\n' </proc/device-tree/compatible | sed -n '1p'
```

Host and guest sources:

```text
host proof build: 57e15a58737afb746f96aeaa5c15dd5b5f597f71
guest proof source: 0740ecf feat(stage10): expose proof marker guest outputs
restored applied guest rev: d7d5d72821c509ba42b15f2663cd1bfa2e7c5229
```

The main ROCKNIX `custom` branch later advanced to `c2fe115e5c`, so sobo was one host commit behind the branch tip immediately after the proof.

Generation paths:

```text
A: /nix/store/8r0a2kf6m7n904x4wk7hz1nl6gvcimfr-nixos-system-sobo-25.11.20260505.0c88e1f
B: /nix/store/k13azwzj3pbhzbb78d6pd9w3qpwpss4s-nixos-system-sobo-25.11.20260505.0c88e1f
```

Restored live state after the proof:

```text
selected = legacy = running = /nix/store/8r0a2kf6m7n904x4wk7hz1nl6gvcimfr-nixos-system-sobo-25.11.20260505.0c88e1f
applied rev = d7d5d72821c509ba42b15f2663cd1bfa2e7c5229
manual hold = absent
failed host units = 0
failed guest units = 0
```

## What this proves

The important property is not merely that B booted once. The proof establishes Nix-native guest activation and rollback semantics:

```text
Nix builds complete guest system closure
host imports closure into the guest store
host selects one guest generation profile
guest service starts exactly that selected generation
rollback selects the previous Nix generation
```

The selected and legacy profiles plus the live guest `/run/current-system` are the authoritative state. Mutable marker files such as `/etc/rocknix-guest-revision` and `/etc/rocknix-guest-system-path` are corroborating evidence, not the source of truth.

## Bugs found and fixed during the proof

- The device at `192.168.1.239` was sobo/Odin2Portal, not Bandai/Thor. The proof target now must be identified through `/proc/device-tree/compatible` before interpreting results.
- Nix cannot read NUL-delimited `/proc/device-tree/compatible` directly. The host substrate now passes normalized `ROCKNIX_GUEST_DEVICE_COMPATIBLE` into the guest build path.
- The guest by-compatible dispatch initially referenced unpublished `korri-desktop-device`. It now uses the published `korri-desktop-odin` package.
- The import proof marker check had to run inside the guest namespace because the NixOS system `etc` entry is an absolute symlink to another store path.
- The audit proof marker check initially reused a stale guest PID after restart. The audit now re-resolves the live namespace before checking the proof marker.
- Guest Wi-Fi needed to remain unblocked on boot so the restored guest came back cleanly after generation switching.

## Remaining artifacts and cleanup

After documenting evidence, the large proof archive on sobo can be removed if no longer needed:

```text
/storage/.guest/stage10-proof/sobo-B.nar
/storage/.guest/stage10-proof/sobo-B.nar.sha256
```

The import provenance and switch-state records may also remain until the operator intentionally cleans proof state:

```text
/storage/.guest/rocknix-guest-generation-import-candidate
/storage/.guest/rocknix-guest-generation-switch-a
```

Do not remove proof artifacts before the A → B → A evidence has been captured somewhere durable.

## Follow-up work

- Repeat the proof on another SM8550 target, especially Thor/Bandai, without conflating device identities.
- Decide whether to install current ROCKNIX `custom` branch tip `c2fe115e5c` on sobo; the proof itself used `57e15a5873`.
- Continue toward device-generic proof outputs, offline host-side import, and a safer UX for generation management.
- Keep automatic recovery out of this proof shape until selection and rollback semantics are separately designed.

## Related

- `docs/thinking/2026-05-10-rocknix-level-n-8-12-report.md`
- sibling ROCKNIX repo: `../rocknix/documentation/PER_DEVICE_DOCUMENTATION/SM8550/STAGE10_GENERATION_PROOF.md`
- sibling ROCKNIX repo: `../rocknix/docs/plans/2026-05-13-002-feat-stage10-generation-switch-proof-plan.md`
