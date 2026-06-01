{ lib, stdenvNoCC }:

stdenvNoCC.mkDerivation {
  pname = "inputplumber-sm8550-maps";
  version = "0.75.2";

  src = ./maps;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/share/inputplumber"
    cp -a . "$out/share/inputplumber/"

    runHook postInstall
  '';

  meta = {
    description = "SM8550 handheld controller maps for InputPlumber";
    homepage = "https://github.com/ShadowBlip/InputPlumber";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
  };
}
