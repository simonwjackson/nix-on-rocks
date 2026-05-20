# Source Migration Map

Date: 2026-05-19

This is the Phase 0 map for draining product-owned material out of the old working repos into the two long-lived homes:

- `../nix-on-rocks/` owns the Nix-on-Rocks product, SM8550 thin-host build/recovery loop, guest/rootfs sources, seed lifecycle, storage contract, and device acceptance record.
- `../korri/` owns the Korri application, frontend, desktop package, app-level NixOS module, game-stream/app runtime behavior, and Korri-specific device tooling.

Thor still matters. The migration keeps Thor and Odin2Portal as first-class SM8550 guest/device profiles; Odin2Portal is the first externally accepted Nix-on-Rocks host artifact, not the only product target.

## Docs relocated in this pass

All product-owned `docs/` content from `../rocknix/` and `../rocknix-nix-guest/` was moved into `../nix-on-rocks/docs/`.

### From `../rocknix/docs/`

Moved to Nix-on-Rocks:

- `docs/nix-on-rock/product-boundary.md` -> `docs/product/product-boundary.md`
- `docs/nix-on-rock/upstream-intake.md` -> `docs/product/upstream-intake.md`
- `docs/nix-on-rock/sm8550-acceptance.md` -> `docs/acceptance/sm8550-acceptance.md`
- `docs/nix-on-rock/sm8550-device-acceptance-2026-05-18.md` -> `docs/acceptance/sm8550-device-acceptance-2026-05-18.md`
- `docs/brainstorms/*` -> `docs/brainstorms/`
- `docs/plans/*` -> `docs/plans/`
- `storage-audit-2026-05-14.md` -> `docs/ops/storage-audit-2026-05-14.md`

Rationale: these files describe Nix-on-Rocks/Nix-on-ROCK product identity, build evidence, storage/recovery behavior, and migration planning. They should not live in the ROCKNIX substrate checkout.

### From `../rocknix-nix-guest/docs/`

Moved to Nix-on-Rocks:

- `docs/brainstorms/*` -> `docs/brainstorms/`
- `docs/contracts/*` -> `docs/contracts/`
- `docs/plans/*` -> `docs/plans/`
- `docs/solutions/*` -> `docs/solutions/`
- `docs/thinking/*` -> `docs/thinking/`
- `rocknix-nix-guest-scout.md` -> `docs/thinking/rocknix-nix-guest-scout.md`

Rationale: the guest rootfs and device-profile source of truth is moving into Nix-on-Rocks next, so its contract/history docs moved first.

### Existing Nix-on-Rocks docs reorganized

- `docs/ci-fast-builds.md` -> `docs/ci/fast-builds.md`
- `docs/first-slice.md` -> `docs/product/first-slice.md`
- `docs/sm8550-device-acceptance-2026-05-19.md` -> `docs/acceptance/sm8550-device-acceptance-2026-05-19.md`

## Destination structure after doc relocation

- `docs/acceptance/` — BuildProof and DeviceAccepted guidance/evidence.
- `docs/brainstorms/` — product and guest/rootfs brainstorming history.
- `docs/ci/` — build-lane and fast-build guidance.
- `docs/contracts/` — guest lifecycle, storage, fallback, main-space, and soak contracts.
- `docs/migration/` — extraction maps and phase plans.
- `docs/ops/` — operator/device/storage audit notes.
- `docs/plans/` — implementation plans for host, guest, seed, recovery, and product-lane work.
- `docs/product/` — product boundary, upstream-intake policy, and early-slice framing.
- `docs/solutions/` — captured learnings from the old guest/rootfs work.
- `docs/thinking/` — architecture/scout/research notes.

## Kept in Korri

No docs were moved into Korri in this pass because the source docs being drained from `rocknix` and `rocknix-nix-guest` are about the Nix-on-Rocks product/guest substrate. Korri already has its own docs tree and remains the right home for:

- frontend and UI plans;
- Electrobun packaging notes;
- native input bridge docs;
- headless game stream runner docs;
- Korri-specific Odin/development runbooks.

Follow-up: review root-level Korri notes such as `handoff-JlZae9.md`, `korri-frontend-scout.md`, and `device-report.md` and decide whether they should move under `../korri/docs/`.

## Intentionally not moved from ROCKNIX

`../rocknix/documentation/PER_DEVICE_DOCUMENTATION/**` was not moved. That tree is inherited ROCKNIX substrate documentation, not Nix-on-Rocks product-owned documentation. If Nix-on-Rocks needs a product-facing subset, copy or rewrite the relevant SM8550/Odin2Portal/Thor material into `docs/ops/` or `docs/contracts/` rather than making the upstream substrate docs authoritative.

## Phase 1 extraction status

`../rocknix-nix-guest/` code now lives under `../nix-on-rocks/guest/` as the in-repo guest flake. The move preserves these outputs:

- `.#rootfs-thor`
- `.#rootfs-odin2portal`
- Thor main-space profile
- Odin2Portal main-space profile
- stage10 proof profiles for both devices

Nix-on-Rocks can build and release guest seeds from in-repo guest sources via `.github/workflows/build-rootfs-seed.yml`. The old `../rocknix-nix-guest/` repo is left as a relocation pointer.

## Phase 2 extraction target

Keep ROCKNIX host changes as generated patch material under `../nix-on-rocks/patches/rocknix/`. The ROCKNIX checkout should not be the product source of truth; it should be an upstream substrate plus locally applied patch queue.

Phase 2 rewires the host patch queue so `rocknix-guest-substrate/package.mk` fetches the pinned Nix-on-Rocks product tarball, extracts its `guest/` subtree into `/usr/lib/rocknix-guest-substrate/guest/`, and copies shipped contract docs from product-owned `docs/contracts/`. The repo is public as of the 2026-05-20 Phase 5 proof, but the package keeps authenticated-capable `curl_fetch`/`curl_append` helpers so private release assets or future restricted fetch modes can still be supported. GitHub-generated tarball bytes are pinned by SHA256 for the active fetch mode.

## Open decisions

- Whether to keep `../rocknix-nix-guest/README.md` until the repo is retired, or copy it into `docs/guest/legacy-readme.md` during Phase 1.
- Whether Thor and Odin2Portal seed builds share one workflow matrix or separate release workflows.
- Whether the storage audit should be split into separate `ops/` and Korri cleanup docs.
- Whether to rename historical `Nix-on-ROCK` docs in place or keep names as historical records while new docs use `Nix-on-Rocks`.
