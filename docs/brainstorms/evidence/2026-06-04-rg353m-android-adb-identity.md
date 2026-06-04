# RG353M Android ADB identity evidence

Date: 2026-06-04

## Probe context

- Physical device: Anbernic RG353M provided by user.
- Booted OS/image: stock Android userspace on the device.
- Connection: USB ADB from this workstation using `nixpkgs#android-tools`; host needed root ADB because the Rockchip USB device node was not accessible to the normal user.
- Write/destructive boundary: read-only probe commands only. No flashing, partition writes, eMMC zeroing, repartitioning, or Android overwrite were performed.
- eMMC state: Android is still booted from internal storage; eMMC was intentionally left untouched.
- ADB device line:

  ```text
  2535846e5eb7d217       device usb:5-2.3.1 product:RG353P model:RG353P device:RG353P transport_id:1
  ```

- USB descriptor observed from host:

  ```text
  Bus 005 Device 009: ID 2207:0017 Fuzhou Rockchip Electronics Company RG353P
  ```

## Device identity

Commands:

```sh
adb shell getprop ro.product.model
adb shell getprop ro.product.device
adb shell getprop ro.product.name
adb shell getprop ro.hardware
adb shell getprop ro.board.platform
adb shell cat /proc/device-tree/model
adb shell 'tr "\000" "\n" < /proc/device-tree/compatible'
```

Output:

```text
ro.product.model=RG353P
ro.product.device=RG353P
ro.product.name=RG353P
ro.hardware=rk30board
ro.board.platform=rk356x
ro.boot.hardware=rk30board

/proc/device-tree/model:
Rockchip RK3566 RK817 TABLET LP4X Board

/proc/device-tree/compatible:
rockchip,rk3566-rk817-tablet
rockchip,rk3566

uname:
Linux localhost 4.19.232 #186 SMP PREEMPT Mon Mar 6 18:37:20 CST 2023 aarch64
```

Profile-selection consequence: the physical RG353M does **not** expose an `anbernic,rg353m` or `anbernic,rg353p` compatible string through this Android boot. The stable device-tree identity captured here is the first compatible string `rockchip,rk3566-rk817-tablet`; nix-on-rocks therefore keys the RG353M profile from that compatible string and documents that this is an RG353-family alias chosen from physical-device evidence.

## Display / DRM / panel evidence

```text
/dev/dri:
crw-rw-rw- 1 root graphics 226,   0 card0
crw-rw-rw- 1 root graphics 226, 128 renderD128

dmesg excerpt:
rockchip-vop2 fe040000.vop: [drm:vop2_crtc_atomic_enable] Update mode to 640x480p60, type: 16 for vp1
dw-mipi-dsi fe060000.dsi: [drm:dw_mipi_dsi_encoder_enable] final DSI-Link bandwidth: 330 x 4 Mbps
```

`/sys/class/drm` connector files were not readable/listed usefully from Android shell during this probe, so exact DRM connector naming remains for the Linux/ROCKNIX boot evidence pass. The Android boot confirms a 640x480 DSI panel path via VOP2/DSI.

## Input devices

`/proc/bus/input/devices` and `getevent -lp` reported:

```text
event0: gpio-moount_adc
  KEY: BTN_MOUSE BTN_RIGHT BTN_MIDDLE
  REL: REL_X REL_Y

event1: rk805 pwrkey
  KEY: KEY_POWER

event2: adc-keys
  KEY: KEY_BACK

event3: gpio-keys
  KEY: KEY_VOLUMEDOWN KEY_VOLUMEUP

event4: retrogame_joypad
  KEY: BTN_GAMEPAD BTN_EAST BTN_NORTH BTN_WEST BTN_TL BTN_TR BTN_TL2 BTN_TR2 BTN_SELECT BTN_START BTN_THUMBL BTN_THUMBR
  ABS: ABS_X/ABS_Y/ABS_Z/ABS_RZ min -1800 max 1800; ABS_HAT0X/ABS_HAT0Y min -1 max 1

event5: touch_joypad
  KEY: same gamepad buttons plus BTN_TOUCH
  ABS: same gamepad axes plus ABS_MT_POSITION_X 0..640, ABS_MT_POSITION_Y 0..480

event6: hyn_ts
  KEY: KEY_MENU KEY_BACK KEY_HOMEPAGE BTN_TOUCH
  ABS: ABS_MT_POSITION_X 0..640, ABS_MT_POSITION_Y 0..480, ABS_MT_TRACKING_ID 0..5

event7: rk-headset
  KEY: KEY_MEDIA
```

