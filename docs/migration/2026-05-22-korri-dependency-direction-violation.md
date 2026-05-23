# Korri dependency-direction violation (pre-existing, not introduced by monorepo merge)

**Status:** active migration; tactical Korri pin bump landed before dependency inversion.
**Surfaced during:** U5 aarch64 build attempt on fuji (2026-05-22).
**Resolution branch:** `feat/korri-dependency-inversion`.

## The rule

> **Korri should pull in nix-on-rocks, never the other way around.**

Nix-on-rocks is upstream substrate (guest base, packages, devices, ROCKNIX
patch queue). Korri is downstream composition (kiosk session, frontends,
input daemon, native packages). The flake dependency graph must reflect
that: `korri --inputs--> nix-on-rocks`, never the reverse.

## Current violation

`flake.nix` declares `inputs.korri` and the `mainSpaceConfigurationFor`
helper composes korri's modules and packages directly:

```nix
# flake.nix (line 6)
korri.url = "github:simonwjackson/korri";

# mainSpaceConfigurationFor (lines 67-83)
specialArgs = {
  korriHasKiosk = builtins.hasAttr "korri-kiosk" korri.nixosModules;
};
modules = [
  korri.nixosModules.korri
  ./guest/profiles/main-space.nix
  # ...
  {
    services.korri.client = {
      enable = true;
      package = korri.packages.${targetSystem}.korri-desktop-device;
    };
    services.korri.inputd.enable = true;
  }
];
```

This makes the following outputs require korri:

- `nixosConfigurations.rocknix-guest-main-space`
- `nixosConfigurations.rocknix-guest-main-space-thor`
- `nixosConfigurations.rocknix-guest-main-space-odin2portal`  ← **Sobo's production target**
- `nixosConfigurations.rocknix-guest-main-space-by-compatible`
- `nixosConfigurations.rocknix-guest-stage10-proof-thor`
- `nixosConfigurations.rocknix-guest-stage10-proof-odin2portal`

These outputs are exactly the kiosk-composition targets that conceptually
belong in korri, not in nix-on-rocks.

## Pre-existing, not introduced by monorepo merge

Verified via `git show pre-merge-baseline-2026-05-22:guest/flake.nix`:
identical 7 korri references, identical module wiring. The monorepo-merge
refactor (U1–U6) moved lines around (flake.nix promoted to root, packages
moved to `packages/`, devices carved out) but preserved the korri input
and the main-space composition exactly.

## Operational symptom

The violation manifests as a build failure on fresh aarch64 hosts:

```
error: hash mismatch in fixed-output derivation
       '/nix/store/g6l0jwpvhxpshdbn6cvqms127hcf5ik7-korri-bun-deps-1.drv':
         specified: sha256-Y5e3MOp/FYacoWLsoO04a8DdvJHgEqSwSNNYi3CFxCA=
            got:    sha256-Tsg7HM8JYpi2T0vRLUy7cOMP/ubKFe+4AvhIcDFY6O8=
```

Korri's old `korri-bun-deps` derivation vendored `node_modules` via Bun.
Bun installed platform-conditional packages (e.g. `@rollup/rollup-linux-arm64-gnu`
on aarch64 vs `@rollup/rollup-linux-x64-gnu` on x86_64), and the resulting
`node_modules` tree differed by host platform. The pinned SRI hash matched
whichever platform last regenerated it (presumably x86_64), so a fresh
aarch64 build could not reproduce it.

Korri revision `b0f39a0a31b736b8e057a087ee381215b0744e50` resolves the hash
mismatch by using the bun2nix migration in Korri. Nix-on-rocks is temporarily
pinned to that pre-inversion Korri revision so the old Sobo target remains a
fallback while the ownership boundary is inverted. Do not advance this pin to a
Korri revision that imports nix-on-rocks; that would create a flake cycle during
the coexistence window.

Sobo's currently-running production rootfs predates this drift, or was built on
a host where the corresponding output was already cached. The production rootfs
continues to work. The tactical pin bump restores old-target buildability; it
does not resolve the architectural dependency-direction violation.

