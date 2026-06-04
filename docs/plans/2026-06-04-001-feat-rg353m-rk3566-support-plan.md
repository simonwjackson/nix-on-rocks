---
title: "feat: Add RG353M RK3566 support path"
type: feat
status: active
date: 2026-06-04
verify_command: "nix flake check --no-build"
---

# feat: Add RG353M RK3566 support path

## Summary

Add an Anbernic RG353M support path to nix-on-rocks by treating RK3566 as a new SoC lane, not as a small SM8550 device-profile addition. Upstream ROCKNIX already carries the important RK3566 host pieces: U-Boot, kernel patches, RK3566 platform options, RG353-family DTB enrollment, and RG353M hardware quirks. The work in this repo is to make the NixOS guest substrate product/SoC-aware enough to run on the RK3566 host, then validate the real device identity and hardware nodes when the handheld arrives.

The safe execution posture is two-phase:

1. **Before the device arrives:** add durable docs, static contracts, RK3566 scaffolding, substrate gates/prerequisites, and an SD-image build lane without claiming hardware success.
2. **After the device arrives:** capture device evidence first, wire profile selection from that evidence, then bring up display/input/audio/networking and produce a bootable SD image with recovery acceptance.

---

## Problem Frame

nix-on-rocks currently proves its NixOS guest substrate on SM8550 devices. The RG353M is a Rockchip RK3566 handheld with a different bootloader, image shape, GPU, audio topology, device-tree identity behavior, and performance envelope. A direct port that reuses SM8550 assumptions would be brittle.

The key question is not whether Linux can boot on RG353M. ROCKNIX already supports the RK3566 family. The key question is whether nix-on-rocks can expose a second, safe guest-substrate lane whose contracts do not depend on SM8550/Qualcomm details.

---

## Requirements

- R1. Record RG353M/RK3566 source facts in a durable repo document before hardware work begins.
- R2. Preserve SM8550 behavior while adding RK3566 extension points.
- R3. Treat RK3566 as a separate SoC lane with explicit contracts, not implicit SM8550 fallback behavior.
- R4. Use the actual device-tree model/compatible evidence from the physical RG353M before finalizing profile selection.
- R5. Build RK3566 artifacts as SD-card U-Boot/extlinux images, not SM8550 fastboot/ABL payloads.
- R6. Keep destructive storage operations out of scope until an explicit later decision is made with hardware evidence.
- R7. Prove each meaningful slice with static checks, artifact checks, or on-device acceptance evidence.

---

## Scope Boundaries

### In scope

- RK3566/RG353M support planning and probe protocol.
- RK3566 flake/profile scaffolding.
- RK3566 static contract checks.
- ROCKNIX guest-substrate gate/prerequisite changes for RK3566.
- RK3566 SD image build and artifact verification lane.
- Hardware evidence capture after device arrival.
- Display/touch/input/audio/network bring-up after evidence exists.
- Recovery/no-nspawn acceptance for the first integrated image.

### Out of scope for the first support path

- Steam viability on RG353M.
- Cemu viability on RG353M.
- Moonlight hardware decode parity with SM8550.
- Proprietary libmali Vulkan optimization as a blocker.
- Any destructive eMMC clearing, zeroing, repartitioning, or Android overwrite.
- General RK3566 support for every device in the ROCKNIX RK3566 family.

### Explicit safety boundary

**Do not zero, overwrite, repartition, or otherwise modify RG353M eMMC unless a later plan explicitly approves that operation after device evidence is captured.** Community docs mention eMMC bootloader interactions for some RG3566 Anbernic devices, but this plan keeps first bring-up on removable SD media and treats eMMC changes as destructive follow-up work requiring explicit human approval.

---

## Source Facts and Prior Art

### Local ROCKNIX RK3566 support

ROCKNIX already has a RK3566 device directory:

