{
  lib,
  symlinkJoin,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  udev,
  libiio,
  libevdev,
}:

let
  # ROCKNIX host packages InputPlumber v0.75.2. The guest flake's pinned
  # nixpkgs can lag behind, so keep this narrow package until the flake pin
  # naturally catches up. The SM8550 maps copied below were validated against
  # v0.75.2 on the host.
  inputplumber_0_75_2 = rustPlatform.buildRustPackage (finalAttrs: {
    pname = "inputplumber";
    version = "0.75.2";

    src = fetchFromGitHub {
      owner = "ShadowBlip";
      repo = "InputPlumber";
      tag = "v${finalAttrs.version}";
      hash = "sha256-KiSroDcaWvzr5sP0jzr1GFyk0lHbtCFJrP3g5/b3hLQ=";
    };

    cargoHash = "sha256-VwQ38Jv5OvyBqo9BBTnpUjgNwAbWyIdUKFKXsGC6+Mo=";

    nativeBuildInputs = [
      pkg-config
      rustPlatform.bindgenHook
    ];

    buildInputs = [
      udev
      libevdev
      libiio
    ];

    postInstall = ''
      cp -r rootfs/usr/* $out/
    '';

    meta = {
      description = "Open source input router and remapper daemon for Linux";
      homepage = "https://github.com/ShadowBlip/InputPlumber";
      license = lib.licenses.gpl3Plus;
      changelog = "https://github.com/ShadowBlip/InputPlumber/releases/tag/v${finalAttrs.version}";
      maintainers = with lib.maintainers; [ shadowapex ];
      mainProgram = "inputplumber";
    };
  });
in
symlinkJoin {
  name = "rocknix-inputplumber-${inputplumber_0_75_2.version}";
  paths = [ inputplumber_0_75_2 ];

  postBuild = ''
    rm -rf "$out/share/inputplumber"
    mkdir -p "$out/share"
    cp -a ${inputplumber_0_75_2}/share/inputplumber "$out/share/"
    chmod -R u+w "$out/share/inputplumber"
    cp -a ${./sm8550}/. "$out/share/inputplumber/"
  '';

  meta = inputplumber_0_75_2.meta // {
    description = "InputPlumber with ROCKNIX SM8550 controller maps";
  };
}
