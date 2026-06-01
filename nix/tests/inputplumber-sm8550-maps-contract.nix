{ pkgs, mapsPackage }:

pkgs.runCommand "inputplumber-sm8550-maps-contract" { } ''
  set -euo pipefail

  expected_files=(
    share/inputplumber/capability_maps/ayaneo_mcu_japanese.yaml
    share/inputplumber/capability_maps/ayaneo_mcu_xbox.yaml
    share/inputplumber/capability_maps/ayn_mcu.yaml
    share/inputplumber/devices/01-ayaneo-controller-japanese.yaml
    share/inputplumber/devices/01-ayaneo-controller.yaml
    share/inputplumber/devices/02-ayn-controller.yaml
  )

  for expected_file in "''${expected_files[@]}"; do
    test -f "${mapsPackage}/$expected_file" \
      || { echo "missing InputPlumber SM8550 map: $expected_file" >&2; exit 1; }
  done

  if test -e "${mapsPackage}/bin/inputplumber"; then
    echo "inputplumber-sm8550-maps must be data-only and must not ship bin/inputplumber" >&2
    exit 1
  fi

  grep -q 'xb360' "${mapsPackage}/share/inputplumber/devices/02-ayn-controller.yaml" \
    || { echo "AYN controller map must advertise the validated xb360 target" >&2; exit 1; }

  touch "$out"
''
