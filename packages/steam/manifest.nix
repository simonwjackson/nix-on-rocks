# ROCKNIX Steam ARM64 guest-native package contract for SM8550 package consumers.
#
# Keep this manifest aligned with the ROCKNIX Steam package sources listed in
# `rocknixSource.paths`. It is intentionally data-only so package derivations,
# docs, and static checks can share the same bootstrap/resource expectations
# without importing ROCKNIX host/session launch policy.

{
  pname = "steam-rocknix-guest-native";
  version = "1.0.0.85-rocknix-guest-native";

  rocknixSource = {
    repo = "github:simonwjackson/rocknix";
    rev = "a7b7898a11152b66475e0a6d72d090927c769731";
    paths = {
      package = "projects/ROCKNIX/packages/emulators/standalone/steam/package.mk";
      installHelper = "projects/ROCKNIX/packages/virtual/emulators/sources/Install Steam.sh";
      resources = "projects/ROCKNIX/packages/emulators/standalone/steam/resources";
      launcher = "projects/ROCKNIX/packages/emulators/standalone/steam/scripts/start_steam.sh";
    };
  };

  steamLauncher = {
    version = "1.0.0.85";
    debUrl = "https://repo.steampowered.com/steam/archive/stable/steam-launcher_1.0.0.85_amd64.deb";
    role = "ROCKNIX x86/FEX launcher source; not fetched by the v1 Nix derivation";
  };

  arm64Bootstrap = {
    runtimeTarUrl = "https://repo.steampowered.com/steamrt3c/images/latest-public-beta/steam-runtime-steamrt-arm64.tar.xz";
    clientManifestUrl = "https://client-update.fastly.steamstatic.com/steam_client_publicbeta_linuxarm64";
    cdnBaseUrl = "https://client-update.steamstatic.com";
    protonCompatibilityToolName = "Proton 11.0 (ARM64)";
    protonCompatibilityToolLink = "Proton11ARM";
  };

  resources = [
    {
      name = "compatibilitytool.vdf";
      file = ./resources/compatibilitytool.vdf;
      upstreamPath = "projects/ROCKNIX/packages/emulators/standalone/steam/resources/compatibilitytool.vdf";
      sha256 = "252d9af9ad94581de80af88aafd6be8323528245ddef7a95fa645897fcb1d903";
    }
    {
      name = "registry.vdf";
      file = ./resources/registry.vdf;
      upstreamPath = "projects/ROCKNIX/packages/emulators/standalone/steam/resources/registry.vdf";
      sha256 = "3cd5456968193f4f3fa15f291a795e6fa813e89691022dd3b94ad76e7ea029ce";
    }
    {
      name = "toolmanifest.vdf";
      file = ./resources/toolmanifest.vdf;
      upstreamPath = "projects/ROCKNIX/packages/emulators/standalone/steam/resources/toolmanifest.vdf";
      sha256 = "4e3179bb7bc94edee07622884ea3bd0ca9d4a911c5600eadef3979dbceafb59b";
    }
  ];

  packageContract = {
    supported = [
      "immutable Steam bootstrap/resource artifact"
      "generic env-driven steam-arm64-bootstrap helper"
      "generic env-driven steam-arm64-seed helper for guest-owned mutable ARM64 client/runtime state"
      "generic steam-guest-native launcher preflight that executes the ARM64 client inside the guest"
      "resource/evidence output for downstream ROCKNIX or guest adapters"
    ];
    downstreamOwned = [
      "target Steam home and library layout"
      "FEX rootfs and thunk configuration"
      "binfmt toggling"
      "host or guest display-session orchestration"
      "Gamescope launch geometry"
      "per-game Proton or compatibility settings"
      "SM8550 power and affinity policy"
    ];
    unsupported = [
      "nix run .#steam as a complete Steam desktop launcher"
      "guest-native Steam client execution without a guest-provided nix-ld or FHS dynamic-linker strategy"
      "immutable Nix-store Valve ARM64 client/runtime seed artifacts in v1"
    ];
  };
}
