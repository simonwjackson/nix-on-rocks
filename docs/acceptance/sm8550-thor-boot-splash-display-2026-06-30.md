# SM8550 Thor Boot Splash Display Observation — 2026-06-30

## Purpose

This acceptance gate records what the ROCKNIX initramfs boot splash actually
shows on AYN Thor's two built-in panels. It does not claim top-screen-only
behavior unless live observation proves it.

The release-critical requirement for the coordinated rebuild is that Korri
branding is staged through the product payload and appears instead of the
upstream ROCKNIX logo. Top-screen-only splash behavior is a desired product
polish outcome, but it remains characterization-gated.

## Known source and live facts

Record or update these facts before final sign-off:

```text
rocknix_splash_entrypoint=initramfs load_splash() invokes /usr/bin/rocknix-splash
rocknix_splash_framebuffer=/dev/fb0
fb0_name=msmdrmfb
fb0_geometry_observed=1080x1240
fb0_virtual_size_observed=1080x1920
DSI-1_observed=connected/enabled 1080x1240 bottom/smaller panel
DSI-2_observed=connected/enabled 1080x1920 top/taller panel
backlights_observed=/sys/class/backlight/ae94000.dsi.0 /sys/class/backlight/ae96000.dsi.0
```

## Payload and build identity

Fill before observing the boot splash:

```text
nix_on_rocks_commit=
korri_product_rev=
product_payload_lock=product-payload-thor.lock
branding_patch_archive=
branding_patch_sha256=
branding_patch_url=
artifact_run=
artifact_name=
```

## Observation procedure

Use a cold boot or update-apply boot where the splash is visible from power-on
through guest startup. A phone video is acceptable evidence if direct capture is
not possible.

Observe and record:

- Does the splash show Korri branding or upstream ROCKNIX branding?
- Which physical panel(s) light during the splash phase?
- If both panels light, does the logo appear on both, one, or a stretched shared
  framebuffer?
- Is the logo centered relative to the top/taller panel?
- Is the logo centered relative to the bottom/smaller panel?
- Does the display advance from splash to the guest UI without panel freeze,
  `EACCES` storms, or compositor/session restarts?

## Outcome matrix

| Observation | Release interpretation |
|-------------|------------------------|
| Korri logo on top panel, centered acceptably | Branding and preferred Thor splash behavior pass. |
| Korri logo on both panels, centered acceptably on the visible target area | Branding passes; top-screen-only remains optional follow-up. |
| Korri logo on bottom panel only | Branding passes if accepted for this release; top-screen-only is explicitly not achieved and should be tracked as follow-up. |
| Korri logo appears but is visibly mis-centered on the top panel | Branding path passes; geometry polish requires follow-up unless the user makes it blocking. |
| Upstream ROCKNIX logo appears | Branding path fails; do not accept the product-payload promotion. |
| Splash never advances or panels freeze | Display boot gate fails; collect DRM/logind evidence with `sm8550-thor-drm-coldplug-boot-gate-2026-06-30.md`. |

## Evidence

```text
status=NOT_RUN/PASS/FAIL
operator=
date=
video_or_photo_reference=
korri_branding_visible=YES/NO
upstream_rocknix_branding_visible=YES/NO
top_panel_lit=YES/NO
bottom_panel_lit=YES/NO
top_panel_centering=PASS/FAIL/NOT_VISIBLE
bottom_panel_centering=PASS/FAIL/NOT_VISIBLE
top_screen_only_achieved=YES/NO
release_blocking=YES/NO
notes=
```

## Follow-up rule

If Korri branding is visible and the device otherwise passes the boot/display
acceptance gates, do not block the DRM-coldplug fix solely because top-screen-only
splash is not achieved. Capture a follow-up for deeper Thor framebuffer, DRM, or
initramfs display selection work instead.
