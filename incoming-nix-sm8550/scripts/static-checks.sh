#!/usr/bin/env bash
set -euo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -f flake.nix ]] || fail "run from repo root"

grep -q 'cemu = pkgs.callPackage ./packages/cemu/package.nix' flake.nix \
  || fail "root flake must expose packages.cemu from packages/cemu"
grep -q 'default = cemu' flake.nix \
  || fail "default package must alias cemu"
grep -q 'cemu-rocknix-package = cemu' flake.nix \
  || fail "compatibility alias must remain available for current consumers"
grep -q 'steam = pkgs.callPackage ./packages/steam/package.nix' flake.nix \
  || fail "root flake must expose packages.steam from packages/steam"
grep -q 'steam = steam' flake.nix \
  || fail "packages.steam must be exposed"
grep -q 'moonlight-embedded = pkgs.callPackage ./packages/moonlight-embedded/package.nix' flake.nix \
  || fail "root flake must expose packages.moonlight-embedded from packages/moonlight-embedded"
grep -q 'moonlight-embedded = moonlight-embedded' flake.nix \
  || fail "packages.moonlight-embedded must be exposed"

grep -q 'exec "\\$cemu_wrapper_dir/Cemu"' packages/cemu/package.nix \
  || fail "package wrapper must exec real Cemu binary"
grep -q 'vulkan_loader_lib_path=' packages/cemu/package.nix \
  || fail "package wrapper must own Vulkan loader path"
grep -q 'SDL_VIDEO_ALLOW_SCREENSAVER' packages/cemu/package.nix \
  || fail "package wrapper must own SDL screensaver guard"

grep -q 'ROCKNIX cemu-sa package contract' packages/cemu/manifest.nix \
  || fail "Cemu manifest must document ROCKNIX package contract source"

grep -q 'ROCKNIX Steam ARM64 guest-native package contract' packages/steam/manifest.nix \
  || fail "Steam manifest must document ROCKNIX package contract source"
grep -q 'rev = "[0-9a-f]\{40\}"' packages/steam/manifest.nix \
  || fail "Steam manifest must record pinned ROCKNIX source revision"
grep -q 'guest-native-steam-target=true' packages/steam/package.nix \
  || fail "Steam package evidence must target guest-native Steam"
grep -q 'host-steam-fallback=false' packages/steam/package.nix \
  || fail "Steam package must not fall back to host Steam"
grep -q 'immutable-nix-store-valve-arm64-seed-artifacts=false' packages/steam/package.nix \
  || fail "Steam v1 package must not claim immutable Nix-store Valve ARM64 seed artifacts"
grep -q 'steam-arm64-bootstrap' packages/steam/package.nix \
  || fail "Steam package must install bootstrap helper"
grep -q 'steam-arm64-seed' packages/steam/package.nix \
  || fail "Steam package must install ARM64 seed helper"
grep -q 'steam-guest-native' packages/steam/package.nix \
  || fail "Steam package must install guest-native launcher helper"
grep -q 'STEAM_HOME' packages/steam/scripts/steam-arm64-bootstrap \
  || fail "Steam bootstrap helper must require explicit STEAM_HOME"
grep -q 'STEAM_GAMES_ROOT' packages/steam/scripts/steam-arm64-bootstrap \
  || fail "Steam bootstrap helper must require explicit STEAM_GAMES_ROOT"
grep -q 'STEAM_DOT' packages/steam/scripts/steam-arm64-bootstrap \
  || fail "Steam bootstrap helper must require explicit STEAM_DOT"
grep -q -- '--dry-run' packages/steam/scripts/steam-arm64-bootstrap \
  || fail "Steam bootstrap helper must support dry-run mode"
grep -q 'steam` | ROCKNIX-informed guest-native Steam ARM64 package helpers' README.md \
  || fail "root README must document Steam package as guest-native helpers"
grep -q 'STEAM_MANIFEST_URL' packages/steam/scripts/steam-arm64-seed \
  || fail "Steam seed helper must know the ARM64 client manifest endpoint"
grep -q 'steamrtarm64/steam' packages/steam/scripts/steam-guest-native \
  || fail "Steam guest-native helper must execute the ARM64 Steam client"
grep -q 'NIX_LD' packages/steam/scripts/steam-guest-native \
  || fail "Steam guest-native helper must preflight NixOS dynamic linker strategy"

for resource in compatibilitytool.vdf registry.vdf toolmanifest.vdf; do
  [[ -f "packages/steam/resources/${resource}" ]] \
    || fail "Steam resource missing: ${resource}"
done

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck packages/steam/scripts/steam-arm64-bootstrap \
    packages/steam/scripts/steam-arm64-seed \
    packages/steam/scripts/steam-guest-native
fi

! grep -R 'systemctl\|swaymsg\|FEXRootFSFetcher\|gamescope\|/storage' \
  packages/steam/package.nix packages/steam/scripts >/tmp/nix-sm8550-steam-boundary-grep.$$ \
  || { cat /tmp/nix-sm8550-steam-boundary-grep.$$ >&2; rm -f /tmp/nix-sm8550-steam-boundary-grep.$$; fail "Steam package executable logic must not own ROCKNIX host/session/storage policy"; }
rm -f /tmp/nix-sm8550-steam-boundary-grep.$$

# moonlight-embedded package invariants.
grep -q 'moonlight-embedded package contract' packages/moonlight-embedded/manifest.nix \
  || fail "moonlight-embedded manifest must document downstream package contract"
grep -q 'rev = "[0-9a-f]\{40\}"' packages/moonlight-embedded/manifest.nix \
  || fail "moonlight-embedded manifest must record pinned upstream source revision"
