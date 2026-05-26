# Thor/Bandai guest-root backup reconnaissance

Read-only scan over SSH: `ssh -p 2222 root@bandai`. Scope was guest root state outside `/storage`, `/nix/store`, `/proc`, `/sys`, `/dev`, `/run`, and `/tmp`; commands used `find`, `du`, `ls`, and `stat` with `-xdev`/excludes where applicable.

## Prioritized backup list

### P0 — preserve before risky device work

1. **Root account local state: `/root` excluding rebuildable caches**
   - Especially `/root/.ssh` (`authorized_keys`, `config`, `known_hosts*`, `id_ed25519_korri_zao*`).
   - App/user configuration and small persistent state:
     - `/root/.config/{Cemu,dolphin-emu,mgba,visualboyadvance-m,antimicrox,sway,btop,mpv}`
     - `/root/.local/share/{Cemu,dolphin-emu,pki,applications,dev.korri.desktop}`
     - `/root/.local/state/wireplumber`
     - `/root/.nix-channels`, `/root/.nix-defexpr`, `/root/.bash_history`
   - Skip `/root/.cache` for normal backup; it is mostly Nix/Mesa/fontconfig/Qt cache (~72M).

2. **Local identity, credentials, and handwritten overrides in `/etc`**
   - `/etc/ssh/ssh_host_*` host keys.
   - `/etc/NetworkManager/system-connections/vrackie.nmconnection`.
   - `/etc/machine-id`.
   - `/etc/passwd`, `/etc/group`, `/etc/shadow` if preserving exact local account/auth state matters.
   - `/etc/nixos`, `/etc/nixos.before-layer14-validation`.
   - `/etc/inputplumber/{devices.d/02-ayn-controller.yaml,capability_maps.d/ayn_mcu.yaml}`.
   - `/etc/sway/config.bak.kill-gui-c.*`, `/etc/sway-minimal.conf`.
   - `/etc/rocknix-guest-revision`, `/etc/rocknix-guest-system-path`, resolver backup files if useful for proof/debug.

3. **Network/device service state in `/var/lib`**
   - `/var/lib/tailscale/tailscaled.state` and related small Tailscale metadata.
   - `/var/lib/iwd/vrackie.psk`, `/var/lib/iwd/.known_network.freq`.
   - `/var/lib/NetworkManager/secret_key`, `NetworkManager.state`, `seen-bssids`, leases/timestamps.
   - `/var/lib/bluetooth/00:03:7F:03:81:24` paired-device state.
   - `/var/lib/nixos` only if exact NixOS declarative UID/GID maps should be preserved.

4. **Top-level local proof/log/screenshot artifacts**
   - `/guest-import.log`, `/guest-promote.log`, `/promote.log`, `/cemu-sm8550-performance.log`, `/steam.log`, `/grim.err`.
   - `/screenshot-DSI2.png`, `/u3-current.png`, `/u3-screen.png`.

### P1 — preserve if exact Nix generation/provenance matters

5. **Nix profile/generation metadata outside the store**
   - `/nix/var/nix/profiles`, `/nix/var/nix/gcroots`, `/nix/var/nix/db/db.sqlite*`.
   - Note: profile/gcroot entries mostly point into `/nix/store`; backing these up without store closures is mainly useful as a manifest/provenance record.
   - Current notable links include `system -> system-manual-link`, `system-44-link -> ...nixos-system-bandai...`, root `profile-3-link`, and `cemu-promoted-3-link`.

6. **Persistent journals/logs for debugging/proof**
   - `/var/log/journal` (~33M) if boot/session history is valuable.
   - `/var/log/{wtmp,btmp,lastlog}` if login history matters.

### P2 / likely rebuildable or low value

- `/cache` is only Mesa shader cache (~1.3M); skip unless shader warmup matters.
- `/rootfs/usr/share/inputplumber` and `/usr/share/inputplumber` look like copied/package data; only the AYN YAML files have local timestamps and are already mirrored under `/etc/inputplumber`.
- `/home`, `/srv`, `/host`, `/host-nix-store`, `/host-var-log`, and `/mnt/games-card` are empty directory shells.
- `/bin`, `/sbin`, `/lib`, `/usr/bin` are symlinks/stubs into `/nix/store`, `/run/current-system`, or `/host`; rebuildable.
- `/var/cache`, `/var/tmp`, `/nix/var/log/nix/drvs`, Nix eval/fetcher caches, Mesa/fontconfig/Qt caches are rebuildable runtime/build cache.

## Evidence

### Root filesystem and top-level scope

Command:

```sh
ssh -p 2222 root@bandai 'stat -f -c "root_fs_type=%T root_fs_id=%i" /; ls -la /'
```

Results excerpt:

```text
host=bandai
root_fs_type=ext2/ext3 root_fs_id=b0a9c598dd035d2b
/root 78M, /var 33M, /nix outside store/logs ~26M, /etc 408K, /rootfs 512K, /cache 1.3M
Top-level files include guest-import.log, guest-promote.log, promote.log, cemu-sm8550-performance.log,
steam.log, grim.err, screenshot-DSI2.png, u3-current.png, u3-screen.png.
```

### `/root`

Command:

```sh
du -x -h -d3 --exclude=/root/.cache /root
find /root -xdev \( -path /root/.cache -o -path /root/.steam/steam -o -path /root/.local/share/Steam/steamapps \) -prune -o -maxdepth 5 \
  \( -type d -o -type f -o -type l \) -printf '%M %s %TY-%Tm-%Td %TH:%TM %p -> %l\n'
```

Results excerpt:

```text
/root excluding .cache: 6.2M
/root/.ssh: 32K; contains authorized_keys, config, known_hosts*, id_ed25519_korri_zao + .pub
/root/.config: 5.6M; includes Cemu, dolphin-emu, mgba, visualboyadvance-m, antimicrox, sway, btop, mpv
/root/.local: 540K; includes Cemu, dolphin-emu, pki/nssdb, applications, dev.korri.desktop
/root/.local/state/wireplumber: default-nodes, default-routes, stream-properties
/root/.cache: 72M, mostly nix tarball/eval/git cache and mesa_shader_cache
```

### `/etc`

Command:

```sh
du -x -h -d2 /etc
find /etc -xdev -type f -printf '%M %u:%g %s %TY-%Tm-%Td %TH:%TM %p\n'
find /etc -xdev -type l -printf '%M %u:%g %s %TY-%Tm-%Td %TH:%TM %p -> %l\n'
ls -la /etc/ssh /etc/NetworkManager /etc/nix /etc/ssl /etc/machine-id
```

Results excerpt:

```text
/etc total: 408K
/etc/ssh/ssh_host_ed25519_key 411 bytes; ssh_host_rsa_key 3381 bytes
/etc/NetworkManager/system-connections/vrackie.nmconnection 305 bytes mode 600
/etc/machine-id 33 bytes
/etc/nixos 88K; /etc/nixos.before-layer14-validation 24K
/etc/inputplumber/devices.d/02-ayn-controller.yaml 2073 bytes
/etc/inputplumber/capability_maps.d/ayn_mcu.yaml 5198 bytes
Most /etc entries are symlinks through /etc/static -> /nix/store/...-etc/etc
```

### `/var`

Command:

```sh
du -x -h -d3 /var
find /var -xdev \( -path /var/cache -o -path /var/tmp -o -path /var/empty \) -prune -o -maxdepth 4 \
  \( -type d -o -type f -o -type l \) -printf '%M %u:%g %s %TY-%Tm-%Td %TH:%TM %p -> %l\n'
```

Results excerpt:

```text
/var total: 33M; /var/log/journal: 33M; /var/lib: 528K
/var/lib/tailscale: 40K, includes tailscaled.state 5466 bytes
/var/lib/iwd: 16K, includes vrackie.psk 492 bytes and .known_network.freq 86 bytes
/var/lib/NetworkManager: 36K, includes secret_key 50 bytes, state, leases, seen-bssids, timestamps
/var/lib/bluetooth: 56K, adapter 00:03:7F:03:81:24 and paired device dirs
/var/lib/nixos: 24K UID/GID/declarative user/group maps
```

### `/nix/var` outside `/nix/store`

Command:

```sh
du -x -h -d4 --exclude=/nix/store --exclude=/nix/var/log /nix
ls -la /nix/var/nix/profiles /nix/var/nix/profiles/per-user/root /nix/var/nix/gcroots /nix/var/nix/db
```

Results excerpt:

```text
/nix outside store/logs: 26M, dominated by /nix/var/nix/db
/nix/var/nix/db/db.sqlite 17,920,000 bytes; reserved 8,388,608 bytes
/nix/var/nix/profiles contains system-1-link through system-44-link plus system-manual-link
current system/manual links target /nix/store/i13qnjy...-nixos-system-bandai-25.11.20260505.0c88e1f
per-user/root has profile-1..3, cemu-promoted-1..3, rocknix-guest-system links
```

### Other scoped paths

Command:

```sh
for p in /cache /home /srv /mnt /rootfs /host /host-nix-store /host-var-log; do
  stat -c '%A %U:%G %s %y %n' "$p"
  du -x -h -d2 "$p"
  find "$p" -xdev -maxdepth 3 -printf '%M %s %TY-%Tm-%Td %TH:%TM %p -> %l\n'
done
```

Results excerpt:

```text
/cache: 1.3M mesa_shader_cache only
/home: empty directory
/srv: empty directory
/mnt/games-card: empty directory
/host, /host-nix-store, /host-var-log: empty directory shells
/rootfs: 512K inputplumber data; local-timestamp AYN files also present under /etc/inputplumber
```
