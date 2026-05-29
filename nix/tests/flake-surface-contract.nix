{ pkgs, self, system }:

let
  helpers = import ./helpers.nix { inherit pkgs; };
  assertContract = helpers.assertContract "flake surface contract";
  packages = self.packages.${system};
in
helpers.runAssertions "rocknix-flake-surface-contract" [
  (assertContract (packages.default == packages.cemu) "default package aliases cemu")
  (assertContract (packages.cemu-rocknix-package == packages.cemu) "cemu-rocknix-package compatibility alias points at cemu")
  (assertContract (packages ? cemu) "packages.cemu is exposed")
  (assertContract (packages ? steam) "packages.steam is exposed")
  (assertContract (packages ? inputplumber) "packages.inputplumber is exposed")
  (assertContract (packages ? moonlight-embedded) "packages.moonlight-embedded is exposed")
  (assertContract (packages ? sm8550-ayn-odin2-ucm) "SM8550 UCM package alias is exposed")
  (assertContract (packages.cemu.drvPath != "") "packages.cemu has a derivation path")
  (assertContract (packages.steam.drvPath != "") "packages.steam has a derivation path")
  (assertContract (self.nixosModules ? rocknix-guest-base) "nixosModules.rocknix-guest-base is exposed")
  (assertContract (self.nixosModules ? odin2portal) "nixosModules.odin2portal is exposed")
  (assertContract (self.nixosModules ? thor) "nixosModules.thor is exposed")
  (assertContract (self.nixosModules ? sm8550) "nixosModules.sm8550 is exposed")
  (assertContract (self.lib ? mkGuestRootfs) "lib.mkGuestRootfs is exposed")
  (assertContract (self.lib ? deviceProfileByCompatible) "lib.deviceProfileByCompatible is exposed")
  (assertContract (self.lib.deviceProfileByCompatible ? "ayn,thor") "Thor device-compatible profile is registered")
  (assertContract (self.lib.deviceProfileByCompatible ? "ayn,odin2portal") "Odin 2 Portal device-compatible profile is registered")
]