grep -q 'fetchSubmodules = true' packages/moonlight-embedded/manifest.nix \
  || fail "moonlight-embedded manifest must fetch submodules"
grep -q 'mainProgram = "moonlight"' packages/moonlight-embedded/package.nix \
  || fail "moonlight-embedded package must declare moonlight as mainProgram"
grep -q 'moonlight-embedded` | ' README.md \
  || fail "root README must list moonlight-embedded in the packages table"

# moonlight-embedded patches directory and dev-checkout helper.
[[ -f packages/moonlight-embedded/patches/README.md ]] \
  || fail "moonlight-embedded patches/ directory must have a README documenting the patch stack"
grep -q '0001-vendored-ffmpeg-drm-prime-pr932.patch' packages/moonlight-embedded/patches/README.md \
  || fail "patches README must name the planned vendored PR #932 patch"
grep -q '0002-add-v4l2m2m-egl-platform.patch' packages/moonlight-embedded/patches/README.md \
  || fail "patches README must name the planned v4l2m2m platform patch"
[[ -x scripts/moonlight-embedded-dev-checkout.sh ]] \
  || fail "moonlight-embedded dev-checkout helper must be executable"
grep -q 'manifest-pinned commit' scripts/moonlight-embedded-dev-checkout.sh \
  || fail "moonlight-embedded dev-checkout helper must read source pin from manifest"
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck scripts/moonlight-embedded-dev-checkout.sh
fi

# moonlight-embedded patch-stack correlation: every file listed in
# manifest.patches[].file must exist on disk, and manifest.expectedPlatforms
# must correlate with the patches that introduce each platform. Drift
# between these three surfaces (filesystem, manifest patches list, manifest
# expectedPlatforms list) is the most likely class of bug as U3/U5 land
# patches incrementally — a stale expectedPlatforms entry, a manifest
# entry pointing at a moved file, etc. Cheap to guard against here.
me_manifest=packages/moonlight-embedded/manifest.nix
me_patches_dir=packages/moonlight-embedded/patches

# Extract patch filenames referenced as `file = ./patches/<name>;` from the
# patches attrset and verify each exists. awk + regex is enough — the
# manifest is data-only Nix with a predictable shape.
while IFS= read -r patch_file; do
  [[ -n "$patch_file" ]] || continue
  [[ -f "$me_patches_dir/$patch_file" ]] \
    || fail "manifest references patches/$patch_file but file does not exist"
done < <(awk -F'[/;]' '/file = \.\/patches\//{print $3}' "$me_manifest")

# Conversely: every *.patch file on disk must be referenced in the
# manifest. Otherwise a patch is sitting in patches/ unused and confusing.
shopt -s nullglob
for patch_path in "$me_patches_dir"/*.patch; do
  patch_basename=$(basename "$patch_path")
  grep -qF "./patches/$patch_basename" "$me_manifest" \
    || fail "patches/$patch_basename exists but is not listed in $me_manifest"
done
shopt -u nullglob

# expectedPlatforms always includes "sdl" (upstream-provided fallback).
grep -E '^\s*"sdl"' "$me_manifest" >/dev/null \
  || fail "manifest expectedPlatforms must always list sdl (the upstream fallback)"

# Patch ↔ platform correlation. Each known patch implies a specific
# platform must appear (uncommented) in expectedPlatforms; absence of the
# patch must NOT advertise the platform.
me_check_platform_correlation() {
  local patch=$1 platform=$2
  local patch_listed platform_listed
  if grep -qF "./patches/$patch" "$me_manifest"; then
    patch_listed=yes
  else
    patch_listed=no
  fi
  if grep -E "^\s*\"${platform}\"" "$me_manifest" >/dev/null; then
    platform_listed=yes
  else
    platform_listed=no
  fi
  if [[ "$patch_listed" != "$platform_listed" ]]; then
    fail "manifest patch/platform correlation drift: patches:$patch=$patch_listed but expectedPlatforms:$platform=$platform_listed"
  fi
}
me_check_platform_correlation 0001-vendored-ffmpeg-drm-prime-pr932.patch ffmpeg_drm
me_check_platform_correlation 0002-add-v4l2m2m-egl-platform.patch v4l2m2m

# moonlight-embedded boundary: package must not own session/launcher/host policy.
! grep -R 'systemctl\|swaymsg\|FEXRootFSFetcher\|gamescope\|/storage\|sunshine' \
  packages/moonlight-embedded/package.nix \
  packages/moonlight-embedded/manifest.nix \
  >/tmp/nix-sm8550-moonlight-boundary-grep.$$ \
  || { cat /tmp/nix-sm8550-moonlight-boundary-grep.$$ >&2; rm -f /tmp/nix-sm8550-moonlight-boundary-grep.$$; fail "moonlight-embedded package must not own session/launch/host policy"; }
rm -f /tmp/nix-sm8550-moonlight-boundary-grep.$$

! find . -path './.git' -prune -o -path './integrations/*' -print | grep -q . \
  || fail "package-only repo must not include integration adapters yet"
! grep -R 'host-tune\|remote-cemu-promote\|start_cemu_guest\|cemu-storage-adapter' \
  --exclude-dir=.git \
  --exclude='static-checks.sh' \
  . >/tmp/nix-sm8550-integration-grep.$$ \
  || { cat /tmp/nix-sm8550-integration-grep.$$ >&2; rm -f /tmp/nix-sm8550-integration-grep.$$; fail "package-only repo must not reference ROCKNIX integration scripts"; }
rm -f /tmp/nix-sm8550-integration-grep.$$
