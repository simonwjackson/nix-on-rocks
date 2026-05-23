#!/usr/bin/env bash
# Prepare a scratch checkout of upstream moonlight-embedded at the
# manifest-pinned commit, with this repo's downstream patches applied as
# git commits on top. Use this to develop / iterate on the patch stack
# before exporting final patches into packages/moonlight-embedded/patches/.
#
# Idempotent: re-running against an existing checkout is a no-op (does not
# re-clone, does not re-apply already-applied patches).
#
# Output: a working git tree at /tmp/moonlight-embedded-dev/<short-rev>/
# containing upstream HEAD + N applied patch commits, branched as
# `nix-sm8550-dev`. Patches can be edited normally; when done, run
#
#   git -C <checkout> format-patch <short-rev>..nix-sm8550-dev \
#       -o <repo>/packages/moonlight-embedded/patches/
#
# to produce the final patch files.

set -euo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }
info() { echo "[dev-checkout] $*"; }

# Resolve repo root (the directory containing flake.nix, walking up from
# this script's location).
script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH='' cd -- "$script_dir/.." && pwd)
[[ -f "$repo_root/flake.nix" ]] \
  || fail "could not locate flake.nix above $script_dir"

manifest="$repo_root/packages/moonlight-embedded/manifest.nix"
[[ -f "$manifest" ]] \
  || fail "manifest not found: $manifest"

patches_dir="$repo_root/packages/moonlight-embedded/patches"

command -v nix >/dev/null \
  || fail "nix is required to read the manifest pin"
command -v git >/dev/null \
  || fail "git is required"

eval_pin() {
  # $1 = attribute path inside the manifest's `source` attrset
  nix eval --raw --impure --expr \
    "(import $manifest).source.$1" 2>/dev/null \
    || fail "could not read source.$1 from $manifest"
}

owner=$(eval_pin owner)
repo=$(eval_pin repo)
rev=$(eval_pin rev)
short_rev=$(eval_pin shortRev)

upstream_url="https://github.com/${owner}/${repo}.git"
scratch_root=${MOONLIGHT_DEV_ROOT:-/tmp/moonlight-embedded-dev}
checkout="$scratch_root/$short_rev"

info "manifest pin: $owner/$repo @ $rev ($short_rev)"
info "checkout target: $checkout"

if [[ -d "$checkout/.git" ]]; then
  info "checkout already present; skipping clone"
else
  mkdir -p "$scratch_root"
  info "cloning $upstream_url (this may take a minute)"
  git clone --quiet "$upstream_url" "$checkout"
fi

# Fetch and pin to the manifest rev. This is cheap when already at the rev.
git -C "$checkout" fetch --quiet --tags origin "$rev" \
  || git -C "$checkout" fetch --quiet origin
git -C "$checkout" -c advice.detachedHead=false checkout --quiet "$rev"

# Re-create the working branch fresh from the pinned rev so re-runs that
# changed patches start from a clean base. Stash any uncommitted user
# edits first so they survive (the user is in active iteration).
if git -C "$checkout" diff --quiet && git -C "$checkout" diff --cached --quiet; then
  :
else
  info "stashing uncommitted edits in working tree before re-base"
  git -C "$checkout" stash push --quiet --include-untracked \
    --message "dev-checkout-autostash-$(date -u +%s)" || true
fi
git -C "$checkout" branch --quiet -f nix-sm8550-dev "$rev"
git -C "$checkout" checkout --quiet nix-sm8550-dev

# Apply each downstream patch in order. Empty patches/ is fine; means the
# scratch tree is just upstream HEAD at the pin.
#
# Use LC_ALL=C ASCII collation for the glob: under en_US.UTF-8 (and many
# other locales) hyphens are sorted weakly, so `0001-vendored-...patch`
# and `0001a-fix-...patch` end up in reverse order relative to the Nix
# derivation's patches list, causing the dev tree to diverge from the
# build tree.
applied=0
if [[ -d "$patches_dir" ]]; then
  shopt -s nullglob
  patch_list=()
  while IFS= read -r path; do
    patch_list+=("$path")
  done < <(LC_ALL=C find "$patches_dir" -maxdepth 1 -type f -name '*.patch' | LC_ALL=C sort)
  for patch in "${patch_list[@]}"; do
    info "applying $(basename "$patch")"
    if ! git -C "$checkout" am --3way --quiet "$patch"; then
      git -C "$checkout" am --abort >/dev/null 2>&1 || true
      fail "patch failed to apply: $patch — resolve manually in $checkout"
    fi
    applied=$((applied + 1))
  done
  shopt -u nullglob
fi

if [[ $applied -eq 0 ]]; then
  info "no patches in $patches_dir yet; scratch tree is vanilla upstream"
else
  info "applied $applied patch(es) on top of $short_rev"
fi

cat <<EOF

  Scratch tree ready at:
    $checkout

  Next steps:

    # build ephemerally against the local source tree on the dev host
    cd $checkout
    cmake -B build -DCMAKE_BUILD_TYPE=Release
    cmake --build build -j

    # OR build via nix using a local source override (path on this host)
    # (typically done by editing manifest.nix's src to a path:// + nix build)

    # iterate freely: edit files, commit, run, repeat
    git -C $checkout add -p && git -C $checkout commit -m '…'

    # export the result as patch files back into this repo
    git -C $checkout format-patch $rev..nix-sm8550-dev \\
        -o $repo_root/packages/moonlight-embedded/patches/

EOF
