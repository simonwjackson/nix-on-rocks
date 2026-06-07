{ lib, stdenvNoCC }:

# RG353M (Rockchip RK3566, Mali-G52) InputPlumber maps as a guest-closure data
# package. Added to the RG353M guest's environment.systemPackages so the
# in-guest InputPlumber discovers them via XDG_DATA_DIRS
# (/run/current-system/sw/share/inputplumber), the same discovery path the
# nixpkgs inputplumber service already relies on.
#
# Mirrors packages/inputplumber-sm8550-maps (data-only; must not ship a binary).
stdenvNoCC.mkDerivation {
  pname = "inputplumber-rk3566-maps";
  version = "0.75.2";

  src = ./maps;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/share/inputplumber"
    cp -a . "$out/share/inputplumber/"

    runHook postInstall
  '';

  meta = {
    description = "RK3566 (RG353M) handheld controller maps for InputPlumber";
    homepage = "https://github.com/ShadowBlip/InputPlumber";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
  };
}
