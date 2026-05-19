# Handoff: ROCKNIX Level N + VM graphics-freeze research

## Current task focus

The conversation has moved from Layer 14 / Level N architecture into a feasibility question:

> Can we create a Nix flake MVP for a thin VM graphics path on Snapdragon/Adreno, specifically QEMU/crosvm + virtio-gpu Venus/rutabaga/gfxstream or Turnip native-context, as a possible route toward freezing BOTW/Cemu state?

The next session should likely continue by designing or implementing a small flake-based MVP that validates the virtual GPU stack before attempting Cemu/BOTW.

## Repository / workspace context

- Current working directory in this session: `/home/simonwjackson/code/sandbox/rocknix`
- Current branch observed by `git branch --show-current`: `custom`
- Current untracked files in this checkout:
  - `base-architecture-minimum.md`
  - `base-safety-review.md`
  - `base-scout-packages.md`
  - `base-scout-sm8550.md`
  - `rebase-plan-learnings.md`
  - `rebase-plan-repo-research.md`
- There is a sibling checkout/artifact location:
  - `/home/simonwjackson/code/sandbox/rocknix-nix-guest/`

Important: earlier in the conversation, a Level N report was written to the sibling checkout, not the current `rocknix` checkout:

- `/home/simonwjackson/code/sandbox/rocknix-nix-guest/docs/thinking/2026-05-10-rocknix-level-n-8-12-report.md`

Reference that report rather than duplicating its contents. It covers stages 8–12:

8. Host product-path amputation  
9. Host package/service closure minimization  
10. Nix-built guest/rootfs activation as source of truth  
11. Nix-owned boot artifacts  
12. Level N

## Conversation state / assumptions

The user explicitly asked to assume stages 1–7 are validated:

1. Nix guest boots as main product space.
2. Guest owns compositor/session.
3. Guest owns display config.
4. Guest runs demanding emulator workload.
5. Guest owns emulator launch/runtime contract.
6. Guest owns product UX / launcher loop.
7. Guest owns device-facing policy sufficiently.

Given that assumption, the prior strategic conclusion was:

- Next architectural frontier is subtractive: make ROCKNIX do less.
- Stages 8–12 are about host amputation, host closure minimization, Nix-native guest activation/rollback, then Nix-owned boot artifacts.
- Do not suggest porting more emulators as the main next step.

## Freeze-to-disk discussion summary

The user asked whether a game could be “frozen” to disk.

Current reasoning:

- Emulator-native savestates are best where available.
- Cemu/BOTW likely does not have robust emulator-native savestate support.
- CRIU/process checkpointing is unlikely to handle Vulkan/DRM/Wayland/JIT/audio/input state.
- nspawn/container checkpoint is also unlikely because the guest shares real host kernel/devices.
- Whole-device hibernate might work in theory but is platform/kernel risky and not per-game.
- RAM quick-resume is more plausible than disk freeze for the current direct-GPU path.
- Disk freeze becomes more plausible only if the game runs inside a VM where GPU/device state is virtualized and snapshot-safe.

## Web/search findings on VM graphics paths

The user asked to search for QEMU/crosvm + virtio-gpu Venus on Snapdragon. Relevant findings:

- QEMU supports virtio-gpu Venus for Vulkan translation with recent virglrenderer/Mesa.
- QEMU docs describe:
  - `-device virtio-gpu-gl,hostmem=8G,blob=true,venus=true`
- QEMU docs also describe rutabaga/gfxstream:
  - `-device virtio-gpu-rutabaga,gfxstream-vulkan=on,cross-domain=on,hostmem=8G,...`
- `rutabaga_gfx`/gfxstream may be more aligned with Android/ChromeOS/Snapdragon VM graphics lineage than plain Venus.
- Turnip native-context / virtgpu DRM native context may be most interesting for near-native Adreno performance, but appears less straightforward as an MVP.
- Even with virtual GPU, VM snapshot/freeze is not automatically solved; active host-side Vulkan/renderer state may still be hard to serialize.

Useful sources already surfaced:

- Mesa Venus docs: https://docs.mesa3d.org/drivers/venus.html
- QEMU VirtIO-GPU docs: https://www.qemu.org/docs/master/system/devices/virtio/virtio-gpu.html
- Collabora Venus on QEMU: https://www.collabora.com/news-and-blog/blog/2021/11/26/venus-on-qemu-enabling-new-virtual-vulkan-driver
- rutabaga_gfx: https://github.com/magma-gpu/rutabaga_gfx
- Qualcomm VCL VirtIO-GPU OpenCL work: https://www.qualcomm.com/developer/blog/2024/10/vcl-virtio-gpu-opencl-driver

## Local nixpkgs inspection findings

