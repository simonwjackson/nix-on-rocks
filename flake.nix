{
  description = "Nix-on-Rocks SM8550 NixOS guest rootfs and emulator packages";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    korri.url = "github:simonwjackson/korri";
    # ROCKNIX Cemu is built against classic SDL2. nixos-25.11 aliases SDL2
    # to sdl2-compat, so keep a narrow 24.11 input only for that build input.
    nixpkgs-sdl2-classic.url = "github:NixOS/nixpkgs/nixos-24.11";
  };

  outputs =
    { self
    , nixpkgs
    , nixpkgs-sdl2-classic
    , korri
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
      mainSpaceConfigurationFor =
        deviceProfile: extraModules:
        nixpkgs.lib.nixosSystem {
          system = targetSystem;
          specialArgs = {
            korriHasKiosk = builtins.hasAttr "korri-kiosk" korri.nixosModules;
          };
          modules = [
            korri.nixosModules.korri
            ./guest/profiles/main-space.nix
            deviceProfile
            (
              { ... }:
              {
                services.korri.client = {
                  enable = true;
                  package = korri.packages.${targetSystem}.korri-desktop-device;
                };

                services.korri.inputd.enable = true;

                # Keep the emulator package source of truth in this guest flake so
                # profile composition, package derivations, and launch adapters are
                # reviewed and versioned together.
                environment.systemPackages = [
                  (packageSetFor targetSystem).cemu
                  (packageSetFor targetSystem).steam
                  (packageSetFor targetSystem).ayn-odin2-ucm
                ];

                # Wire moonlight-embedded into the main-space profile. The
                # module installs the binary, stages /storage/.cache/moonlight
                # for persistent pair keys, and exposes the package option so
                # the inline package override below picks up the in-repo SM8550
                # v4l2m2m + SDL NV12 build instead of nixpkgs' upstream.
                rocknix.sm8550.moonlight = {
                  enable = true;
                  package = (packageSetFor targetSystem).moonlight-embedded;
                };
              }
            )
          ] ++ extraModules;
        };
      stage10ProofModule =
        { ... }:
        {
          environment.etc."rocknix-stage10-proof-marker".text = ''
            ROCKNIX Stage 10 generation-switch proof marker
            source=nix-on-rocks/guest
            target=explicit-sm8550-proof
          '';
        };
      mainSpaceThorConfiguration = mainSpaceConfigurationFor ./guest/profiles/devices/thor.nix [ ];
      mainSpaceOdin2PortalConfiguration = mainSpaceConfigurationFor ./guest/profiles/devices/odin2portal.nix [ ];
      stage10ProofThorConfiguration = mainSpaceConfigurationFor ./guest/profiles/devices/thor.nix [ stage10ProofModule ];
      stage10ProofOdin2PortalConfiguration = mainSpaceConfigurationFor ./guest/profiles/devices/odin2portal.nix [ stage10ProofModule ];
      # Backward-compatible alias: the production packaged rootfs remains the
      # hardware-validated Thor profile until host packaging selects a
      # device-specific rootfs explicitly.
      mainSpaceConfiguration = mainSpaceThorConfiguration;

      # Single source of truth for device-tree compatible -> device profile
      # mapping. Adding a new SM8550 device is one entry here plus a profile
      # under profiles/devices/. The host substrate must not maintain a
      # parallel device list; it asks for rocknix-guest-main-space-by-compatible
      # below and this table picks the right profile from /proc/device-tree.
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
            rocknix-guest-main-space-by-compatible requires the host substrate
            to normalize /proc/device-tree/compatible and pass a single
            compatible string. Use one of the explicit per-device attributes
            off-device, e.g.:
              nix build .#nixosConfigurations.rocknix-guest-main-space-odin2portal.config.system.build.toplevel
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

      mainSpaceByCompatibleConfiguration =
        mainSpaceConfigurationFor selectDeviceProfileFromCompatible [ ];
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
        main-space = ./guest/profiles/main-space.nix;
        odin2portal = ./guest/profiles/devices/odin2portal.nix;
        thor = ./guest/profiles/devices/thor.nix;
        default = ./guest/profiles/main-space.nix;
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
      nixosConfigurations.rocknix-guest-main-space = mainSpaceConfiguration;
      nixosConfigurations.rocknix-guest-main-space-thor = mainSpaceThorConfiguration;
      nixosConfigurations.rocknix-guest-main-space-odin2portal = mainSpaceOdin2PortalConfiguration;
      nixosConfigurations.rocknix-guest-stage10-proof-thor = stage10ProofThorConfiguration;
      nixosConfigurations.rocknix-guest-stage10-proof-odin2portal = stage10ProofOdin2PortalConfiguration;
      # Host-promoter entry point: picks the right per-device profile from
      # /proc/device-tree/compatible at eval time. Requires --impure on the
      # host. Keeps the device list and the per-device transforms in this
      # repo, next to the profiles, so adding a device is a single-PR change.
      nixosConfigurations.rocknix-guest-main-space-by-compatible =
        mainSpaceByCompatibleConfiguration;
      nixosConfigurations.rocknix-guest-dev-env = devEnvConfiguration;
      packages = forAllHostSystems (
        hostSystem:
        let
          rootfsThor = mkRootfs hostSystem mainSpaceThorConfiguration;
          rootfsOdin2Portal = mkRootfs hostSystem mainSpaceOdin2PortalConfiguration;
          rootfs = rootfsThor;
        in
        (packageSetFor hostSystem)
        // {
          inherit rootfs;
          "rootfs-thor" = rootfsThor;
          "rootfs-odin2portal" = rootfsOdin2Portal;
        }
      );
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
        }
      );
      formatter = forAllHostSystems (system: nixpkgs.legacyPackages.${system}.nixpkgs-fmt);
    };
}
