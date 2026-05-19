{ lib
, stdenvNoCC
, makeWrapper
, bash
, binutils
, coreutils
, curl
, findutils
, gnugrep
, gnutar
, gzip
, unzip
}:

let
  manifest = import ./manifest.nix;
  resourceNames = map (resource: resource.name) manifest.resources;
in

stdenvNoCC.mkDerivation {
  pname = manifest.pname;
  version = manifest.version;

  src = ./.;

  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    install -Dm755 scripts/steam-arm64-bootstrap \
      "$out/bin/steam-arm64-bootstrap"
    install -Dm755 scripts/steam-arm64-seed \
      "$out/bin/steam-arm64-seed"
    install -Dm755 scripts/steam-guest-native \
      "$out/bin/steam-guest-native"

    mkdir -p \
      "$out/share/steam-rocknix-bootstrap/resources" \
      "$out/nix-support/rocknix-steam-bootstrap"

    for resource in ${lib.escapeShellArgs resourceNames}; do
      install -Dm644 "resources/$resource" \
        "$out/share/steam-rocknix-bootstrap/resources/$resource"
    done

    cat > "$out/nix-support/rocknix-steam-bootstrap/manifest.txt" <<EOF
pname=${manifest.pname}
version=${manifest.version}
rocknix-repo=${manifest.rocknixSource.repo}
rocknix-rev=${manifest.rocknixSource.rev}
rocknix-package-path=${manifest.rocknixSource.paths.package}
rocknix-install-helper-path=${manifest.rocknixSource.paths.installHelper}
rocknix-resource-path=${manifest.rocknixSource.paths.resources}
rocknix-launcher-path=${manifest.rocknixSource.paths.launcher}
steam-launcher-version=${manifest.steamLauncher.version}
steam-launcher-deb-url=${manifest.steamLauncher.debUrl}
steam-arm64-runtime-url=${manifest.arm64Bootstrap.runtimeTarUrl}
steam-arm64-client-manifest-url=${manifest.arm64Bootstrap.clientManifestUrl}
steam-arm64-cdn-base-url=${manifest.arm64Bootstrap.cdnBaseUrl}
proton-compatibility-tool-name=${manifest.arm64Bootstrap.protonCompatibilityToolName}
proton-compatibility-tool-link=${manifest.arm64Bootstrap.protonCompatibilityToolLink}
package-entry-points=bin/steam-arm64-bootstrap bin/steam-arm64-seed bin/steam-guest-native
steam-client-launcher=guest-native-helper
host-steam-fallback=false
guest-native-steam-target=true
immutable-nix-store-valve-arm64-seed-artifacts=false
downstream-owns-target-layout=true
downstream-owns-fex-rootfs=true
downstream-owns-session-launch=true
resources=${lib.concatStringsSep " " resourceNames}
EOF

    cat > "$out/nix-support/rocknix-steam-bootstrap/resource-sha256.txt" <<EOF
${lib.concatMapStringsSep "\n" (resource: "${resource.sha256}  ${resource.name}") manifest.resources}
EOF

    wrapProgram "$out/bin/steam-arm64-bootstrap" \
      --prefix PATH : ${lib.makeBinPath [ bash coreutils ]}
    wrapProgram "$out/bin/steam-arm64-seed" \
      --prefix PATH : ${lib.makeBinPath [ bash binutils coreutils curl findutils gnugrep gnutar gzip unzip ]}
    wrapProgram "$out/bin/steam-guest-native" \
      --prefix PATH : ${lib.makeBinPath [ bash coreutils ]}

    runHook postInstall
  '';

  passthru = {
    rocknixSteamManifest = manifest;
  };

  meta = {
    description = "ROCKNIX-informed guest-native Steam ARM64 package helpers for SM8550";
    homepage = "https://store.steampowered.com/";
    license = lib.licenses.gpl2Only;
    platforms = [ "x86_64-linux" "aarch64-linux" ];
  };
}
