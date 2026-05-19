# Code Context

## Files Retrieved
1. `flake.nix` (lines 1-138) - flake inputs, package set, NixOS configurations, rootfs outputs, checks.
2. `profiles/main-space.nix` (lines 1-323) - production guest profile imports modules, starts Sway, defines session env and Home-chord launch bindings.
3. `modules/steam.nix` (lines 1-408) - best example of a runtime/frontend-like guest module with FHS env, launch wrapper, system packages, and a boot service.
4. `packages/steam/package.nix` (lines 1-101) - simple no-build package pattern for scripts/resources/evidence.
5. `packages/steam/manifest.nix` (lines 1-81) - data-only package contract and boundary documentation pattern.
6. `packages/cemu/package.nix` (lines 1-272) - compiled package pattern, wrapper-owned generic runtime setup, runtime data checks/evidence.
7. `packages/cemu/manifest.nix` (lines 1-78) - data-only upstream/source/patch/runtime contract pattern.
8. `modules/device.nix` (lines 1-108) - SM8550 options consumed by modules/profiles; per-device override boundaries.
9. `modules/display.nix` (lines 1-45) - Sway/Mesa display substrate and wlroots env.
10. `modules/audio.nix` (lines 1-103) - root-scoped PipeWire/session-bus model used by graphical apps.
11. `modules/base.nix` (lines 1-40) - container baseline and Nix-in-nspawn constraints.
12. `modules/ssh.nix` (lines 1-17) - no-default-credentials SSH baseline.
13. `profiles/devices/odin2portal.nix` (lines 1-30) - example of keeping device differences in profile overrides.
14. `launchers/games-launcher.sh` (lines 1-97) - current frontend-ish touch menu bound from Sway.
15. `scripts/static-checks.sh` (lines 15-317) - structural checks that must be extended for new files/outputs/boundaries.
16. `README.md` (lines 13-135) - documented layout, flake outputs, package/runtime boundaries, validation commands.
17. `docs/contracts/layer14-main-space-contract.md` (lines 1-169) - host/guest ownership, recovery, promotion, package-vs-session policy boundaries.

## Key Code

Flake package exposure and main-space install surface:

```nix
# flake.nix:16-32
packageSetFor = system:
  let
    pkgs = nixpkgs.legacyPackages.${system};
    pkgsSdl2Classic = nixpkgs-sdl2-classic.legacyPackages.${system};
    cemu = pkgs.callPackage ./packages/cemu/package.nix {
      SDL2_classic = pkgsSdl2Classic.SDL2;
    };
    steam = pkgs.callPackage ./packages/steam/package.nix { };
    ayn-odin2-ucm = pkgs.callPackage ./packages/audio/ayn-odin2-ucm { };
  in {
    default = cemu;
    cemu = cemu;
    steam = steam;
    ayn-odin2-ucm = ayn-odin2-ucm;
    cemu-rocknix-package = cemu;
  };
```

```nix
# flake.nix:38-52
mainSpaceConfigurationFor = deviceProfile: nixpkgs.lib.nixosSystem {
  system = targetSystem;
  modules = [
    ./profiles/main-space.nix
    deviceProfile
    ({ ... }: {
      environment.systemPackages = [
        (packageSetFor targetSystem).cemu
        (packageSetFor targetSystem).steam
        (packageSetFor targetSystem).ayn-odin2-ucm
      ];
    })
  ];
};
```

Main-space module composition and Sway launch/session contract:

```nix
# profiles/main-space.nix:45-56
imports = [
  ../modules/base.nix
  ../modules/device.nix
  ../modules/tools.nix
  ../modules/ssh.nix
  ../modules/display.nix
  ../modules/audio.nix
  ../modules/network.nix
  ../modules/lid.nix
  ../modules/steam.nix
];
```