Bring-up consequence: do not reuse AYN input names. RG353M controls should start from `retrogame_joypad` / `touch_joypad`, with touchscreen from `hyn_ts` if exposed in the Linux guest boot.

## Audio evidence

```text
/proc/asound/cards:
 0 [rockchiphdmi   ]: rockchip_hdmi - rockchip,hdmi
                      rockchip,hdmi
 1 [rockchiprk817co]: rockchip_rk817- - rockchip,rk817-codec
                      rockchip,rk817-codec

/proc/asound/devices:
  2: [ 0- 0]: digital audio playback
  3: [ 0]   : control
  4: [ 1- 0]: digital audio playback
  5: [ 1- 0]: digital audio capture
  6: [ 1]   : control
 33:        : timer
```

`aplay -l` produced no output in this Android shell, and `tinymix` produced no output in the captured probe. RK817 audio bring-up must be based on Linux/ROCKNIX ALSA mixer evidence in the next audio task.

## WiFi / Bluetooth evidence

```text
/sys/class/net:
wlan0 -> ../../devices/platform/fe000000.dwmmc/mmc_host/mmc3/mmc3:0001/mmc3:0001:1/net/wlan0
p2p0 -> ../../devices/platform/fe000000.dwmmc/mmc_host/mmc3/mmc3:0001/mmc3:0001:1/net/p2p0

properties:
init.svc.vendor.bluetooth-1-0=running
init.svc.vendor.wifi_hal_legacy=running
init.svc.wificond=running
persist.bluetooth.rtkcoex=true
vendor.wlan.driver.version=v5.12.0-8-g39bbb8dd2.20201015_COEX20200730-5151
vendor.wlan.firmware.version=v24.8
wifi.active.interface=wlan0
wifi.interface=wlan0
vendor.wifi.direct.interface=p2p0
```

Relevant dmesg excerpts show Realtek `RTW` SDIO suspend/resume paths and power-save transitions. This supports keeping the RK3566 Realtek/rtw88 workaround path under the later WiFi/Bluetooth task.

## Storage / eMMC safety evidence

Android internal storage exposed named block devices on `mmcblk0`; no write commands were issued.

```text
/dev/block/by-name:
security -> /dev/block/mmcblk0p1
uboot -> /dev/block/mmcblk0p2
trust -> /dev/block/mmcblk0p3
misc -> /dev/block/mmcblk0p4
dtbo -> /dev/block/mmcblk0p5
vbmeta -> /dev/block/mmcblk0p6
boot -> /dev/block/mmcblk0p7
recovery -> /dev/block/mmcblk0p8
backup -> /dev/block/mmcblk0p9
cache -> /dev/block/mmcblk0p10
metadata -> /dev/block/mmcblk0p11
baseparameter -> /dev/block/mmcblk0p12
super -> /dev/block/mmcblk0p13
userdata -> /dev/block/mmcblk0p14
```

## Follow-up evidence still needed

- ROCKNIX/Linux boot evidence from removable SD for final DRM connector names and backlight paths.
- ALSA mixer topology (`amixer`/`tinymix` equivalent) for RK817 speaker/headphone routing.
- WiFi connection persistence and Bluetooth scan behavior in the target Linux host/guest lane.
- Guest-substrate status once the first RK3566 SD image is booted.
