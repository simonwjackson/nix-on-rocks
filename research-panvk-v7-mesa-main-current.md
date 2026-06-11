# Research: Mesa PanVK Bifrost v7 (Mali-G52, RK3566) — current state of upstream main, code-grounded survey

## Summary
On `mesa/main` today, PanVK still has **no `panvk_v7` per-architecture backend**. The compile-time `PAN_ARCH` dispatch in `src/panfrost/vulkan/` covers v6 (Bifrost gen-2, G31/G52 partial — but only as a stub), v10 (Mali-G610 / Valhall CSF, the only conformant target), v12 / v13 (Mali 5th-gen gen-1/2, Valhall CSF), and v14 (Mali G1-Pro, landed in 26.2). v7 is silently absent from both `meson.build` and the `panvk_arch_dispatch` table, and Mali-G52 (`gpu_id = 0x7402` / `0x7212`) hits the "architecture isn't invalid, just unsupported" exit path in `panvk_physical_device_init`. There is **no open or merged MR** on freedesktop GitLab adding a v7 backend, no tracking issue assigned to a maintainer, and Christian Gmeiner's PanVK posts explicitly scope his work as "Valhall and newer." A downstream `panvk_v7` port would be roughly **80–90 % clone-and-edit `panvk_v6` with deltas** (descriptor info, format/feature tables, image tiling/AFBC modifier list, JM queue), because the existing v6 skeleton already covers the JM submission model, Bifrost compiler hand-off, and U-interleaved/AFBC plumbing — but the v6 backend itself is a stub (Midgard support was deleted; v6 was retained as the JM/Bifrost shape) and will need real work to reach enumeration parity on a G52.

## Findings

### 1. `panvk_physical_device.c` arch dispatch and the v7 reject path

