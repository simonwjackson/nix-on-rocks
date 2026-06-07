---
module: rg353m-rk3566-graphics
date: 2026-06-06
problem_type: integration_issue
component: tooling
severity: medium
related_components:
  - gamescope-korri
  - mesa-panvk
  - panfrost
  - sway-korri-compositor
  - retroarch
tags:
  - gamescope
  - panvk
  - mali-g52
  - rk3566
  - rg353m
  - vulkan
  - wayland
  - nested-compositor
symptoms:
  - "gamescope aborts at startup: SDL_Vulkan_CreateSurface failed: VK_KHR_wayland_surface extension is not enabled (SIGABRT, exit 134)"
  - "gamescope: failed to find physical device (selects llvmpipe, then aborts)"
  - "vkCreateDevice failed (VkResult -7 EXTENSION_NOT_PRESENT, then -8 FEATURE_NOT_PRESENT)"
  - "physical device doesn't support VK_EXT_physical_device_drm"
  - "Game renders one frame then freezes; RetroArch blocks in wl_display_dispatch_queue, gamescope idle in poll"
root_cause: incomplete_setup
resolution_type: code_fix
---

# Running gamescope on Mali-G52 / PanVK (Rockchip RK3566, Anbernic RG353M)

## Problem

Getting Valve's gamescope to run on the Anbernic RG353M (Rockchip RK3566, Mali-G52, Bifrost v7) using Mesa PanVK + Panfrost as the Vulkan ICD. Out of the box gamescope rejects the GPU, falls back to llvmpipe, and aborts; once it accepts the GPU it fails `vkCreateDevice`; once it creates a device it freezes after a few frames when run nested inside the Korri Sway compositor.

## Symptoms

- `SDL_Vulkan_CreateSurface failed: VK_KHR_wayland_surface extension is not enabled` → `terminate` → SIGABRT (exit 134)
- `[Error] vulkan: failed to find physical device`
- `[Error] vulkan: physical device doesn't support VK_EXT_physical_device_drm`
- `vkCreateDevice failed (VkResult: -7)` then `(-8)`
- Renders ~1–23 frames then freezes; RetroArch stuck in `wl_display_dispatch_queue` (waiting for a frame callback), gamescope idle in `poll()`.

## What Didn't Work

- **Assuming PanVK can't enumerate Mali-G52.** Initial belief (and web research) said PanVK on Bifrost v7 has no usable Vulkan and that libmali/PanVK upstream were the only paths. Wrong. Direct on-device `vulkaninfo` proved PanVK enumerates `Mali-G52 r1` today with `PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1`, and exposes `VK_EXT_physical_device_drm`, `VK_KHR_wayland_surface`, `VK_KHR_swapchain`. The web-research conclusions were materially wrong; on-device probing was the source of truth.
- **`gamescope --allow-deferred-backend`, `--backend headless|sdl`.** None bypass the device-suitability checks; they only relax per-format modifier matching.
- **`GAMESCOPE_DISABLE_EXPLICIT_SYNC` (a custom patch) to fix the freeze.** Did not fix it. The freeze is not an explicit-sync deadlock.
- **`--force-composition`.** Made gamescope output black while RetroArch ran.
- **Hiding / SIGSTOP-ing the Korri webview to "win" the output.** Made the nested freeze *worse* (immediate), because the webview's continuous commits were what drove Sway's repaint clock — which is what delivered the host frame callbacks gamescope (nested) uses as its vblank source.
- **`gamescope --backend drm` with `LIBSEAT_BACKEND=seatd`.** `Could not connect to /run/seatd.sock` (no seatd; root over SSH, no logind session).

## Solution

Two parts: runtime env to make PanVK usable, and downstream gamescope patches for PanVK v7 gaps. The patches live in the Korri repo at `product/vendor/gamescope-korri/patches/` (commits `2804f46`, `263f554`).

### 1. Runtime environment (PanVK on Bifrost v7)

```sh
PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1        # PanVK gates v6/v7/v14 behind this
MESA_VK_VERSION_OVERRIDE=1.2               # PanVK v7 reports apiVersion 1.0; gamescope needs >= 1.2
VK_DRIVER_FILES=<mesa>/share/vulkan/icd.d/panfrost_icd.aarch64.json   # force PanVK, avoid llvmpipe
```

### 2. gamescope-korri patch `0001` (all sub-changes necessary)

Verified by removing each on the working path:

