{ pkgs, self, system }:

let
  helpers = import ./helpers.nix { inherit pkgs; };
  assertContract = helpers.assertContract "flake surface contract";
  packages = self.packages.${system};
  fixtureProfiles = {
    "ayn,thor" = "thor-profile";
    "ayn,odin2portal" = "odin2portal-profile";
    "anbernic,rg353p" = "rg353p-profile";
    "anbernic,rg353m" = "rg353m-profile";
  };
  fixtureModelAliases = {
    "Anbernic RG353M" = "anbernic,rg353m";
  };
  selectedThorKey = self.lib.deviceProfileKeyFromIdentity {
    profiles = fixtureProfiles;
    compatibleStrings = [ "ayn,thor" "qcom,sm8550" ];
  };
  selectedRg353mKey = self.lib.deviceProfileKeyFromIdentity {
    profiles = fixtureProfiles;
    modelAliases = fixtureModelAliases;
    model = "Anbernic RG353M";
    compatibleStrings = [ "anbernic,rg353p" "rockchip,rk3566" ];
  };
  selectedRg353pKey = self.lib.deviceProfileKeyFromIdentity {
    profiles = fixtureProfiles;
    modelAliases = fixtureModelAliases;
    model = "Anbernic RG353P";
    compatibleStrings = [ "anbernic,rg353p" "rockchip,rk3566" ];
  };
  selectedRg353mProfile = self.lib.selectDeviceProfileFromIdentity {
    profiles = fixtureProfiles;
    modelAliases = fixtureModelAliases;
    model = "Anbernic RG353M";
    compatibleStrings = [ "anbernic,rg353p" "rockchip,rk3566" ];
  };
  capturedRg353mCompatibleKey = self.lib.deviceProfileKeyFromIdentity {
    model = "Rockchip RK3566 RK817 TABLET LP4X Board";
    compatibleStrings = [ "rockchip,rk3566-rk817-tablet" "rockchip,rk3566" ];
  };
  capturedRg353mProfile = self.lib.selectDeviceProfileFromIdentity {
    model = "Rockchip RK3566 RK817 TABLET LP4X Board";
    compatibleStrings = [ "rockchip,rk3566-rk817-tablet" "rockchip,rk3566" ];
  };
  rg353mGenericCompatibleOnlyKey = self.lib.deviceProfileKeyFromIdentity {
    model = "Rockchip RK3566 RK817 TABLET LP4X Board";
    compatibleStrings = [ "rockchip,rk3566" ];
  };
  capturedSdRg353mKey = self.lib.deviceProfileKeyFromIdentity {
    model = "Anbernic RG353M";
    compatibleStrings = [ "anbernic,rg353p" "rockchip,rk3566" ];
  };
  capturedSdRg353mProfile = self.lib.selectDeviceProfileFromIdentity {
    model = "Anbernic RG353M";
    compatibleStrings = [ "anbernic,rg353p" "rockchip,rk3566" ];
  };
  rg353pCompatibleOnlyKey = self.lib.deviceProfileKeyFromIdentity {
    model = "Anbernic RG353P";
    compatibleStrings = [ "anbernic,rg353p" "rockchip,rk3566" ];
  };
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
  (assertContract (self.nixosModules ? rk3566) "nixosModules.rk3566 is exposed")
  (assertContract (self.nixosModules ? rg353m) "nixosModules.rg353m is exposed")
  (assertContract (self.lib ? mkGuestRootfs) "lib.mkGuestRootfs is exposed")
  (assertContract (self.lib ? deviceProfileByCompatible) "lib.deviceProfileByCompatible is exposed")
  (assertContract (self.lib ? deviceProfileByModel) "lib.deviceProfileByModel is exposed")
  (assertContract (self.lib ? deviceProfileKeyFromIdentity) "lib.deviceProfileKeyFromIdentity is exposed")
  (assertContract (self.lib ? selectDeviceProfileFromIdentity) "lib.selectDeviceProfileFromIdentity is exposed")
  (assertContract (self.lib.deviceProfileByCompatible ? "ayn,thor") "Thor device-compatible profile is registered")
  (assertContract (self.lib.deviceProfileByCompatible ? "ayn,odin2portal") "Odin 2 Portal device-compatible profile is registered")
  (assertContract (self.lib.deviceProfileByCompatible ? "rockchip,rk3566-rk817-tablet") "captured RG353M RK3566/RK817 compatible profile is registered")
  (assertContract (self.lib.deviceProfileByModel."Anbernic RG353M" == "rockchip,rk3566-rk817-tablet") "captured SD-boot RG353M model aliases to the registered RG353M profile key")
  (assertContract (self.nixosConfigurations ? rocknix-guest-rg353m) "RG353M NixOS profile configuration is exposed")
  (assertContract (selectedThorKey == "ayn,thor") "direct compatible selection preserves known SM8550 devices")
  (assertContract (selectedRg353mKey == "anbernic,rg353m") "RG353M model alias overrides ambiguous RG353P compatible")
  (assertContract (selectedRg353pKey == "anbernic,rg353p") "RG353P uses direct compatible selection when no model alias applies")
  (assertContract (selectedRg353mProfile == "rg353m-profile") "identity selector returns the model-aliased RG353M profile")
  (assertContract (capturedRg353mCompatibleKey == "rockchip,rk3566-rk817-tablet") "captured RG353M identity selects the RK3566/RK817 compatible key")
  (assertContract (capturedRg353mProfile == self.lib.deviceProfileByCompatible."rockchip,rk3566-rk817-tablet") "captured RG353M identity returns the RG353M profile path")
  (assertContract (rg353mGenericCompatibleOnlyKey == null) "generic rockchip,rk3566 alone does not select any registered profile")
  (assertContract (capturedSdRg353mKey == "rockchip,rk3566-rk817-tablet") "captured SD-boot RG353M identity selects the RG353M model alias")
  (assertContract (capturedSdRg353mProfile == self.lib.deviceProfileByCompatible."rockchip,rk3566-rk817-tablet") "captured SD-boot RG353M identity returns the RG353M profile path")
  (assertContract (rg353pCompatibleOnlyKey == null) "RG353P-shaped compatible without RG353M model does not select RG353M")
]