```nix
# profiles/main-space.nix:116-124,153-169,175-207
systemd.services.rocknix-sway-kiosk = {
  wantedBy = [ "multi-user.target" ];
  after = [ "systemd-user-sessions.service" "rocknix-session-dbus.service" ];
  requires = [ "rocknix-session-dbus.service" ];
  path = with pkgs; [ dbus foot swaybg swaylock bashInteractive fuzzel git coreutils sway ];
  serviceConfig = {
    Type = "simple";
    User = "root";
    ExecStartPre = "${pkgs.coreutils}/bin/install -d -m 0700 -o 0 -g 0 /run/user/0";
    ExecStart = "${pkgs.sway}/bin/sway -c /etc/sway/config";
  };
  environment = {
    XDG_RUNTIME_DIR = "/run/user/0";
    DBUS_SESSION_BUS_ADDRESS = "unix:path=/run/user/0/bus";
    SDL_AUDIODRIVER = "pulseaudio";
    HOME = "/storage";
    XDG_CONFIG_HOME = "/storage/.config";
    XDG_DATA_HOME = "/storage/.local/share";
    XDG_CACHE_HOME = "/storage/.cache";
    WLR_NO_HARDWARE_CURSORS = "1";
    WLR_LIBINPUT_NO_DEVICES = "1";
    USER = "root";
  };
};
```

Sway config/keybinding pattern for launching a frontend:

```nix
# profiles/main-space.nix:224-245,317-321
environment.etc."sway/config".text = ''
  ${sm8550.display.swayDeviceConfig}
  set $home_chord_mode home-chord
  bindsym Home mode "$home_chord_mode"
  bindsym XF86HomePage mode "$home_chord_mode"
  mode "$home_chord_mode" {
    bindsym Return exec foot, mode "default"
    bindsym d exec fuzzel, mode "default"
    bindsym g exec /storage/.guest/games-launcher.sh, mode "default"
  }
  exec foot
'';
```

Steam module pattern to copy for frontend runtime glue:

```nix
# modules/steam.nix:263-388,391-407
steamFhs = pkgs.buildFHSEnv { ... runScript = steamRunScript; };
steamLauncher = pkgs.writeShellScriptBin "rocknix-steam-guest" ''
  export HOME="''${HOME:-/storage}"
  export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/0}"
  export DBUS_SESSION_BUS_ADDRESS="''${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/0/bus}"
  exec ${steamFhs}/bin/steam-arm64-fhs "$@"
'';

{
  environment.systemPackages = [ steamFhs steamLauncher steamRuntimePrep steamUinputPrep ];
  systemd.services.rocknix-steam-uinput = { wantedBy = [ "multi-user.target" ]; ... };
}
```

Package contract pattern:

```nix
# packages/steam/package.nix:20-29,31-49,50-86,91-100
stdenvNoCC.mkDerivation {
  pname = manifest.pname;
  version = manifest.version;
  src = ./.;
  dontConfigure = true;
  dontBuild = true;
  nativeBuildInputs = [ makeWrapper ];
  installPhase = ''
    install -Dm755 scripts/... "$out/bin/..."
    mkdir -p "$out/share/..." "$out/nix-support/..."
    # write manifest/evidence
    wrapProgram "$out/bin/..." --prefix PATH : ${lib.makeBinPath [ bash coreutils ]}
  '';
  passthru = { rocknixSteamManifest = manifest; };
  meta.platforms = [ "x86_64-linux" "aarch64-linux" ];
}
```

Device/session substrate frontend code should consume, not duplicate:

```nix
# modules/display.nix:20-44
hardware.graphics.enable = true;
programs.sway.enable = true;
environment.sessionVariables = {
  WLR_NO_HARDWARE_CURSORS = "1";
  WLR_LIBINPUT_NO_DEVICES = "1";
};
```

```nix
# modules/audio.nix:12-17,45-90
ALSA_CONFIG_UCM2 = ucmPath;
PULSE_SERVER = "unix:/run/user/0/pulse/native";
# root-owned rocknix-pipewire, rocknix-pipewire-pulse, rocknix-wireplumber services
```

## Architecture

This repo has three relevant layers:

1. **Package layer (`packages/*`)** builds immutable Nix outputs and package-owned generic wrappers/resources/evidence. Existing examples are `packages/cemu` for a compiled app and `packages/steam` for script/resource helpers. Packages are exposed through `flake.nix` `packageSetFor` for both `x86_64-linux` and `aarch64-linux` hosts.
2. **Guest module layer (`modules/*.nix`)** owns runtime/session integration: packages in `environment.systemPackages`, FHS wrappers, systemd services, root `/run/user/0` env, device prep, and app-specific guest runtime policy.
3. **Profile layer (`profiles/*.nix`)** composes modules. `profiles/main-space.nix` is the production UX profile. It starts one root Sway service, bakes `/etc/sway/config`, and imports `modules/steam.nix`. Device profiles override only measured SM8550 differences.