- `work/rocknix/projects/ROCKNIX/devices/RK3566/options`
- `work/rocknix/projects/ROCKNIX/devices/RK3566/linux/linux.aarch64.conf`
- `work/rocknix/projects/ROCKNIX/devices/RK3566/patches/linux/`
- `work/rocknix/projects/ROCKNIX/devices/RK3566/packages/u-boot-Generic/package.mk`
- `work/rocknix/projects/ROCKNIX/devices/RK3566/bootloader/update.sh`

Important current option values from `work/rocknix/projects/ROCKNIX/devices/RK3566/options`:

- `HW_CPU="Rockchip RK3566"`
- `BOOTLOADER="u-boot"`
- `KERNEL_TARGET="Image"`
- `MALI_FAMILY="bifrost-g52"`
- `GRAPHIC_DRIVERS="mali panfrost"`
- `PREFER_GLES="yes"`
- `VULKAN_SUPPORT="yes"`
- `DISPLAYSERVER="wl"`
- `WINDOWMANAGER="swaywm-env"`
- `PIPEWIRE_SUPPORT="yes"`
- current cmdline: `quiet console=ttyS2,1500000 console=tty0 systemd.debug_shell=ttyS2`

### RK3566 image enrollment

`work/rocknix/projects/ROCKNIX/config.xml` enrolls RK3566 as a `Generic` subdevice with `mkimage_options="dtb,extlinux,uboot"` and an FDT directory. The Generic list includes `rk3566-anbernic-rg353p`, `rk3566-anbernic-rg353ps`, `rk3566-anbernic-rg353v`, and `rk3566-anbernic-rg353vs`.

The RG353M is not listed as a separate DTB entry in that local config. Upstream U-Boot identifies RG353M and uses the RG353P DTB path for it.

### U-Boot Generic path

`work/rocknix/projects/ROCKNIX/devices/RK3566/packages/u-boot-Generic/package.mk` builds:

- `PKG_UBOOT_CONFIG="anbernic-rgxx3-rk3566_defconfig"`
- BL31: `rk35/rk3568_bl31_v1.45.elf`
- DDR TPL: `rk35/rk3568_ddr_1056MHz_v1.23.bin`

Research against upstream U-Boot shows RG353M is detected by the Anbernic RGXX3 RK3566 board code and mapped to `rk3566-anbernic-rg353p.dtb`, with runtime model/panel fixups.

### RG353M hardware quirks in ROCKNIX

ROCKNIX has a per-device quirk directory:

- `work/rocknix/projects/ROCKNIX/packages/hardware/quirks/devices/Anbernic RG353M/001-device_config`
- `work/rocknix/projects/ROCKNIX/packages/hardware/quirks/devices/Anbernic RG353M/020-gpios`
- `work/rocknix/projects/ROCKNIX/packages/hardware/quirks/devices/Anbernic RG353M/040-display`
- `work/rocknix/projects/ROCKNIX/packages/hardware/quirks/devices/Anbernic RG353M/info.d/`

Observed quirk facts:

- `DEVICE_HAS_TOUCHSCREEN="true"`
- `DEVICE_FAKE_JACKSENSE="false"`
- `DEVICE_WIFI="0"`
- `DEVICE_PWM_MOTOR="pwmchip1"`
- display adjustment script reads connector information around `Connector: 133`

### Hardware expectations

Expected hardware profile from research:

- SoC: Rockchip RK3566, Cortex-A55 class CPU.
- GPU: Mali-G52/Bifrost; prefer Panfrost/GLES for initial support.
- Display: 640x480 MIPI DSI panel with RG353-family panel variants.
- Audio: RK817 PMIC/codec path, not SM8550 WCD938x/Q6 routing.
- WiFi/Bluetooth: RTL8821CS-class Realtek path; ROCKNIX carries `rtw88_core disable_lps_deep=y` workaround.
- Boot: U-Boot/extlinux from SD/eMMC, not qcom-abl/fastboot.
- Storage target for first bring-up: removable SD card only.

---

## Key Design Decisions

### Decision 1: Add RK3566 as a SoC lane, not as an SM8550 variant

