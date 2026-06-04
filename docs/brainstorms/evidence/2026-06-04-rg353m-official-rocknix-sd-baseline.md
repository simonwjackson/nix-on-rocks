# RG353M official ROCKNIX SD baseline evidence

Date: 2026-06-04

## Probe context

- Physical device: Anbernic RG353M.
- Booted OS/image: official ROCKNIX RK3566 Generic SD image, `ROCKNIX-RK3566.aarch64-20260601-Generic.img.gz`.
- Access path: SSH to `root@192.168.1.140` with the ROCKNIX root password.
- Write/destructive boundary: read-only probe commands over SSH. No flashing, partition writes, eMMC zeroing, repartitioning, or Android overwrite were performed from the device shell.
- Product target: removable-SD baseline. Android/eMMC remains the fallback path.

```text
OS_NAME="ROCKNIX"
OS_VERSION="20260601"
OS_BUILD="official"
HW_DEVICE="RK3566"
HW_ARCH="aarch64"
Linux ROCKNIX 7.0.2 #1 SMP PREEMPT Mon Jun  1 05:08:02 UTC 2026 aarch64 GNU/Linux
```

## Device identity

```text
/proc/device-tree/model:
Anbernic RG353M

/proc/device-tree/compatible:
anbernic,rg353p
rockchip,rk3566
```

Profile-selection consequence: official ROCKNIX SD boot exposes an RG353M model with an RG353P-compatible DTB. nix-on-rocks should select the RG353M profile by the model alias `Anbernic RG353M`, not by registering `anbernic,rg353p` directly for RG353M.

## SD-only storage evidence

```text
/proc/cmdline:
boot=LABEL=ROCKNIX disk=LABEL=STORAGE quiet console=ttyS2,1500000 console=tty0 systemd.debug_shell=ttyS2

/flash:
/dev/mmcblk1p1 LABEL="ROCKNIX" TYPE="vfat"

/storage:
/dev/mmcblk1p2 LABEL="STORAGE" TYPE="ext4"
```

The eMMC remained visible as `/dev/mmcblk0` with Android-style named partitions (`security`, `uboot`, `trust`, `misc`, `dtbo`, `vbmeta`, `boot`, `recovery`, `cache`, `metadata`, `baseparameter`, `super`, `userdata`) but was not written.

## Display, framebuffer, and backlight

```text
/sys/class/drm:
card0
card0-DSI-1
card0-HDMI-A-1

card0-DSI-1/status: connected
card0-DSI-1/modes: 640x480
card0-DSI-1/enabled: enabled

card0-HDMI-A-1/status: disconnected
card0-HDMI-A-1/enabled: disabled

/sys/class/graphics/fb0/name: rockchipdrmfb
/sys/class/graphics/fb0/modes: U:640x480p-0
/sys/class/graphics/fb0/virtual_size: 640,480
/sys/class/graphics/fb0/bits_per_pixel: 32

/sys/class/backlight/backlight/actual_brightness: 127
/sys/class/backlight/backlight/brightness: 127
/sys/class/backlight/backlight/max_brightness: 255
/sys/class/backlight/backlight/type: raw
```

Relevant dmesg excerpts:

```text
Machine model: Anbernic RG353M
panel-sitronix-st7703 fe060000.dsi.0: 640x480@60 24bpp dsi 4dl - ready
rockchip-drm display-subsystem: [drm] fb0: rockchipdrmfb frame buffer device
```

## Input devices

`/proc/bus/input/devices` reported:

```text
rk805 pwrkey
Hynitron cst3xx Touchscreen
adc-keys
rk817_ext Headphones
gpio-keys-vol
retrogame_joypad
```

`/dev/input` exposed `event0` through `event5` and `js0`; `retrogame_joypad` provided the joystick device.

Relevant dmesg excerpts:

```text
input: Hynitron cst3xx Touchscreen as /devices/platform/fe5b0000.i2c/i2c-2/2-001a/input/input1
input: adc-keys as /devices/platform/adc-keys/input/input2
input: rk817_ext Headphones as /devices/platform/sound/sound/card1/input3
input: gpio-keys-vol as /devices/platform/gpio-keys-vol/input/input4
input: retrogame_joypad as /devices/platform/rocknix-singleadc-joypad/input/input5
rocknix-singleadc-joypad rocknix-singleadc-joypad: has rumble
rocknix-singleadc-joypad rocknix-singleadc-joypad: joypad_probe : probe success
```

## Audio evidence

```text
/proc/asound/cards:
 0 [HDMI           ]: simple-card - HDMI
                      HDMI
 1 [rk817ext       ]: simple-card - rk817_ext
                      rk817_ext

/proc/asound/pcm:
00-00: fe400000.i2s-i2s-hifi i2s-hifi-0 : fe400000.i2s-i2s-hifi i2s-hifi-0 : playback 1
01-00: fe410000.i2s-rk817-hifi rk817-hifi-0 : fe410000.i2s-rk817-hifi rk817-hifi-0 : playback 1 : capture 1

aplay -l:
card 0: HDMI [HDMI], device 0: fe400000.i2s-i2s-hifi i2s-hifi-0
card 1: rk817ext [rk817_ext], device 0: fe410000.i2s-rk817-hifi rk817-hifi-0

amixer controls:
Simple mixer control 'Master',0
Simple mixer control 'Mic Capture Gain',0
Simple mixer control 'Playback Mux',0
Simple mixer control 'Internal Speakers',0
```

Task-013 still owns real RK817 guest audio routing; this baseline only records card/control names.

## WiFi and Bluetooth evidence

```text
/sys/class/net:
wlan0 -> /devices/platform/fe000000.mmc/mmc_host/mmc3/mmc3:0001/mmc3:0001:1/net/wlan0
wlan1 -> /devices/platform/fe000000.mmc/mmc_host/mmc3/mmc3:0001/mmc3:0001:1/net/wlan1

wlan0: UP with 192.168.1.140/24
wlan1: DOWN
rfkill phy0 wlan: unblocked
rfkill hci0 bluetooth: unblocked

hci0: Type Primary, Bus UART, BD Address 2C:C3:E6:47:40:7B, DOWN
```

Relevant dmesg excerpts:

```text
rtw88_8821cs mmc3:0001:1: Firmware version 24.11.0, H2C version 12
Bluetooth: hci0: RTL: loading rtl_bt/rtl8821cs_fw.bin
Bluetooth: hci0: RTL: loading rtl_bt/rtl8821cs_config.bin
Bluetooth: hci0: RTL: fw version 0x75b8f098
```

## GPU evidence

```text
mali fde60000.gpu: Kernel DDK version r54p2-02eac0
mali fde60000.gpu: GPU identified as 0x2 arch 7.4.0 r1p0 status 0
mali fde60000.gpu: Probed as mali0
```

Task-017 still owns guest footprint and graphics default decisions.