Concrete changes to add a new frontend module/package:

1. Add `packages/<frontend>/package.nix` (and likely `manifest.nix`, `scripts/`, `resources/`) following either `packages/steam` for scripts/resources or `packages/cemu` for compiled source. Set `meta.platforms = [ "x86_64-linux" "aarch64-linux" ]` if both package host outputs should exist.
2. In `flake.nix`, add `frontend = pkgs.callPackage ./packages/<frontend>/package.nix { ... };` in `packageSetFor`, expose `frontend = frontend;`, and add `(packageSetFor targetSystem).frontend` to `mainSpaceConfigurationFor` `environment.systemPackages` if it belongs in the rootfs.
3. Add `modules/<frontend>.nix` if the frontend needs guest runtime glue. It should add the package/wrappers to `environment.systemPackages`, define any `writeShellScriptBin` launchers, and define systemd services only if needed. Import it from `profiles/main-space.nix`; import from `profiles/dev-env.nix` only if dev profile needs it.
4. If the frontend is user-launched from Sway, update `profiles/main-space.nix` `/etc/sway/config` Home-chord bindings or autostart. If launched by basename through Sway, add the executable package to `rocknix-sway-kiosk.path`; otherwise use an absolute Nix store path in the generated config. Do not pre-set `WAYLAND_DISPLAY` on the Sway service itself.
5. If replacing/augmenting the current menu, update `launchers/games-launcher.sh` entries or add a new launcher under `launchers/` and ensure host staging/promotion knows how it reaches `/storage/.guest` (this repo only contains the source scripts; host integration stages them).
6. Extend `scripts/static-checks.sh`: file existence for new module/package, flake exposure grep, main-space install/import grep, shell syntax checks for new scripts, package boundary greps, and README checks.
7. Update `README.md` package table/output examples and boundary notes. If it changes host/guest contract or recovery assumptions, update `docs/contracts/layer14-main-space-contract.md` too.

## Start Here

Start with `flake.nix` and `profiles/main-space.nix`. `flake.nix` is the source of truth for package exposure and rootfs inclusion; `profiles/main-space.nix` is where the production guest imports runtime modules and wires the Sway frontend launch surface.

## Validation Commands

Minimum checks after edits:

```sh
./scripts/static-checks.sh
nix flake show --all-systems --no-write-lock-file .
nix build --dry-run --no-write-lock-file .#nixosConfigurations.rocknix-guest-main-space.config.system.build.toplevel
nix build .#<frontend> --print-build-logs
nix flake check --no-write-lock-file --print-build-logs
```

If the frontend is aarch64-specific or rootfs-impacting, also build the target/rootfs with an aarch64 builder available:

```sh
nix build .#packages.aarch64-linux.<frontend> --print-build-logs
nix build .#rootfs-thor --print-build-logs
nix build .#rootfs-odin2portal --print-build-logs
```

## Safety Boundaries

- Keep packages generic: no host `/usr`, `/lib`, `/flash`, `/boot`, broad `/storage`, `systemctl`, `swaymsg`, Gamescope/FEX/session orchestration, or SM8550 sysfs policy in package entry points unless explicitly documented as package-generic.
- Put guest/session/device policy in `modules/<frontend>.nix`, `profiles/main-space.nix`, or launch adapters, not in `packages/<frontend>`.
- Keep the guest container-style and credential-safe: `boot.isContainer = true`, no default passwords, no shipped authorized keys, SSH remains locked down.
- Do not add greetd/PAM/logind session assumptions, TTYPath, or `After=multi-user.target` to the Sway startup path. Current validated pattern is a root systemd service with `wantedBy = [ "multi-user.target" ]` and concrete prerequisites only.
- Use Home-chord bindings; static checks forbid AYN/Mod4 custom bindings.
- Preserve host/guest boundary: host binds only narrow resources; recovery is explicit via `/flash/rocknix.no-nspawn` or `rocknix.safe=1`; target is SM8550 only.
- For display/audio/network, consume existing modules (`display.nix`, `audio.nix`, `network.nix`) rather than duplicating ownership or binding host services.