SM8550 and RK3566 differ in bootloader, image shape, GPU, audio, input, debug TTY, and performance. RK3566 should get an explicit profile/module surface such as `rocknix.rk3566.*` or a deliberately generalized device abstraction created by a refactor. It should not silently inherit SM8550 defaults.

### Decision 2: Use hardware evidence for profile identity

U-Boot may expose RG353M through an RG353P DTB plus a runtime model fixup. Profile selection must not assume the first `/proc/device-tree/compatible` string will be `anbernic,rg353m`. The after-device evidence run records model and compatible strings first; selection logic then follows the real device.

### Decision 3: Start with Panfrost/DRM, defer proprietary Mali/Vulkan tuning

The initial product target is a working guest substrate, not high-end emulation. Panfrost/DRM is the simplest guest graphics boundary. Proprietary `libmali`, `/dev/mali0`, Cemu, Steam, and Moonlight decode tuning are follow-up decisions after boot/display/input/audio are stable.

### Decision 4: Keep first boot on SD card and protect eMMC

An SD-card image is the safe bring-up artifact. eMMC bootloader clearing or Android overwrite is not part of this plan.

---

## Logical LLM Work Groups

These backlog items are deliberately PR-sized for LLM implementation runs. The numbers reflect current backlog IDs after consolidation.

### Before the RG353M arrives

1. `task-001`: Document RG353M RK3566 support plan and probe protocol.
2. `task-002`: Add RG353-family device identity selection contracts.
3. `task-003`: Extract product-agnostic seams from SM8550 guest modules.
4. `task-018`: Scaffold RK3566 profile surface with static contracts.
5. `task-019`: Enable RK3566 host substrate prerequisites and gates.
6. `task-008`: Add RK3566 SD image build lane and artifact checks.

### After the RG353M arrives

1. `task-020`: Capture RG353M identity evidence and wire profile selection.
2. `task-021`: Bring up RG353M display touchscreen and controls.
3. `task-013`: Bring up RK3566 RK817 audio in guest.
4. `task-014`: Stabilize RG353M WiFi and Bluetooth path.
5. `task-022`: Produce bootable RG353M SD image with recovery acceptance.
6. `task-017`: Tune RK3566 guest footprint for RG353M constraints.

---

## Arrival Probe Protocol

Run this before implementing post-arrival code. Prefer a known-good stock/ROCKNIX boot from removable SD. Save the output into a dated evidence document under `docs/brainstorms/evidence/`, for example `docs/brainstorms/evidence/2026-06-DD-rg353m-first-boot-probe.md`.

### 0. Record probe context

```sh
uname -a
cat /etc/os-release 2>/dev/null || true
mount | sed -n '1,80p'
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINTS
```

Record:

- Which image/OS was booted.
- Whether boot came from SD card or eMMC.
- Whether eMMC was left untouched.

### 1. Model and compatible strings

```sh
printf 'model: '
tr '\0' '\n' </proc/device-tree/model 2>/dev/null || cat /proc/device-tree/model 2>/dev/null || true

printf '\ncompatible strings:\n'
tr '\0' '\n' </proc/device-tree/compatible

printf '\nchosen DTB hints from cmdline:\n'
cat /proc/cmdline
```

This evidence decides whether profile selection keys on `anbernic,rg353m`, `anbernic,rg353p`, model text, or an explicit RG353-family alias rule.

### 2. Display, panel, DRM, and backlight

```sh
printf '\nDRM devices:\n'
ls -la /dev/dri 2>/dev/null || true

printf '\nDRM sysfs connectors:\n'
find /sys/class/drm -maxdepth 2 -type l -o -type d | sort

printf '\nBacklight devices:\n'
find /sys/class/backlight -maxdepth 2 -type l -o -type d | sort

printf '\nPanel/display dmesg:\n'
dmesg | grep -Ei 'panel|dsi|drm|display|backlight|newvision|nv3051|sitronix|st7703' || true
```