- **Render-only device**: downgrade `physical device has no primary node` from fatal to info. The *Vulkan* device (PanVK on `renderD128`/panfrost) is render-only; the display primary node belongs to `rockchip-drm` `card0`. True in both nested and DRM modes.
- **Optional `VK_EXT_robustness2`**: PanVK v7 lacks it → `vkCreateDevice -7`. Probe and skip the extension + its feature struct.
- **Skip `present_id`/`present_wait` feature structs** when the backend has no Vulkan swapchain → otherwise `-8`.
- **Gate `samplerYcbcrConversion`** on actual support (PanVK reports false) → otherwise `-8`.
- **Force `VK_IMAGE_TILING_LINEAR` for exported images on no-modifier devices.** Required for KMS direct scanout on `rockchip-drm`. Without it: `Failed to prepare 1-layer flip: Invalid argument` (black screen). With it: 0 flip failures, DSI-1 modeset succeeds.

### 3. gamescope-korri patch `0003` (perf, optional)

`GAMESCOPE_DISABLE_PIPELINE_PRECOMPILE=1` skips precompiling the full shader-permutation set. PanVK's Bifrost-v7 compiler is slow enough that precompiling hundreds of pipelines burns a core for minutes. Not required for correctness on the DRM path, but avoids battery/first-launch cost.

### 4. Architecture: run gamescope as the PRIMARY DRM compositor, not nested

The decisive fix for the freeze. Stop the Korri Sway stack to free DRM master, then run gamescope on its own KMS backend:

```sh
systemctl stop korri-sessiond korri-compositor    # frees DRM master on card0
LIBSEAT_BACKEND=builtin gamescope --backend drm -W 640 -H 480 -- \
  retroarch -L mgba_libretro.so "<rom>.gba"
```

Result: RetroArch advances continuously (36s+ measured, 0 frozen samples), 0 KMS flip failures, DSI-1 scanout. `LIBSEAT_BACKEND=builtin` matches how Sway/korri-compositor takes the seat as root.

## Why This Works

- PanVK v7 *is* present in Mesa's `panvk_physical_device.c` arch dispatch (`case 6: case 7: case 14:`) since 25.2, gated behind `PAN_I_WANT_A_BROKEN_VULKAN_DRIVER`. The blockers were: an API-version floor (gamescope requires ≥1.2; PanVK v7 advertises 1.0 unless overridden) and a handful of extensions/features PanVK v7 doesn't expose that gamescope requested unconditionally.
- gamescope's Vulkan device is the render-only Panfrost node, so the `hasPrimary` check must not be fatal; LINEAR tiling makes the composited buffer scannable by the separate `rockchip-drm` display controller (which can't read Panfrost's tiled/AFBC layout via an implicit modifier).
- **The freeze was architectural, not a graphics bug.** Nested in Sway, gamescope uses the host compositor's frame callbacks as its vblank clock. On this stack those callbacks only flow while *another* surface (the Korri Electrobun webview) keeps committing; gamescope's own surface gets `wp_presentation_feedback.discarded` (never `presented`) and its client (RetroArch) never receives frame callbacks. As the primary DRM compositor there is no host to depend on — gamescope drives its own vblank and presents directly via KMS.

## Prevention

- **Probe the device, don't trust web research for bleeding-edge GPU/driver combos.** `vulkaninfo --summary`, per-ICD `VK_DRIVER_FILES`, and `gdb -p <pid> -batch -ex 'thread apply all bt'` on the spinning thread were each decisive and each overturned a wrong assumption. (The spinning `gamescope-shdr` thread backtrace showed `panvk_compile_shaders`, identifying the precompile cost; the `WAYLAND_DEBUG` log showing all-`discarded` feedback identified the nested-clock dependency.)
- **For gamescope on any render-only Vulkan device (Pi 5 V3DV, Mali, etc.): run it as the primary DRM compositor.** Nesting it inside another wlroots compositor couples its vblank to the host and is fragile.
- **Minimize patches empirically.** Removing each suspected-unnecessary change one at a time on the known-good path is what proved LINEAR tiling was required (it wasn't optional as guessed) and that the explicit-sync patch was dead code on the DRM path (removed in `263f554`).
- **`RA/app CPU advancing is not proof of a visible display.** RetroArch utime climbed even while KMS flips failed (black screen). Verify with flip-success logs (`Failed to prepare flip` count == 0) or an actual pixel capture, not just process liveness.

## Related

- `backlog/task-028 - enable-gamescope-on-rg353m-mali-g52-rk3566.md`
- Korri commits `2804f46` (enable), `263f554` (drop unnecessary explicit-sync patch)
- `product/vendor/gamescope-korri/patches/0001-rendervulkan-allow-render-only-vulkan-device.patch`
- `product/vendor/gamescope-korri/patches/0003-rendervulkan-optional-pipeline-precompile.patch`

## Notes

Open follow-up: the product launch should run gamescope as the session compositor (DRM primary) on RG353M rather than nested; the `sessiond` `app.library.launch` RPC currently hits an unrelated `Failed to parse String to BigInt` error in korri-server. DRM-primary "no freeze" was verified via flip-success logs + sustained RetroArch CPU, not a pixel capture (gamescope-as-primary exposes no wlr-screencopy; gamescopectl screenshot returned black, a capture-path artifact).
