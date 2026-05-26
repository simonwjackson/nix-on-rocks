#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH="" cd -- "$(dirname -- "$0")/../.." && pwd)
product_lock="${repo_root}/product-payload.lock"
guest_lock="${repo_root}/guest.lock"
renderer="${repo_root}/scripts/render-product-payload"
verifier="${repo_root}/scripts/verify-product-payload"
work_dir=${NIX_ON_ROCKS_WORKDIR:-"${repo_root}/work/rocknix"}
package_mk="${work_dir}/projects/ROCKNIX/packages/tools/rocknix-guest-substrate/package.mk"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

require_file() {
  local path=$1
  [ -f "${path}" ] || fail "missing ${path}"
}

require_nonempty() {
  local name=$1
  local value=$2
  [ -n "${value}" ] || fail "${name} must not be empty"
}

require_equal() {
  local name=$1
  local actual=$2
  local expected=$3
  [ "${actual}" = "${expected}" ] || fail "${name}: expected '${expected}', got '${actual}'"
}

copy_package_fixture() {
  local tmp_work=$1
  local fixture_package_mk="${tmp_work}/projects/ROCKNIX/packages/tools/rocknix-guest-substrate/package.mk"
  mkdir -p "$(dirname -- "${fixture_package_mk}")"
  cp "${package_mk}" "${fixture_package_mk}"
}

expect_verifier_failure() {
  local tmp_work=$1
  local expected=$2
  local out status
  set +e
  out=$(NIX_ON_ROCKS_WORKDIR="${tmp_work}" "${verifier}" 2>&1)
  status=$?
  set -e
  [ "${status}" -ne 0 ] || fail "verify-product-payload should fail for ${expected}"
  printf '%s\n' "${out}" | grep -q "${expected}" \
    || fail "verify-product-payload failure should mention ${expected}; output was: ${out}"
}

require_file "${product_lock}"
require_file "${guest_lock}"
[ -x "${renderer}" ] || fail "missing executable ${renderer}"
[ -x "${verifier}" ] || fail "missing executable ${verifier}"

# shellcheck source=../../product-payload.lock
# shellcheck disable=SC1090,SC1091
. "${product_lock}"
# shellcheck source=../../guest.lock
# shellcheck disable=SC1090,SC1091
. "${guest_lock}"

for field in \
  PRODUCT_AUTHORITY_REPO \
  PRODUCT_REV \
  PRODUCT_SOURCE_SHA256 \
  PRODUCT_SOURCE_SUBDIR \
  PRODUCT_BUILD_TARGET \
  PRODUCT_ROOTFS_SEED_REV \
  PRODUCT_ROOTFS_SEED_DEVICE \
  PRODUCT_ROOTFS_SEED_COMPATIBLE \
  PRODUCT_ROOTFS_SEED_ARCHIVE \
  PRODUCT_ROOTFS_SEED_SHA256 \
  PRODUCT_ROOTFS_SEED_URLS; do
  require_nonempty "${field}" "${!field:-}"
done

require_equal PRODUCT_ROOTFS_SEED_URL "${PRODUCT_ROOTFS_SEED_URL-__unset__}" ""
require_equal PRODUCT_ROOTFS_SEED_REV "${PRODUCT_ROOTFS_SEED_REV}" "${GUEST_REV}"
require_equal PRODUCT_ROOTFS_SEED_DEVICE "${PRODUCT_ROOTFS_SEED_DEVICE}" "${GUEST_DEVICE}"
require_equal PRODUCT_ROOTFS_SEED_COMPATIBLE "${PRODUCT_ROOTFS_SEED_COMPATIBLE}" "${GUEST_COMPATIBLE}"
require_equal PRODUCT_ROOTFS_SEED_ARCHIVE "${PRODUCT_ROOTFS_SEED_ARCHIVE}" "${GUEST_SEED_ARCHIVE}"
require_equal PRODUCT_ROOTFS_SEED_SHA256 "${PRODUCT_ROOTFS_SEED_SHA256}" "${GUEST_SEED_SHA256}"
require_equal PRODUCT_ROOTFS_SEED_URLS "${PRODUCT_ROOTFS_SEED_URLS}" "https://api.github.com/repos/simonwjackson/nix-on-rocks/releases/assets/426703720 https://api.github.com/repos/simonwjackson/nix-on-rocks/releases/assets/426704444"

rendered_env=$(mktemp)
trap 'rm -f "${rendered_env}"' EXIT
"${renderer}" > "${rendered_env}"
# shellcheck source=/dev/null
# shellcheck disable=SC1090
. "${rendered_env}"

