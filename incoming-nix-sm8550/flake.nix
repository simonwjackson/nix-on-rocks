{
  description = "SM8550 emulator package monorepo";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # ROCKNIX Cemu is built against classic SDL2. nixos-unstable aliases SDL2
    # to sdl2-compat, so keep a narrow 24.11 input only for that build input.
    nixpkgs-sdl2-classic.url = "github:NixOS/nixpkgs/nixos-24.11";
  };

  outputs = { self, nixpkgs, nixpkgs-sdl2-classic }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
    in {
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          pkgsSdl2Classic = nixpkgs-sdl2-classic.legacyPackages.${system};
          cemu = pkgs.callPackage ./packages/cemu/package.nix {
            SDL2_classic = pkgsSdl2Classic.SDL2;
          };
          steam = pkgs.callPackage ./packages/steam/package.nix { };
          moonlight-embedded = pkgs.callPackage ./packages/moonlight-embedded/package.nix { };
        in {
          default = cemu;
          cemu = cemu;
          steam = steam;
          moonlight-embedded = moonlight-embedded;
          # Compatibility alias for ROCKNIX Layer 14 scripts/docs while they
          # migrate to the shorter monorepo package name.
          cemu-rocknix-package = cemu;
        });

      checks = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in {
          static = pkgs.runCommand "nix-sm8550-static-checks" {
            nativeBuildInputs = [ pkgs.shellcheck ];
          } ''
            cd ${self}
            ${pkgs.bash}/bin/bash scripts/static-checks.sh
            touch $out
          '';
        });

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixpkgs-fmt);
    };
}
