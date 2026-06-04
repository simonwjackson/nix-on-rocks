---
id: task-018
title: Scaffold RK3566 profile surface with static contracts
status: In Progress
priority: high
labels:
  - rg353m
  - rk3566
  - before-device
  - flake
  - guest-profile
  - contracts
  - ci
created: 2026-06-04
source: user
---

# Scaffold RK3566 profile surface with static contracts

## Why it matters

A minimal evaluated RK3566 surface with contracts lets later LLM runs add hardware behavior behind tests instead of inventing structure from scratch or accidentally inheriting SM8550 assumptions.

## Acceptance Criteria

- [ ] `devices/rk3566/README.md` documents the SoC directory purpose and known RG353M constraints.
- [ ] A new `guest/profiles/devices/rg353m.nix` exists with hostname and RK3566 device ID only or similarly minimal safe settings.
- [ ] `flake.nix` exposes the RK3566/RG353M profile through a clear, tested surface without making it the default target.
- [ ] A RK3566 contract script or check asserts the minimal RK3566 profile and flake surface evaluate.
- [ ] Contracts fail with clear messages if RK3566 profile wiring imports SM8550-only audio, input, or display assumptions unintentionally.
- [ ] Existing SM8550 flake outputs, device profiles, and contract checks remain unchanged.
- [ ] CI or `nix flake check` exposes the new contract in a discoverable way.

## Related

- `devices/README.md`
- `devices/rk3566/`
- `guest/profiles/devices/rg353m.nix`
- `flake.nix`
- `nix/tests/flake-surface-contract.nix`
- `scripts/verify-sm8550-contract`
- `scripts/check-boundary-lint`
- `scripts/check-shell-smoke`
- `nix/tests/`
- `.github/workflows/`

## Notes

Logical work group: minimal RK3566 scaffold plus static validation boundary. Consolidates task-004 and task-005.