If ROCKNIX tools are present, also capture:

```sh
drm_tool list 2>/dev/null || true
```

Record the connector/output name Sway should use and whether the panel appears landscape-native at 640x480.

### 3. Audio hardware and mixer topology

```sh
printf '\nALSA cards:\n'
aplay -l

printf '\nALSA devices:\n'
aplay -L | sed -n '1,160p'

printf '\nSound sysfs:\n'
find /proc/asound -maxdepth 2 -type f -o -type l | sort | sed -n '1,160p'

printf '\nAudio dmesg:\n'
dmesg | grep -Ei 'rk817|audio|codec|alsa|asoc|speaker|headphone|jack|amp|pipewire|wireplumber' || true
```

If `amixer` is available:

```sh
amixer -c 0 scontents 2>/dev/null | sed -n '1,220p' || true
amixer -c 1 scontents 2>/dev/null | sed -n '1,220p' || true
```

Record the actual card names before creating RK3566 audio config. Do not reuse SM8550 UCM assumptions.

### 4. Input, controls, power, volume, rumble, and touchscreen

```sh
printf '\nInput devices:\n'
cat /proc/bus/input/devices

printf '\nInput event nodes:\n'
for event in /sys/class/input/event*; do
  [ -e "$event" ] || continue
  printf '%s: ' "$event"
  cat "$event/device/name" 2>/dev/null || true
done

printf '\nInput dmesg:\n'
dmesg | grep -Ei 'input|gpio-keys|adc|joystick|gamepad|touch|goodix|hynitron|cst|pwm|vibrator|rumble' || true
```

If `evtest` is available, run it interactively for each likely control device and record the event node/name mapping:

```sh
evtest
```

Capture button, d-pad, shoulder, trigger, analog stick, power, volume, and touchscreen event names.

### 5. WiFi and Bluetooth

```sh
printf '\nNetwork links:\n'
ip link show

printf '\nWireless devices:\n'
iw dev 2>/dev/null || true
rfkill list 2>/dev/null || true

printf '\nLoaded Realtek/WiFi modules:\n'
lsmod | grep -Ei 'rtw|8821|8723|bluetooth|btusb|hci|sdio' || true

printf '\nWiFi/Bluetooth dmesg:\n'
dmesg | grep -Ei 'rtw|rtl|8821|8723|sdio|wifi|wlan|bluetooth|bt_|hci|firmware' || true

printf '\nModprobe config snippets:\n'
grep -R "rtw88_core" /etc/modprobe.d /usr/lib/modprobe.d 2>/dev/null || true
```

Record whether `rtw88_core disable_lps_deep=y` is present and whether WiFi/audio interference is observed.

### 6. GPU, devfreq, and graphics path

```sh
printf '\nGPU/render nodes:\n'
ls -la /dev/dri 2>/dev/null || true

printf '\nDevfreq paths:\n'
find /sys/class/devfreq /sys/devices -maxdepth 4 -type d -iname '*gpu*' 2>/dev/null | sort | sed -n '1,120p'

printf '\nGPU dmesg:\n'
dmesg | grep -Ei 'mali|panfrost|bifrost|gpu|devfreq|vulkan|mesa' || true
```

If available:

```sh
glxinfo -B 2>/dev/null || true
vulkaninfo --summary 2>/dev/null || true
```

Initial support should accept Panfrost/OpenGL or GLES. Do not block first boot on Vulkan.

### 7. Storage and boot safety

```sh
printf '\nBlock devices:\n'
lsblk -o NAME,PATH,SIZE,TYPE,FSTYPE,LABEL,PARTLABEL,UUID,MOUNTPOINTS

printf '\nMounted flash/storage:\n'
findmnt /flash /storage 2>/dev/null || true

printf '\nBoot files on flash, if mounted:\n'
find /flash -maxdepth 3 -type f 2>/dev/null | sort | sed -n '1,160p' || true
```