require_equal PKG_NIX_GUEST_AUTHORITY_REPO "${PKG_NIX_GUEST_AUTHORITY_REPO:-}" "${PRODUCT_AUTHORITY_REPO}"
require_equal PKG_NIX_GUEST_AUTHORITY_NAME "${PKG_NIX_GUEST_AUTHORITY_NAME:-}" "${PRODUCT_AUTHORITY_REPO##*/}"
require_equal PKG_NIX_GUEST_REV "${PKG_NIX_GUEST_REV:-}" "${PRODUCT_REV}"
require_equal PKG_NIX_GUEST_SHA256 "${PKG_NIX_GUEST_SHA256:-}" "${PRODUCT_SOURCE_SHA256}"
require_equal PKG_NIX_GUEST_URL "${PKG_NIX_GUEST_URL:-}" "https://api.github.com/repos/${PRODUCT_AUTHORITY_REPO}/tarball/${PRODUCT_REV}"
require_equal PKG_NIX_GUEST_SOURCE_SUBDIR "${PKG_NIX_GUEST_SOURCE_SUBDIR:-}" "${PRODUCT_SOURCE_SUBDIR}"
require_equal PKG_NIX_GUEST_BUILD_TARGET "${PKG_NIX_GUEST_BUILD_TARGET:-}" "${PRODUCT_BUILD_TARGET}"
require_equal PKG_NIX_GUEST_ROOTFS_SEED_REV "${PKG_NIX_GUEST_ROOTFS_SEED_REV:-}" "${PRODUCT_ROOTFS_SEED_REV}"
require_equal PKG_NIX_GUEST_ROOTFS_SEED_DEVICE "${PKG_NIX_GUEST_ROOTFS_SEED_DEVICE:-}" "${PRODUCT_ROOTFS_SEED_DEVICE}"
require_equal PKG_NIX_GUEST_ROOTFS_SEED_COMPATIBLE "${PKG_NIX_GUEST_ROOTFS_SEED_COMPATIBLE:-}" "${PRODUCT_ROOTFS_SEED_COMPATIBLE}"
require_equal PKG_NIX_GUEST_ROOTFS_SEED_ARCHIVE "${PKG_NIX_GUEST_ROOTFS_SEED_ARCHIVE:-}" "${PRODUCT_ROOTFS_SEED_ARCHIVE}"
require_equal PKG_NIX_GUEST_ROOTFS_SEED_SHA256 "${PKG_NIX_GUEST_ROOTFS_SEED_SHA256:-}" "${PRODUCT_ROOTFS_SEED_SHA256}"
require_equal PKG_NIX_GUEST_ROOTFS_SEED_URL "${PKG_NIX_GUEST_ROOTFS_SEED_URL-__unset__}" ""
require_equal PKG_NIX_GUEST_ROOTFS_SEED_URLS "${PKG_NIX_GUEST_ROOTFS_SEED_URLS:-}" "${PRODUCT_ROOTFS_SEED_URLS}"

case "${PRODUCT_AUTHORITY_REPO}" in
  */*) : ;;
  *) fail "PRODUCT_AUTHORITY_REPO must be an authority/repository pair" ;;
esac

tmp_work=$(mktemp -d)
expect_verifier_failure "${tmp_work}" "run scripts/apply-rocknix-patches first"
rm -rf "${tmp_work}"

if [ -f "${package_mk}" ]; then
  (
    product_backup=$(mktemp)
    cp "${product_lock}" "${product_backup}"
    trap 'mv "${product_backup}" "${product_lock}"' EXIT
    sed -i 's/^PRODUCT_ROOTFS_SEED_SHA256=.*/PRODUCT_ROOTFS_SEED_SHA256="deadbeef"/' "${product_lock}"
    expect_verifier_failure "${work_dir}" "PRODUCT_ROOTFS_SEED_SHA256"
  )

  (
    product_backup=$(mktemp)
    cp "${product_lock}" "${product_backup}"
    trap 'mv "${product_backup}" "${product_lock}"' EXIT
    {
      printf '\nrequire_equal() { :; }\n'
      printf 'PRODUCT_REV="0000000000000000000000000000000000000000"\n'
    } >> "${product_lock}"
    expect_verifier_failure "${work_dir}" "PKG_NIX_GUEST_REV"
  )

  tmp_work=$(mktemp -d)
  copy_package_fixture "${tmp_work}"
  printf '\nPKG_NIX_GUEST_EXTRA_CONTRACT_FIELD="x"\n' >> "${tmp_work}/projects/ROCKNIX/packages/tools/rocknix-guest-substrate/package.mk"
  expect_verifier_failure "${tmp_work}" "unmodeled product payload package field: PKG_NIX_GUEST_EXTRA_CONTRACT_FIELD"
  rm -rf "${tmp_work}"

  tmp_work=$(mktemp -d)
  copy_package_fixture "${tmp_work}"
  sed -i '/^PKG_NIX_GUEST_ROOTFS_SEED_URL=/d' "${tmp_work}/projects/ROCKNIX/packages/tools/rocknix-guest-substrate/package.mk"
  expect_verifier_failure "${tmp_work}" "missing modeled product payload package field: PKG_NIX_GUEST_ROOTFS_SEED_URL"
  rm -rf "${tmp_work}"

  tmp_work=$(mktemp -d)
  copy_package_fixture "${tmp_work}"
  sed -i 's/^PKG_NIX_GUEST_SHA256=.*/PKG_NIX_GUEST_SHA256="deadbeef"/' "${tmp_work}/projects/ROCKNIX/packages/tools/rocknix-guest-substrate/package.mk"
  expect_verifier_failure "${tmp_work}" "PKG_NIX_GUEST_SHA256"
  rm -rf "${tmp_work}"

  tmp_work=$(mktemp -d)
  copy_package_fixture "${tmp_work}"
  sed -i '/^post_install() {/a PKG_NIX_GUEST_REV="runtime-mutation"' "${tmp_work}/projects/ROCKNIX/packages/tools/rocknix-guest-substrate/package.mk"
  expect_verifier_failure "${tmp_work}" "non-top-level PKG_NIX_GUEST_"
  rm -rf "${tmp_work}"
fi

printf 'product-payload-contract: ok\n'