In current nixpkgs (from repo `flake.nix`, `nixos-unstable` input), these are available for `aarch64-linux`:

- `crosvm`: `crosvm-0-unstable-2026-02-13`
- `qemu_kvm`: `qemu-host-cpu-only-10.2.1`
- `qemu`: `qemu-10.2.1`
- `virglrenderer`: `virglrenderer-1.3.0`
- `mesa`: `mesa-26.0.2`
- `rutabaga_gfx`: `rutabaga_gfx-0.1.6`
- `libkrun`: `libkrun-1.17.0`

Important build details observed via derivation inspection:

- `virglrenderer` has:
  - `mesonFlags=-Dvideo=true -Dvenus=true -Ddrm-renderers=amdgpu-experimental,asahi,msm`
- `rutabaga_gfx` has:
  - `mesonFlags=-Dgfxstream=true`
- `qemu` has `rutabaga_gfx` and `virglrenderer` in build inputs and configure flags including:
  - `--enable-opengl`
  - `--enable-virglrenderer`
- `crosvm` package is present, but nixpkgs derivation appears built with only:
  - `buildFeatures=virgl_renderer`
  - not `gfxstream`
- crosvm source has features for:
  - `gfxstream = ["rutabaga_gfx/gfxstream"]`
  - `gfxstream_display = ["gpu_display/gfxstream_display"]`
  - `virgl_renderer = ["devices/virgl_renderer"]`

Conclusion from local inspection:

- Easiest flake MVP is **QEMU first**, not crosvm first.
- QEMU + Venus and QEMU + rutabaga/gfxstream are plausible to package as runner scripts.
- crosvm + gfxstream likely needs a Nix overlay to override cargo features.
- Turnip native-context is probably MVP #3/#4, not first, because obvious QEMU `drm_native_context` support was not found in local QEMU source inspection.

## Recommended MVP sequence

Do not start with BOTW/Cemu.

Suggested proof ladder:

1. Build/run a flake package or app that exposes a QEMU Venus runner.
2. Boot a minimal aarch64 Linux guest under KVM on SM8550.
3. Inside guest, run `vulkaninfo`.
4. Run `vkcube` or a headless Vulkan smoke test.
5. Try VM pause/resume without disk snapshot.
6. Try save/restore snapshot while Vulkan app is idle.
7. Try save/restore while Vulkan app is active.
8. Only after that, try Cemu/BOTW.

Potential runner shapes discussed:

```sh
qemu-system-aarch64 \
  -enable-kvm \
  -machine virt,accel=kvm \
  -cpu host \
  -m 4096 \
  -device virtio-gpu-gl,hostmem=4G,blob=true,venus=true
```

and:

```sh
qemu-system-aarch64 \
  -enable-kvm \
  -machine virt,accel=kvm \
  -cpu host \
  -m 4096 \
  -device virtio-gpu-rutabaga,gfxstream-vulkan=on,cross-domain=on,hostmem=4G,wsi=headless
```

These need real guest kernel/rootfs details before being runnable.

## Existing repo flake

Current `/home/simonwjackson/code/sandbox/rocknix/flake.nix` is a ROCKNIX build environment flake. It currently provides:

- `packages.${system}.rocknix-env`
- `apps.${system}.rocknix-env`
- `devShells.${system}.default`

It does not yet include VM graphics MVP packages/apps.

If implementing, either:

- add new packages/apps to this flake, or
- create a separate experimental flake file/path to avoid polluting the ROCKNIX build env.

Given the user asked “is it possible to create a flake.nix for some kind of MVP,” the next agent should probably propose or implement a minimal experimental flake app rather than large repo integration.

## Suggested skills for next session

- `web-search`: if checking current QEMU/crosvm/rutabaga feature flags, command-line syntax, or known Snapdragon/Adreno issues.
- `se-prototype`: for creating a throwaway flake/runner MVP without committing to architecture.
- `se-plan`: if user wants this turned into an implementation plan.
- `thinking-partner`: if continuing to stress-test whether VM snapshotting is strategically worth pursuing.
- `se-work`: if user explicitly asks to implement the flake/app in the repo.

## Cautions for next agent

- Do not overpromise disk freeze. The current evidence supports a research spike, not a guaranteed BOTW quick-resume solution.
- Keep the first MVP small: prove virtual Vulkan visibility before Cemu.
- Distinguish three paths:
  1. QEMU + Venus — easiest first smoke test.
  2. QEMU + rutabaga/gfxstream — promising and already supported by QEMU docs/nixpkgs deps.
  3. crosvm + gfxstream / Turnip native-context — interesting but likely needs overlay or deeper integration.
- Be careful about checkout confusion: Level N report is in `rocknix-nix-guest`, while current shell is `rocknix`.
