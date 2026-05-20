# Legacy guest repo retirement

Date: 2026-05-19
Updated: 2026-05-20

The former guest-source repository, `rocknix-nix-guest`, has been drained into the Nix-on-Rocks product repository.

## Current authority

- Product repo: `https://github.com/simonwjackson/nix-on-rocks`
- Guest source: `nix-on-rocks/guest/`
- Guest seed workflow: `nix-on-rocks/.github/workflows/build-rootfs-seed.yml`
- Host patch queue: `nix-on-rocks/patches/rocknix/`
- Host guest source fetch: pinned `nix-on-rocks` product tarball, extracting `guest/`
- Host seed fetch: pinned `nix-on-rocks` release asset API URLs

## Legacy repo status

`rocknix-nix-guest` is archived and retained only as a relocation pointer for old links, historical tags, and already-published seed references.

It should not receive:

- new guest source changes,
- new seed workflows,
- new product docs,
- new host integration logic,
- new issue/PR-driven development.

If work appears to belong there, move it to one of these homes instead:

| Work type | Destination |
| --- | --- |
| Guest flake, NixOS modules, rootfs packages | `nix-on-rocks/guest/` |
| Guest seed build/release automation | `nix-on-rocks/.github/workflows/build-rootfs-seed.yml` |
| SM8550 host substrate changes | `nix-on-rocks/patches/rocknix/` |
| Product acceptance records | `nix-on-rocks/docs/acceptance/` |
| Product contracts and ops guidance | `nix-on-rocks/docs/contracts/` or `nix-on-rocks/docs/ops/` |
| Upstream ROCKNIX substrate changes | `rocknix` upstream or the Nix-on-Rocks patch queue |

## Retirement checklist

Completed:

- Guest source moved into `nix-on-rocks/guest/`.
- Product docs and acceptance records moved into `nix-on-rocks/docs/`.
- `rocknix-nix-guest` reduced to a relocation README.
- Host package fetch path rewired away from `rocknix-nix-guest` to `nix-on-rocks`.
- Preflight now verifies lock/package alignment and rejects retired `rocknix-nix-guest` archive/release fetch references.
- Legacy repo README updated to say the repo is archived.
- Legacy repo tagged `relocated-to-nix-on-rocks`.
- GitHub Issues, Projects, and Wiki disabled on `simonwjackson/rocknix-nix-guest`.
- GitHub repository `simonwjackson/rocknix-nix-guest` archived.

Remaining optional audit:

- Audit external docs or scripts outside this workspace that still link to `rocknix-nix-guest` for active setup instructions.
