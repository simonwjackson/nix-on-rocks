#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH="" cd -- "$(dirname -- "$0")/../.." && pwd)
product_lock="${repo_root}/product-payload.lock"
guest_lock="${repo_root}/guest.lock"

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

require_file "${product_lock}"
require_file "${guest_lock}"

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

case "${PRODUCT_AUTHORITY_REPO}" in
  */*) : ;;
  *) fail "PRODUCT_AUTHORITY_REPO must be an authority/repository pair" ;;
esac

printf 'product-payload-contract: ok\n'
