{ pkgs, steamPackage }:

pkgs.runCommand "rocknix-steam-package-output-contract"
  {
    nativeBuildInputs = [ pkgs.coreutils pkgs.gnugrep ];
  }
  ''
    set -eu

    package_out=${steamPackage}
    manifest="$package_out/nix-support/rocknix-steam-bootstrap/manifest.txt"

    for executable in \
      steam-arm64-bootstrap \
      steam-arm64-seed \
      steam-guest-native \
      steam-guest-runtime-prep \
      steam-guest-run; do
      test -x "$package_out/bin/$executable" || {
        echo "built Steam package missing executable: $executable" >&2
        exit 1
      }
    done

    test -f "$manifest" || {
      echo "built Steam package missing bootstrap manifest: $manifest" >&2
      exit 1
    }

    grep -q 'steam-runtime-prep-helper=bin/steam-guest-runtime-prep' "$manifest" || {
      echo "built Steam package evidence missing runtime prep helper" >&2
      exit 1
    }

    grep -q 'steam-run-capsule=' "$manifest" || {
      echo "built Steam package evidence missing run capsule entry" >&2
      exit 1
    }

    if grep -q 'steam-run-capsule=bin/steam-arm64-fhs' "$manifest"; then
      test -x "$package_out/bin/steam-arm64-fhs" || {
        echo "Steam package evidence claims missing steam-arm64-fhs" >&2
        exit 1
      }
    fi

    for resource in compatibilitytool.vdf registry.vdf toolmanifest.vdf; do
      test -f "$package_out/share/steam-rocknix-bootstrap/resources/$resource" || {
        echo "built Steam package missing resource: $resource" >&2
        exit 1
      }
    done

    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    mkdir -p "$tmp/Steam/steamrtarm64"
    : > "$tmp/Steam/steamrtarm64/steam"
    chmod 755 "$tmp/Steam/steamrtarm64/steam"
    STEAM_HOME="$tmp/Steam" FEX_ROOTFS="$tmp/fex" \
      "$package_out/bin/steam-guest-run" --check >/tmp/steam-guest-run-built-check.out
    test ! -e "$tmp/Steam/prep-applied" || {
      echo "built steam-guest-run --check must not apply mutable prep" >&2
      exit 1
    }

    touch $out
  ''
