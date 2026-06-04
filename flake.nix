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
      nixLib = nixpkgs.lib;
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
          inputplumber-sm8550-maps = pkgs.callPackage ./packages/inputplumber-sm8550-maps/package.nix { };
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
          inputplumber-sm8550-maps = inputplumber-sm8550-maps;
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
      # Model aliases are intentionally empty until hardware evidence proves a
      # product needs one. RG353-family U-Boot can expose a reused compatible
      # string for a metal-shell variant, so downstream tests exercise this seam
      # with an explicit fixture table before the physical device arrives.
      deviceProfileByModel = { };

      deviceProfileKeyFromIdentity =
        args:
        let
          profiles = args.profiles or deviceProfileByCompatible;
          modelAliases = args.modelAliases or deviceProfileByModel;
          model = args.model or "";
          compatibleStrings = args.compatibleStrings or [ ];
          modelProfileKey =
            if model != "" && builtins.hasAttr model modelAliases then
              modelAliases.${model}
            else
              null;
          compatibleProfileKey = nixLib.findFirst
            (compatible: builtins.hasAttr compatible profiles)
            null
            compatibleStrings;
        in
        if modelProfileKey != null && builtins.hasAttr modelProfileKey profiles then
          modelProfileKey
        else
          compatibleProfileKey;

      selectDeviceProfileFromIdentity =
        args:
        let
          profiles = args.profiles or deviceProfileByCompatible;
          profileKey = deviceProfileKeyFromIdentity (args // {
            inherit profiles;
          });
        in
        if profileKey == null then
          throw ''
            nix-on-rocks guest: no guest profile registered for device identity.
            Model: ${builtins.toJSON (args.model or "")}
            Compatible strings: ${builtins.toJSON (args.compatibleStrings or [ ])}
            Add profiles/devices/<device>.nix and register a matching compatible
            string or documented model alias in flake.nix.
          ''
        else
          profiles.${profileKey};

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
      # Per-device evaluations expose substrate capabilities composed with
      # the form-factor profiles. They exist solely as contract surfaces
      # so the SM8550 substrate can be asserted under each shipped device
      # without a downstream product flake.
      thorConfiguration = nixpkgs.lib.nixosSystem {
        system = targetSystem;
        modules = [
          ./guest/profiles/rocknix-guest-base.nix
          ./guest/profiles/devices/thor.nix
        ];
      };
      odin2portalConfiguration = nixpkgs.lib.nixosSystem {
        system = targetSystem;
        modules = [
          ./guest/profiles/rocknix-guest-base.nix
          ./guest/profiles/devices/odin2portal.nix
        ];
      };
      # Synthetic per-device override: proves the SM8550 video decode
      # backend can be overridden by a device profile without editing the
      # shared chipset module or the product layer.
      videoOverrideConfiguration = nixpkgs.lib.nixosSystem {
        system = targetSystem;
        modules = [
          ./guest/profiles/rocknix-guest-base.nix
          ./guest/profiles/devices/thor.nix
          ({ lib, ... }: {
            networking.hostName = lib.mkForce "rocknix-video-override-contract";
            rocknix.sm8550.video.decodeBackend = lib.mkForce "sdl";
          })
        ];
      };
      mainSpaceConfiguration = nixpkgs.lib.nixosSystem {
        system = targetSystem;
        modules = [
          ./guest/profiles/main-space.nix
          ({ lib, ... }: { networking.hostName = lib.mkForce "rocknix-main-space-contract"; })
        ];
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
        # Collapsed SM8550 chipset surface (device options + neutral
        # audio/video capability imports). Replaces the legacy flat
        # `./guest/modules/device.nix` module.
        sm8550 = ./guest/modules/chipsets/sm8550;
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
        inherit
          deviceProfileByCompatible
          deviceProfileByModel
          deviceProfileKeyFromIdentity
          selectDeviceProfileFromCompatible
          selectDeviceProfileFromIdentity
          ;
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
          # Compatibility attr name for callers that used the old monolithic
          # static check. Keep the flake check surface Nix-owned; shell smoke,
          # boundary lint, and docs contracts run through named scripts/ steps.
          static = import ./nix/tests/flake-surface-contract.nix {
            inherit pkgs self system;
          };
          steam-package-contract = import ./nix/tests/steam-package-output-contract.nix {
            inherit pkgs;
            steamPackage = self.packages.${system}.steam;
          };
          flake-surface-contract = import ./nix/tests/flake-surface-contract.nix {
            inherit pkgs self system;
          };
          inputplumber-sm8550-maps-contract = import ./nix/tests/inputplumber-sm8550-maps-contract.nix {
            inherit pkgs;
            mapsPackage = self.packages.${system}.inputplumber-sm8550-maps;
          };
          guest-input-boundary-contract = import ./nix/tests/guest-input-boundary-contract.nix {
            inherit pkgs baseConfiguration devEnvConfiguration;
          };
          guest-profile-contract = import ./nix/tests/guest-profile-contract.nix {
            inherit pkgs baseConfiguration devEnvConfiguration
              thorConfiguration odin2portalConfiguration
              videoOverrideConfiguration;
          };
          main-space-systemd-contract = import ./nix/tests/main-space-systemd-contract.nix {
            inherit pkgs mainSpaceConfiguration devEnvConfiguration;
          };
          audio-input-systemd-contract = import ./nix/tests/audio-input-systemd-contract.nix {
            inherit pkgs baseConfiguration devEnvConfiguration
              thorConfiguration odin2portalConfiguration;
          };
        }
      );
      formatter = forAllHostSystems (system: nixpkgs.legacyPackages.${system}.nixpkgs-fmt);
    };
}
