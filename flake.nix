{
  description = "Nix-on-Rocks SM8550 NixOS guest rootfs and emulator packages";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    # ROCKNIX Cemu is built against classic SDL2. nixos-25.11 aliases SDL2
    # to sdl2-compat, so keep a narrow 24.11 input only for that build input.
    nixpkgs-sdl2-classic.url = "github:NixOS/nixpkgs/nixos-24.11";
  };

  outputs =
    { self
    , nixpkgs
    , nixpkgs-sdl2-classic
    ,
    }:
    let
      targetSystem = "aarch64-linux";
      hostSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllHostSystems = nixpkgs.lib.genAttrs hostSystems;
      packageSetFor =
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          pkgsSdl2Classic = nixpkgs-sdl2-classic.legacyPackages.${system};
          cemu = pkgs.callPackage ./packages/cemu/package.nix {
            SDL2_classic = pkgsSdl2Classic.SDL2;
            # SoC-bound defaults injected from devices/sm8550/. Keeps the
            # cemu package generic; when Retroid (sm8250) work starts the
            # same package accepts socSettings = ./devices/sm8250/cemu/...;
            # socName = "SM8250";
            socSettings = ./devices/sm8550/cemu/settings.xml;
            socName = "SM8550";
          };
          steam = pkgs.callPackage ./packages/steam/package.nix { };
          ayn-odin2-ucm = pkgs.callPackage ./devices/sm8550/audio/ayn-odin2-ucm { };
          inputplumber = pkgs.callPackage ./packages/inputplumber { };
          moonlight-embedded = pkgs.callPackage ./packages/moonlight-embedded/package.nix { };
        in
        {
          default = cemu;
          cemu = cemu;
          steam = steam;
          ayn-odin2-ucm = ayn-odin2-ucm;
          # Forward-looking alias: when a second SoC lands, sm8250-<codec>-ucm
          # naturally sits beside this. The unprefixed ayn-odin2-ucm name is
          # preserved for backward compat with existing consumers.
          sm8550-ayn-odin2-ucm = ayn-odin2-ucm;
          inputplumber = inputplumber;
          moonlight-embedded = moonlight-embedded;
          # Compatibility alias for existing ROCKNIX Layer 14 scripts/docs.
          cemu-rocknix-package = cemu;
        };
      configuration = nixpkgs.lib.nixosSystem {
        system = targetSystem;
        modules = [ ./guest/rocknix-guest.nix ];
      };
      # Single source of truth for device-tree compatible -> device profile
      # mapping. Adding a new SM8550 device is one entry here plus a profile
      # under profiles/devices/. Downstream product flakes can use this table
      # to pick the right profile from /proc/device-tree.
      deviceProfileByCompatible = {
        "ayn,thor" = ./guest/profiles/devices/thor.nix;
        "ayn,odin2portal" = ./guest/profiles/devices/odin2portal.nix;
      };

      # Impure: reads the target device-compatible string from the host
      # promoter via ROCKNIX_GUEST_DEVICE_COMPATIBLE. Device-tree compatible
      # properties are NUL-delimited; Nix strings cannot represent NUL bytes,
      # so the host substrate normalizes /proc/device-tree/compatible before
      # evaluation. Off-device evaluation should use explicit per-device
      # attributes instead.
      selectDeviceProfileFromCompatible =
        let
          compatible = builtins.getEnv "ROCKNIX_GUEST_DEVICE_COMPATIBLE";
        in
        if compatible == "" then
          throw ''
            nix-on-rocks guest: ROCKNIX_GUEST_DEVICE_COMPATIBLE is not set.
            Downstream product flakes that use selectDeviceProfileFromCompatible
            must normalize /proc/device-tree/compatible and pass a single
            compatible string. Off-device evaluation should use an explicit
            per-device product configuration.
          ''
        else if !(builtins.hasAttr compatible deviceProfileByCompatible) then
          throw ''
            nix-on-rocks guest: no guest profile registered for device-tree
            compatible ${builtins.toJSON compatible}.
            Add profiles/devices/<device>.nix and register its first DT
            compatible string in deviceProfileByCompatible (flake.nix).
          ''
        else
          deviceProfileByCompatible.${compatible};

      baseConfiguration = nixpkgs.lib.nixosSystem {
        system = targetSystem;
        modules = [
          ./guest/profiles/rocknix-guest-base.nix
          ({ lib, ... }: { networking.hostName = lib.mkForce "rocknix-input-boundary-contract"; })
        ];
      };
      devEnvConfiguration = nixpkgs.lib.nixosSystem {
        system = targetSystem;
        modules = [ ./guest/profiles/dev-env.nix ];
      };
      # The rootfs artifact is the production main-space guest: Sway,
      # guest-owned audio/input/display, and guest-native packages. The
      # minimal rocknix-guest configuration remains exposed for evaluation,
      # but the host autostart path must stage main-space or the device boots
      # to a container with no compositor.
      mkRootfs =
        hostSystem: configurationToPackage:
        let
          pkgs = import nixpkgs { system = hostSystem; };
          toplevel = configurationToPackage.config.system.build.toplevel;
          closure = pkgs.closureInfo {
            rootPaths = [ toplevel ];
          };
        in
        pkgs.runCommand "rocknix-layer10b-guest-rootfs"
          {
            nativeBuildInputs = [
              pkgs.coreutils
              pkgs.gnutar
              pkgs.zstd
            ];
          }
          ''
            mkdir -p root/nix/store root/sbin root/usr/bin root/tmp root/proc root/sys root/dev root/run root/etc root/var root/var/lib $out/tarball
            chmod 1777 root/tmp
            while IFS= read -r store_path; do
              cp -a "$store_path" root/nix/store/
            done < ${closure}/store-paths
            ln -s ${toplevel}/init root/init
            ln -s ${toplevel}/init root/sbin/init
            ln -s /run/current-system/sw/bin/nix root/usr/bin/nix
            cp -a ${toplevel}/etc/. root/etc/
            chmod -R u+w root/etc
            if [ -e root/etc/static/ssh/sshd_config ]; then
              mkdir -p root/etc/ssh
              rm -f root/etc/ssh/sshd_config
              cp -L root/etc/static/ssh/sshd_config root/etc/ssh/sshd_config
              chmod u+w root/etc/ssh/sshd_config
            fi
            mkdir -p root/etc/ssh/authorized_keys.d
            rm -f root/etc/ssh/authorized_keys.d/root
            : > root/etc/ssh/authorized_keys.d/root
            chmod 600 root/etc/ssh/authorized_keys.d/root
            tar --sort=name --numeric-owner --owner=0 --group=0 --zstd \
              -cf $out/tarball/rocknix-layer10b-guest-rootfs-aarch64-linux.tar.zst \
              -C root .
          '';
    in
    {
      # Reusable NixOS modules for external flake consumers (e.g. mountainous
      # composing the Odin 2 Portal as a managed host while this flake remains
      # the source of truth for the SM8550 device schema and the main-space
      # profile).
      #
      # Path attributes are deliberate: a path-valued module is imported by the
      # consumer's nixosSystem evaluation, which means imports inside
      # main-space.nix and the device profiles still resolve relative to this
      # store path.
      nixosModules = {
        sm8550 = ./guest/modules/device.nix;
        rocknix-guest-base = ./guest/profiles/rocknix-guest-base.nix;
        odin2portal = ./guest/profiles/devices/odin2portal.nix;
        thor = ./guest/profiles/devices/thor.nix;
        default = ./guest/profiles/rocknix-guest-base.nix;
      };

      # Library helpers exposed to external flake consumers. mkGuestRootfs is
      # the same packaging used to produce the in-flake rootfs-* artifacts; it
      # is exposed so a downstream flake can package its own nixosConfiguration
      # of the main-space guest as a deployable rootfs tarball without
      # duplicating the closure/tar plumbing.
      lib = {
        mkGuestRootfs = mkRootfs;
        inherit deviceProfileByCompatible selectDeviceProfileFromCompatible;
      };

      nixosConfigurations.rocknix-guest = configuration;
      nixosConfigurations.rocknix-guest-dev-env = devEnvConfiguration;
      packages = forAllHostSystems packageSetFor;
      checks = forAllHostSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          static =
            pkgs.runCommand "nix-on-rocks-guest-static-checks"
              {
                nativeBuildInputs = [ pkgs.shellcheck ];
              }
              ''
                cd ${self}
                ${pkgs.bash}/bin/bash guest/scripts/static-checks.sh
                touch $out
              '';
          steam-package-contract =
            pkgs.runCommand "rocknix-steam-package-contract"
              { }
              ''
                cd ${self}
                PACKAGE_OUT=${self.packages.${system}.steam} \
                  ${pkgs.bash}/bin/bash packages/steam/tests/steam-package-contract.sh
                touch $out
              '';
          guest-input-boundary-contract =
            let
              assertContract = condition: message:
                if condition then message else builtins.throw "guest input boundary contract failed: ${message}";
              cfg = baseConfiguration.config;
              devCfg = devEnvConfiguration.config;
              inputplumber = cfg.systemd.services.inputplumber;
              wireplumber = cfg.systemd.services.main-space-wireplumber;
              devWireplumber = devCfg.systemd.services.main-space-wireplumber;
              contract = builtins.toFile "guest-input-boundary-contract.json" (builtins.toJSON [
                (assertContract cfg.services.udev.enable "services.udev.enable")
                (assertContract (builtins.elem "systemd-udev-trigger.service" cfg.systemd.additionalUpstreamSystemUnits) "udev-trigger upstream unit restored")
                (assertContract cfg.systemd.services.systemd-udevd.enable "systemd-udevd enabled")
                (assertContract cfg.systemd.services.systemd-udev-trigger.enable "systemd-udev-trigger enabled")
                (assertContract cfg.systemd.services.systemd-udev-settle.enable "systemd-udev-settle enabled")
                (assertContract (builtins.length cfg.services.udev.packages > 0) "InputPlumber udev package installed")
                (assertContract (inputplumber.environment.HIDE_DEVICES_FROM_ROOT or "" == "1") "InputPlumber hides from root")
                (assertContract (builtins.elem "systemd-udev-settle.service" (inputplumber.after or [ ])) "InputPlumber orders after udev-settle")
                (assertContract (builtins.elem "L /dev/inputplumber - - - - /dev/input/.inputplumber" cfg.systemd.tmpfiles.rules) "/dev/inputplumber symlink tmpfiles rule")
                (assertContract (builtins.elem "d /run/udev/rules.d 0755 root root -" cfg.systemd.tmpfiles.rules) "/run/udev/rules.d tmpfiles rule")
                (assertContract (builtins.elem "systemd-udev-settle.service" (wireplumber.wants or [ ])) "WirePlumber pulls in udev-settle")
                (assertContract (builtins.elem "systemd-udev-settle.service" (wireplumber.after or [ ])) "WirePlumber orders after udev-settle")
                (assertContract (builtins.elem "systemd-udev-settle.service" (devWireplumber.wants or [ ])) "dev-env WirePlumber pulls in udev-settle")
              ]);
            in
            pkgs.runCommand "rocknix-guest-input-boundary-contract"
              { }
              ''
                cat ${contract} >/dev/null
                touch $out
              '';
        }
      );
      formatter = forAllHostSystems (system: nixpkgs.legacyPackages.${system}.nixpkgs-fmt);
    };
}