Do not run destructive commands such as `dd if=/dev/zero of=/dev/mmcblk0`, `sgdisk --zap-all`, `mkfs.*`, or bootloader writes during this probe.

### 8. Guest-substrate readiness

After a nix-on-rocks RK3566 image exists, add this section to the evidence:

```sh
systemctl status rocknix-guest.service --no-pager || true
systemctl status rocknix-guest-root-ensure.service --no-pager || true
systemctl status rocknix-guest-promote.service --no-pager || true
journalctl -b -u rocknix-guest.service --no-pager | tail -200 || true
journalctl -b -u rocknix-guest-root-ensure.service --no-pager | tail -200 || true
journalctl -b -u rocknix-guest-promote.service --no-pager | tail -200 || true
```

---

## Validation Strategy

### Before-device validation

- `nix flake check --no-build`
- RK3566-specific contract script once added.
- SM8550 contract checks to prove no regression.
- Static patch-queue checks for RK3566 host prerequisites.
- RK3566 artifact checks for SD-image layout once the build lane exists.

### After-device validation

- First-boot evidence document under `docs/brainstorms/evidence/`.
- Hardware acceptance document under `docs/acceptance/` for first integrated image.
- Device smoke checks:
  - model/compatible selection selects RG353M profile,
  - display appears on panel,
  - controls generate guest-visible input events,
  - speaker/headphone audio works or gaps are documented,
  - WiFi connects or failure is documented,
  - guest service reaches expected state,
  - recovery/no-nspawn path works.

---

## Risks

| Risk | Impact | Mitigation |
| --- | --- | --- |
| RG353M reports RG353P compatible string | Wrong guest profile selection | Capture `/proc/device-tree/model` and all compatibles first; add model-aware or alias rule only with evidence. |
| RK3566 host lacks nspawn prerequisites | Guest fails to start | Add static checks for cgroup v2, user namespaces, overlayfs, and systemd-nspawn gating before image work. |
| Audio topology differs from assumptions | No speaker/headphone route | Probe `aplay -l`, `amixer`, and dmesg before writing RK817 audio config. |
| Panfrost/Vulkan limitations | High-end emulators fail | Make first target Panfrost/OpenGL/GLES and defer proprietary Mali/Vulkan tuning. |
| WiFi/audio interference | Poor user experience | Preserve Realtek driver workaround and document any observed hardware coupling. |
| eMMC bootloader interaction | Device boot disruption or Android loss | Keep first bring-up SD-only and require explicit later approval for destructive eMMC operations. |

---

## Open Questions for Device Arrival

Evidence captured from stock Android over ADB: `docs/brainstorms/evidence/2026-06-04-rg353m-android-adb-identity.md`.

- Answered: `/proc/device-tree/model` exposed `Rockchip RK3566 RK817 TABLET LP4X Board`.
- Answered: `/proc/device-tree/compatible` exposed `rockchip,rk3566-rk817-tablet`, then `rockchip,rk3566`.
- Still open: Does the device boot a current ROCKNIX SD image without touching eMMC?
- Partially answered: ALSA cards are `rockchip,hdmi` and `rockchip,rk817-codec`; mixer paths still need Linux/ROCKNIX evidence.
- Still open: What DRM connector name does Sway need? Android dmesg shows a 640x480 DSI path but not the final Linux connector name.
- Partially answered: Android input names include `retrogame_joypad`, `touch_joypad`, `hyn_ts`, `gpio-keys`, `adc-keys`, `rk805 pwrkey`, and `rk-headset`; final guest mapping needs Linux/ROCKNIX confirmation.
- Partially answered: Android WiFi uses Realtek `RTW` SDIO with `wlan0`/`p2p0`; Linux workaround validation remains open.
- Partially answered: Android exposes `/dev/dri/card0` and `/dev/dri/renderD128`; `/dev/mali0` status remains for Linux/ROCKNIX evidence.
- Still open: Is recovery/no-nspawn best represented by an extlinux entry, a `/flash` flag file, or the existing substrate flag-file pattern?