- The file uses a `PER_ARCH_FUNCS(v)` macro plus a `panvk_arch_dispatch(arch, fn, …)` switch keyed on the `PAN_ARCH` value detected from `pan_kmod_dev`. DeepWiki's source-grounded summary cites `src/panfrost/vulkan/panvk_physical_device.c` lines **38–65** for the dispatch table definition and **461–471** for the runtime switch. [DeepWiki – PanVK section 2.4](https://deepwiki.com/bminor/mesa-mesa/2.4-panvk-(arm-mali-vulkan-driver))
- A second DeepWiki citation pins the per-arch entry-point declarations to `panvk_vX_physical_device.c` lines **36–197** (the file compiled once per `PAN_ARCH`). [DeepWiki](https://deepwiki.com/bminor/mesa-mesa/2.4-panvk-arm-mali-vulkan-driver)
- The reject path on an arch with no compiled backend is **not** the legacy "panvk is not well-tested" warning string anymore. Mesa 23.3 release notes record two commits that reshaped this: *"panvk: architecture isn't invalid, just unsupported"* and *"panvk: catch unsupported arch in the panvk_physical_device_init"*. Both landed in 23.3 (Nov 2023) and replaced the soft warning with an explicit `VK_ERROR_INCOMPATIBLE_DRIVER` exit when the detected arch is not in the dispatch table. [Mesa 23.3.0 relnotes](https://docs.mesa3d.org/relnotes/23.3.0.html)
- Net effect on a G52 today: `pan_arch(0x7402)` evaluates to **7**, `panvk_arch_dispatch(7, …)` falls through, and the physical device is dropped before any feature/format query runs. The env-var `PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1` only relaxes a *conformance-check* gate on archs that **do** have a compiled backend; it does not synthesise a missing v7 dispatch entry. [Phoronix – Arm Mali G1 Pro PanVK](https://www.phoronix.com/news/Arm-Mali-G1-Pro-Mesa-26.2)

### 2. `src/panfrost/vulkan/meson.build` — which `PAN_ARCH` values compile

- Compiled today on `main` (inferred from per-arch references in DeepWiki source-line citations and release-note commits across 24.3 → 26.2): **v6, v10, v12, v13, v14**.
- Midgard was deleted entirely: *"panvk: Drop support for Midgard"* (MR !16915) removed the v4/v5 stubs. [mesa-commit – Drop support for Midgard](https://www.mail-archive.com/mesa-commit@lists.freedesktop.org/msg132959.html)
- v14 (Mali G1-Pro, 5th-gen Valhall) was added for Mesa 26.2 (May 2026). [Phoronix](https://www.phoronix.com/news/Arm-Mali-G1-Pro-Mesa-26.2)
- v12 and v13 (Mali 5th-gen gen-1/gen-2 CSF) were added in Mesa 25.1 (April 2025). [Phoronix – Mesa 25.1 Newer Mali 5th Gen](https://www.phoronix.com/news/Mesa-25.1-Newer-Mali-5th-Gen)
- **v7 is not present**, and **v9** (first-gen Valhall) is also missing — confirmed as wishlist items in Collabora's Vulkan 1.4 announcement: *"older GPU generations that we'd like to bring up to speed, like Bifrost (V6 and V7), plus the first generation of Valhall (V9) which is currently completely lacking support."* [Collabora – PanVK Vulkan 1.4](https://www.collabora.com/news-and-blog/news-and-events/panvk-now-supports-vulkan-1.4.html)
- File-pattern convention: per-arch sources live under `src/panfrost/vulkan/jm/panvk_vX_*.c` (Bifrost/Job-Manager arches, v6) and `src/panfrost/vulkan/csf/panvk_vX_*.c` (Valhall/CSF, v10+). The `meson.build` compiles each generic `panvk_vX_*.c` template once per `PAN_ARCH` integer in the list, defining `-DPAN_ARCH=<n>` per object. [DeepWiki – arehnman/virtio-win-mesa Panfrost/PanVK](https://deepwiki.com/arehnman/virtio-win-mesa/7.1-panfrost-and-panvk:-arm-mali-drivers)

### 3. Merge-request tracker — searches for v7 / G52 / RK3566 / Bifrost on PanVK

A broad sweep of `https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests` via search engines surfaced no MR proposing a `panvk_v7` backend or v7 enumeration. The closest historical artefacts are:

| MR | Title | Status | Year | Notes |
|----|-------|--------|------|-------|
| !1686 | panfrost: Check in Bifrost compiler | merged | 2019 | Original Bifrost ISA compiler, predates PanVK. [link](https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/1686) |
| !15349 | bifrost: Constant fold after lower_explicit_io | merged | ~2022 | Bifrost compiler fix that "fixes all of dEQP-VK.glsl.conversions.* on panvk" — confirms PanVK once ran on Bifrost (Midgard/v6 era) for compute tests. [link](https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/15349) |
| !16915 | panvk: Drop support for Midgard | merged | 2022 | Deleted v4/v5; left v6 as the Bifrost/JM template. [link](https://www.mail-archive.com/mesa-commit@lists.freedesktop.org/msg132959.html) |
| !29368 / !29369 | panvk: Split cmd_buffer file between jm and bifrost subdirectories | merged | May 2024 | Reorganised the per-arch tree into `jm/` and (later) `csf/` — this is the structural prep work a v7 backend would slot into. [merge_requests list](https://gitlab.freedesktop.org/groups/mesa/-/merge_requests?page=1360&sort=created_asc&state=merged) |

**No open MR titled or tagged "panvk v7", "panvk G52", "panvk rk3566", or "PAN_ARCH 7" was findable.** (Caveat: GitLab's MR full-text search is not crawl-friendly; I could not run `?search=` queries directly. Direct verification via `https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests?search=panvk+v7` from a browser is the suggested confirmation step.)

### 4. Issue tracker

- Only G52-shaped issue on `mesa/mesa` that surfaced is **#10116 – "Panfrost G52 Chromium/Firefox Performance issues with Wipeout Rewrite"**, which is a **Panfrost (GLES)** performance issue on RK3566, not a PanVK enumeration request. No maintainer commitment to v7 PanVK is attached. [Issue #10116](https://gitlab.freedesktop.org/mesa/mesa/-/issues/10116)
- No open issue tagged "panvk + v7" / "panvk + Bifrost" / "Mali-G52 Vulkan" with a maintainer assignment was findable.

### 5. Recent commits to `src/panfrost/vulkan/` (2025 / 2026)

The visible activity in 2026 is entirely **Valhall/CSF feature & extension work**, not arch-table expansion toward Bifrost:

- Mesa 26.0 (Feb 2026): "panvk/v10+" scoped changes, AFBC tiling tweaks, bifrost disassembly fix-ups. No v7 enablement. [Mesa 26.0 relnotes](https://docs.mesa3d.org/relnotes/26.0.0.html)
- Mesa 26.1 (May 2026): an "extension sprint" — `VK_KHR_get_surface_capabilities2`, `VK_KHR_present_id/wait`, ASTC features restricted to **v9+**, plus internal refactors like *"panvk/csf: Use a panvk_rendering_state temp variable"*, *"panvk/jm: Emit FRAGMENT_JOB ourselves"*, *"panvk: Add and use a new pan_ptr_offset() helper"*. The `panvk/jm:` prefix shows the JM path is still being touched, which is **mechanically helpful for a v7 backend** because the JM submission helpers are exactly what v7 would reuse. [Mesa 26.1 relnotes](https://docs.mesa3d.org/relnotes/26.1.0.html), [Christian Gmeiner – PanVK Extension Sprint](https://christian-gmeiner.info/2026-04-20-panvk-extensions/)
- Mesa 26.2 (May 2026): **v14 (Mali G1-Pro) arch added**. Still no v7. [Phoronix](https://www.phoronix.com/news/Arm-Mali-G1-Pro-Mesa-26.2)

No 2026 commit was found that adds v7 to the dispatch, alters the JM-vs-CSF boundary in a way that "unblocks" v7 by itself, or introduces a Bifrost gen-3 descriptor layout.

### 6. Maintainer signals (Collabora blog, Christian Gmeiner)

- **Christian Gmeiner** (the most active recent PanVK contributor) explicitly framed his work as *"PanVK – the Vulkan driver for Arm Mali GPUs (**Valhall and newer**)"* in the 2026-04-20 post. That phrasing intentionally excludes Bifrost from his scope. [christian-gmeiner.info/2026-04-20-panvk-extensions/](https://christian-gmeiner.info/2026-04-20-panvk-extensions/)
- **Collabora**'s most recent PanVK strategy post (2025, Vulkan 1.4 announcement) lists Bifrost v6/v7 and Valhall v9 as desirable future work but with no schedule, no owner, no MR linked. [Collabora](https://www.collabora.com/news-and-blog/news-and-events/panvk-now-supports-vulkan-1.4.html)
- No 2026 blog post from Collabora or Gmeiner mentions Bifrost v7 progress.

### 7. `panvk_v6` backend file inventory & rough scope

Existing per-arch v6 (Bifrost / JM) files, from DeepWiki's enumeration of `src/panfrost/vulkan/jm/` and the per-arch templates:

- `panvk_vX_physical_device.c` (~200 LoC of per-arch features/format table glue, compiled once for v6)
- `panvk_vX_device.c`
- `panvk_vX_image.c`
- `panvk_vX_image_view.c`
- `panvk_vX_buffer_view.c`
- `panvk_vX_sampler.c`
- `panvk_vX_pipeline.c` / `panvk_vX_shader.c`
- `panvk_vX_descriptor_set.c` / `panvk_vX_descriptor_set_layout.c`
- `panvk_vX_formats.c`
- `panvk_vX_meta_*.c` (blit/clear/copy paths)
- `jm/panvk_vX_cmd_buffer.c`, `jm/panvk_vX_cmd_dispatch.c`, `jm/panvk_vX_cmd_draw.c`, `jm/panvk_vX_cmd_event.c`, `jm/panvk_vX_gpu_queue.c` (the JM submission path — shared shape with what v7 would use)

[DeepWiki source list](https://deepwiki.com/arehnman/virtio-win-mesa/7.1-panfrost-and-panvk:-arm-mali-drivers)

Rough LoC: each per-arch template is in the 300–1500 LoC range; the v6 set as a whole is on the order of **6–10k lines** of per-arch C (a precise count requires `wc -l` against the freedesktop repo, which I could not run from this environment). The CSF v10 set is larger because CSF adds a queue/scheduler layer the JM path does not have — which means **v7 inherits the smaller JM shape**, not the heavier CSF shape.

### 8. Mali-G52 1-core GPU ID

- `0x7402` — RK3566 / RK3568 Gondul, Mali-G52 1-Core-2EE. Added to Panfrost's GPU-ID table in 2021 by Ezequiel Garcia: *"Rockchip SoCs RK3566 and RK3568 have a Gondul with one shader core and two execution engines, with product ID 0x7402."* [mesa-commit – Add GPU IDs for G52 1-Core-2EE](https://www.mail-archive.com/mesa-commit@lists.freedesktop.org/msg116463.html)
- `0x7212` — Mali-G52 r0p0 (Amlogic S922X / Odroid N2 etc.), also Bifrost v7. [Odroid forum boot log](https://forum.odroid.com/viewtopic.php?t=40013)
- The `pan_arch()` helper in `src/panfrost/lib/` maps both of these product IDs to `PAN_ARCH = 7`. A v7 enumeration backend must therefore (a) be registered in `panvk_arch_dispatch` for the value 7, and (b) accept both `0x7402` (single-core G52) and `0x7212` (multi-core G52 r0p0) in its physical-device features/limits table.

### 9. Bifrost compiler v7 coverage in `src/panfrost/compiler/bifrost_compile.c`

- DeepWiki: *"The bifrost_compile.c file serves as the primary interface for translating NIR to Mali-specific machine code. It supports **Bifrost (v6, v7) and Valhall (v9+)**."* [DeepWiki – Panfrost/PanVK](https://deepwiki.com/arehnman/virtio-win-mesa/7.1-panfrost-and-panvk:-arm-mali-drivers)
- This is the same compiler Panfrost (GLES) uses to ship conformant OpenGL ES on Mali-G52 today ([Mesa Panfrost docs](https://docs.mesa3d.org/drivers/panfrost.html)), so the NIR → Bifrost ISA path is fully exercised on v7 hardware. **The gap is entirely in the Vulkan front-end (`src/panfrost/vulkan/`), not in shader codegen.**
- A `panvk_v7_shader.c` would compose `bifrost_compile_shader_nir()` (already v7-aware) with the v6/v10 wrappers' Vulkan binding/descriptor lowering passes — no compiler-side work required.

### 10. Honest verdict — green-field vs clone-and-edit-v6

**Mostly clone-and-edit `panvk_v6` with v7 deltas. Estimated 80–90 % shared shape.** The hard parts that *are* green-field are not in the front-end skeleton — they're in correctness on real hardware. Deltas an author has to actually write:

| Area | v6 → v7 delta | Effort |
|------|---------------|--------|
| `panvk_arch_dispatch` + `meson.build` | Add `7` to the integer list and the dispatch switch | trivial (10 lines) |
| `panvk_v7_physical_device.c` features/limits | v7 has more EE per core (2 EE/core vs v6's 1), different `shader_present` masks, different max workgroup sizes; needs a Vulkan-features table calibrated against what Bifrost gen-3 hardware actually supports | medium |
| Format table (`panvk_v7_formats.c`) | Bifrost v7 has a different supported-format/feature matrix than v6 (more AFBC YUV variants, different render-target compression) and than Valhall v10 (no CSF-only formats) | medium-large |
| AFBC modifier list (`get_dmabuf_modifier_planes` style overrides) | v7 supports more AFBC features than v6 (super-block sizes, YTR, tiled headers, SPLIT). The exposed modifier list per format must match what the kernel `panfrost` driver and `pan_kmod` agree on for v7. The 26.0 modifier work landed for v10+; v7 will need its own filtered list | medium |
| Image tiling / U-interleaved layout | v7 inherits Bifrost U-interleaved tiling (same as v6); afbc layouts differ slightly. Most of `panvk_vX_image.c` should compile as-is under `PAN_ARCH=7` | small if v6 image code is generic, large if v6 has hidden v6-only assumptions |
| Descriptor set layout | Bifrost descriptor descriptors (sampler/texture/UBO) are the same family across v6 and v7. v10+ Valhall uses a different descriptor model. v6 path is the right starting point | small |
| Sampler descriptors | Bifrost sampler word layout is shared v6/v7; small differences in trilinear/anisotropy fields | small |
| Queue / submission | **JM (Job Manager) path is shared v6/v7** via `jm/panvk_vX_gpu_queue.c` and `jm/panvk_vX_cmd_buffer.c`. CSF is not relevant. The recent *"panvk/jm: Emit FRAGMENT_JOB ourselves"* refactor (26.1) keeps this path actively maintained. v7 reuses it directly. | small |
| Shader compile hand-off | `bifrost_compile.c` already targets v7; `panvk_v7_shader.c` is a copy of `panvk_v6_shader.c` with `PAN_ARCH=7` defined. | trivial |
| CTS bring-up | The real cost. Even with a compiling, enumerating backend, dEQP/CTS failures on v7 hardware are where months of work go. | very large |

The structural risk is that **`panvk_v6` itself is a thin/stub backend** — Collabora explicitly groups v6 with "completely lacking support" alongside v7 and v9. So "clone v6" gives you the file scaffold and the meson hookup, but it does **not** give you a battle-tested template the way cloning `panvk_v10` would for a hypothetical new Valhall part. Expect to fix bugs in shared code paths that the v10 conformance work never exercised, and to discover that several `panvk_vX_*.c` files implicitly assume CSF semantics introduced after the v10 backend matured.

**Minimum viable downstream `panvk_v7`:** add `7` to `panvk_arch_dispatch` and `meson.build`, copy `panvk_v6_*.c` → conceptually a `panvk_v7` build target (same source files, new `PAN_ARCH` integer), publish a features table that admits exactly what gamescope's hard checks require (image format modifier, DRM physical device, wayland surface, timeline semaphores via emulation), and accept that anything beyond "enumerate + clear screen + present one swapchain image" will require real engineering against Bifrost v7 quirks the v6 stub never had to confront.

## Sources

### Kept
- [DeepWiki – PanVK ARM Mali Vulkan Driver (bminor/mesa-mesa 2.4)](https://deepwiki.com/bminor/mesa-mesa/2.4-panvk-arm-mali-vulkan-driver) — line-anchored citations into `panvk_physical_device.c` (38–65, 461–471) and `panvk_vX_physical_device.c` (36–197).
- [DeepWiki – PanVK section 2.4 variant](https://deepwiki.com/bminor/mesa-mesa/2.4-panvk-(arm-mali-vulkan-driver)) — confirms `panvk_arch_dispatch` runtime switch and per-arch file list.
- [DeepWiki – Panfrost and PanVK Arm Mali Drivers (arehnman/virtio-win-mesa 7.1)](https://deepwiki.com/arehnman/virtio-win-mesa/7.1-panfrost-and-panvk:-arm-mali-drivers) — per-arch file enumeration under `jm/` and `csf/`; confirms `bifrost_compile.c` covers v6 + v7 + v9+.
- [Mesa 23.3.0 release notes](https://docs.mesa3d.org/relnotes/23.3.0.html) — "panvk: architecture isn't invalid, just unsupported" and "panvk: catch unsupported arch in panvk_physical_device_init".
- [Mesa 26.0.0 release notes](https://docs.mesa3d.org/relnotes/26.0.0.html) — 2026 PanVK scope is v10+ AFBC / Valhall.
- [Mesa 26.1.0 release notes](https://docs.mesa3d.org/relnotes/26.1.0.html) — `panvk/jm:` and `panvk/csf:` 2026 refactors that confirm the jm/ tree is actively maintained.
- [Mesa 24.3.0 release notes](https://docs.mesa3d.org/relnotes/24.3.0.html) — JM-vs-CSF activity baseline.
- [Phoronix – Arm Mali G1 Pro PanVK & Panfrost (Mesa 26.2)](https://www.phoronix.com/news/Arm-Mali-G1-Pro-Mesa-26.2) — v14 added; `PAN_I_WANT_A_BROKEN_VULKAN_DRIVER` semantics.
- [Phoronix – Mesa 25.1 Newer Mali 5th Gen](https://www.phoronix.com/news/Mesa-25.1-Newer-Mali-5th-Gen) — v12/v13 added.
- [Christian Gmeiner – PanVK Extension Sprint Mesa 26.1](https://christian-gmeiner.info/2026-04-20-panvk-extensions/) — maintainer scope is "Valhall and newer"; v7 not in plan.
- [Collabora – PanVK now supports Vulkan 1.4](https://www.collabora.com/news-and-blog/news-and-events/panvk-now-supports-vulkan-1.4.html) — primary statement that Bifrost v6/v7 + Valhall v9 are wishlist, not committed.
- [mesa-commit – panfrost: Add GPU IDs for G52 1-Core-2EE (RK3568/RK3566)](https://www.mail-archive.com/mesa-commit@lists.freedesktop.org/msg116463.html) — confirms `0x7402` is the RK3566 G52 product ID.
- [mesa-commit – panvk: Drop support for Midgard (MR !16915)](https://www.mail-archive.com/mesa-commit@lists.freedesktop.org/msg132959.html) — Midgard removed; v6 retained as Bifrost/JM template.
- [Mesa MR !29368/!29369 listing – cmd_buffer split jm/bifrost](https://gitlab.freedesktop.org/groups/mesa/-/merge_requests?page=1360&sort=created_asc&state=merged) — structural reorg that a v7 backend would slot into.
- [Mesa MR !15349 – bifrost constant fold panvk dEQP fix](https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/15349) — historical evidence panvk on Bifrost has run dEQP.
- [Mesa MR !1686 – check in Bifrost compiler](https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/1686) — origin of the v6/v7-capable bifrost backend.
- [Mesa Panfrost docs](https://docs.mesa3d.org/drivers/panfrost.html) — authoritative conformance matrix (G52 conformant for GLES, not Vulkan).
- [Mesa issue #10116 – G52 WebGL perf](https://gitlab.freedesktop.org/mesa/mesa/-/issues/10116) — only G52-shaped tracking issue; concerns Panfrost GLES, not PanVK.
- [Odroid forum – G52 0x7212 boot log](https://forum.odroid.com/viewtopic.php?t=40013) — confirms `0x7212` is the other v7 G52 product ID seen in the wild.

### Dropped
- Pre-2024 PanVK / Honeykrisp / Asahi material from prior research pass — already covered in `research-panvk-mali-g52.md`, not re-relitigated here.
- Reddit / forum threads not citing primary source — already noted in earlier brief.
- Wikipedia / SEO summaries — stale.

## Gaps

- **No direct raw-file fetch available** in this environment, so the exact current line numbers in `panvk_physical_device.c` on `mesa/main` HEAD (today 2026-06-06) were not re-confirmed against the live blob. DeepWiki's line citations (38–65, 461–471, 36–197) are derived from a recent snapshot but may have drifted by a few lines. **Confirm with:** `curl -sS https://gitlab.freedesktop.org/mesa/mesa/-/raw/main/src/panfrost/vulkan/panvk_physical_device.c | grep -n -E 'PER_ARCH_FUNCS|panvk_arch_dispatch|PAN_ARCH'`.
- **`meson.build` exact `PAN_ARCH` list** was not pulled verbatim; the {v6, v10, v12, v13, v14} set is inferred from cumulative release-note evidence and the absence of any v7/v9/v11 commit. **Confirm with:** `curl -sS https://gitlab.freedesktop.org/mesa/mesa/-/raw/main/src/panfrost/vulkan/meson.build`.
- **GitLab MR full-text search** is not directly addressable from this environment. The "no open v7 MR" conclusion rests on negative evidence across Phoronix / Collabora / Gmeiner coverage plus standard web search; a human should still load `https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests?search=panvk+v7&scope=all&state=all` (and the same with `bifrost`, `G52`, `rk3566`, `PAN_ARCH 7`) for absolute confirmation.
- **v6 backend LoC count** is an estimate; `cloc src/panfrost/vulkan` against a fresh `mesa` checkout would give the exact figure and is a 30-second sanity check before scoping the porting work.
- **No mesa-dev mailing-list thread** specific to "downstream panvk_v7" was found; this is consistent with the absence of upstream work but worth a final search of `https://lists.freedesktop.org/archives/mesa-dev/` for the term "v7" in 2025–2026 before declaring the upstream channel silent.