## Why not fix in monorepo-merge?

1. **Out of scope.** Monorepo-merge plan 001 is structural consolidation
   (single-flake monorepo + `devices/` slot for upcoming sm8250). Inverting
   the korri dependency direction is a separate, comparable-sized piece of
   work touching two repos.

2. **Touches another repo.** A clean inversion requires changes in `korri`
   (add `inputs.nix-on-rocks`, consume `nixosModules.rocknix-guest-base`,
   move kiosk composition there). Monorepo-merge is a single-repo refactor.

3. **Disrupts Sobo deploy story.** Today Sobo deploys
   `nix-on-rocks#rocknix-guest-main-space-odin2portal`. After inversion it
   would deploy `korri#korri-rocknix-rootfs-odin2portal`. That's a
   deployment-pipeline change worth doing deliberately, not as a side
   effect.

## Resolution sketch (separate branch)

| Step | Repo | Action |
|---|---|---|
| 1 | nix-on-rocks | Remove `inputs.korri` from `flake.nix`; remove all `korri.*` references from `mainSpaceConfigurationFor` |
| 2 | nix-on-rocks | Drop `rocknix-guest-main-space*` outputs (their composition belongs in korri); keep `rocknix-guest` as the bare guest base |
| 3 | nix-on-rocks | Export `nixosModules.rocknix-guest-base` (the module assembly that current `mainSpaceConfiguration` builds on, minus korri-specific bits) |
| 4 | korri | Add `inputs.nix-on-rocks`; consume base modules + packages; export `korri-rocknix-rootfs-{thor,odin2portal}` |
| 5 | sobo | Switch deploy source from `nix-on-rocks#rocknix-guest-main-space-odin2portal` to `korri#korri-rocknix-rootfs-odin2portal` |
| 6 | korri | Separately fix the `korri-bun-deps` aarch64 hash drift (regenerate hash on aarch64 host, or restructure Bun vendoring to be platform-neutral) |

Step 6 has landed first in Korri and is consumed here as a tactical unblock.
The remaining resolution work is the dependency-direction inversion: expose a
nix-on-rocks substrate contract, move Thor/Sobo kiosk appliance composition to
Korri, cut over deploy authority, then remove `inputs.korri` from nix-on-rocks.

## How monorepo-merge proceeds despite this

Before the tactical pin bump, U5 verification of the monorepo-merge refactor on
aarch64 built korri-free targets only:

```bash
# Packages (no korri needed)
nix build .#packages.aarch64-linux.cemu
nix build .#packages.aarch64-linux.steam
nix build .#packages.aarch64-linux.moonlight-embedded
nix build .#packages.aarch64-linux.inputplumber
nix build .#packages.aarch64-linux.sm8550-ayn-odin2-ucm

# Bare guest config (no korri, no main-space)
nix build .#nixosConfigurations.rocknix-guest.config.system.build.toplevel
```

These prove the refactor preserves package and guest-base behavior. After the
tactical pin bump, the korri-composing main-space variants are valid temporary
fallback targets until the inversion branch removes them.

## Sobo deploy strategy under this constraint

Pre-cutover fallback for Sobo deploy of the post-merge state:

1. **Preferred until cutover:** use the existing nix-on-rocks Sobo target as the
   temporary fallback:
   `nix build .#nixosConfigurations.rocknix-guest-main-space-odin2portal.config.system.build.toplevel`
   or the matching `rootfs-odin2portal` artifact.

2. **Do not redeploy Sobo only because this fallback was restored.** The current
   production rootfs continues to work; production redeploy waits for Korri to
   own and verify `korri-rocknix-rootfs-odin2portal`.

3. **Deploy bare `rocknix-guest`** only as a temporary regression (no kiosk, no
   main-space) to prove substrate behavior independently. This is not a Sobo
   kiosk appliance deploy path.

After cutover, deploy authority moves to Korri and the nix-on-rocks fallback
outputs are removed.
