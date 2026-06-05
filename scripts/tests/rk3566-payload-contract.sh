#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH="" cd -- "$(dirname -- "$0")/../.." && pwd)
verifier="${repo_root}/scripts/verify-rk3566-payloads"

require_tool() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "rk3566-payload-contract: SKIP missing $1" >&2
    exit 0
  }
}

for tool in sfdisk mkfs.vfat mke2fs mmd mcopy gzip sha256sum; do
  require_tool "${tool}"
done

make_payload() {
  local target_dir=$1
  local part1_start=${2:-32768}
  local fat_label=${3:-ROCKNIX}
  local storage_label=${4:-STORAGE}
  local manifest_state=${5:-valid}
  local extlinux_state=${6:-valid}
  local include_dtb=${7:-yes}
  local disk_label=${8:-dos}
  local sha_state=${9:-valid}

  local image="${target_dir}/ROCKNIX-RK3566-test.img"
  local fat="${target_dir}/part1.fat"
  local storage="${target_dir}/part2.ext4"
  local part_size=32768
  local part2_start=$((part1_start + part_size))

  truncate -s 96M "${image}"
  if [ "${disk_label}" = "gpt" ]; then
    printf 'label: gpt\n%s,%s\n%s,%s\n' \
      "${part1_start}" "${part_size}" "${part2_start}" "${part_size}" | sfdisk "${image}" >/dev/null
  else
    printf 'label: dos\n%s,%s,c,*\n%s,%s,83\n' \
      "${part1_start}" "${part_size}" "${part2_start}" "${part_size}" | sfdisk "${image}" >/dev/null
  fi

  truncate -s $((part_size * 512)) "${fat}"
  mkfs.vfat -F 32 -S 512 -n "${fat_label}" "${fat}" >/dev/null 2>&1
  printf 'kernel\n' > "${target_dir}/KERNEL"
  printf 'system\n' > "${target_dir}/SYSTEM"
  printf 'dtb\n' > "${target_dir}/rk3566-test.dtb"
  case "${extlinux_state}" in
    valid)
      cat > "${target_dir}/extlinux.conf" <<'EOF'
LABEL ROCKNIX
  LINUX /KERNEL
  FDTDIR /device_trees
  APPEND boot=LABEL=ROCKNIX disk=LABEL=STORAGE quiet
EOF
      ;;
    no-fdt)
      cat > "${target_dir}/extlinux.conf" <<'EOF'
LABEL ROCKNIX
  LINUX /KERNEL
  APPEND boot=LABEL=ROCKNIX disk=LABEL=STORAGE quiet
EOF
      ;;
    wrong-boot)
      cat > "${target_dir}/extlinux.conf" <<'EOF'
LABEL ROCKNIX
  LINUX /KERNEL
  FDTDIR /device_trees
  APPEND boot=LABEL=WRONG disk=LABEL=STORAGE quiet
EOF
      ;;
    wrong-disk)
      cat > "${target_dir}/extlinux.conf" <<'EOF'
LABEL ROCKNIX
  LINUX /KERNEL
  FDTDIR /device_trees
  APPEND boot=LABEL=ROCKNIX disk=LABEL=WRONG quiet
EOF
      ;;
    missing)
      rm -f "${target_dir}/extlinux.conf"
      ;;
  esac
  mmd -i "${fat}" ::/extlinux ::/device_trees
  mcopy -i "${fat}" "${target_dir}/KERNEL" ::/KERNEL
  mcopy -i "${fat}" "${target_dir}/SYSTEM" ::/SYSTEM
  if [ -f "${target_dir}/extlinux.conf" ]; then
    mcopy -i "${fat}" "${target_dir}/extlinux.conf" ::/extlinux/extlinux.conf
  fi
  if [ "${include_dtb}" = "yes" ]; then
    mcopy -i "${fat}" "${target_dir}/rk3566-test.dtb" ::/device_trees/rk3566-test.dtb
  fi

  truncate -s $((part_size * 512)) "${storage}"
  mke2fs -F -q -t ext4 -L "${storage_label}" "${storage}"

  dd if="${fat}" of="${image}" bs=512 seek="${part1_start}" conv=notrunc status=none
  dd if="${storage}" of="${image}" bs=512 seek="${part2_start}" conv=notrunc status=none
  gzip -c "${image}" > "${target_dir}/ROCKNIX-RK3566-test.img.gz"
  if [ "${sha_state}" = "valid" ]; then
    (cd "${target_dir}" && sha256sum ROCKNIX-RK3566-test.img.gz > ROCKNIX-RK3566-test.img.gz.sha256)
  else
    printf '%064d  ROCKNIX-RK3566-test.img.gz\n' 0 > "${target_dir}/ROCKNIX-RK3566-test.img.gz.sha256"
  fi

  case "${manifest_state}" in
    valid)
      printf -- '- **Hardware boot:** `unverified`\n' > "${target_dir}/manifest.md"
      ;;
    invalid)
      printf -- '- **Hardware boot:** `accepted`\n' > "${target_dir}/manifest.md"
      ;;
    absent)
      rm -f "${target_dir}/manifest.md"
      ;;
  esac
}

expect_failure() {
  local expected=$1
  shift
  local output
  set +e
  output=$("$@" 2>&1)
  local status=$?
  set -e
  [ "${status}" -ne 0 ] || {
    echo "expected verifier failure containing '${expected}'" >&2
    exit 1
  }
  grep -Fq "${expected}" <<<"${output}" || {
    echo "failure output did not contain '${expected}':" >&2
    printf '%s\n' "${output}" >&2
    exit 1
  }
}

tmp_root=$(mktemp -d)
trap 'rm -rf "${tmp_root}"' EXIT

empty_dir=$(mktemp -d "${tmp_root}/empty.XXXXXX")
expect_failure 'expected exactly one RK3566 SD image' "${verifier}" "${empty_dir}"

valid_dir=$(mktemp -d "${tmp_root}/valid.XXXXXX")
make_payload "${valid_dir}"
NIX_ON_ROCKS_BUILD_MANIFEST="${valid_dir}/manifest.md" "${verifier}" "${valid_dir}" >/dev/null

multi_image_dir=$(mktemp -d "${tmp_root}/multi-image.XXXXXX")
make_payload "${multi_image_dir}"
cp "${multi_image_dir}/ROCKNIX-RK3566-test.img.gz" "${multi_image_dir}/ROCKNIX-RK3566-test-Generic.img.gz"
cp "${multi_image_dir}/ROCKNIX-RK3566-test.img.gz" "${multi_image_dir}/ROCKNIX-RK3566-test-Specific.img.gz"
(
  cd "${multi_image_dir}"
  sha256sum ROCKNIX-RK3566-test-Generic.img.gz > ROCKNIX-RK3566-test-Generic.img.gz.sha256
  sha256sum ROCKNIX-RK3566-test-Specific.img.gz > ROCKNIX-RK3566-test-Specific.img.gz.sha256
)
SUBDEVICE=Generic NIX_ON_ROCKS_BUILD_MANIFEST="${multi_image_dir}/manifest.md" "${verifier}" "${multi_image_dir}" >/dev/null

overlap_dir=$(mktemp -d "${tmp_root}/overlap.XXXXXX")
make_payload "${overlap_dir}" 128
expect_failure 'U-Boot sector window' "${verifier}" "${overlap_dir}"

fat_dir=$(mktemp -d "${tmp_root}/fat.XXXXXX")
make_payload "${fat_dir}" 32768 WRONG
expect_failure 'FAT label must be ROCKNIX' "${verifier}" "${fat_dir}"

storage_dir=$(mktemp -d "${tmp_root}/storage.XXXXXX")
make_payload "${storage_dir}" 32768 ROCKNIX WRONG
expect_failure 'STORAGE partition label mismatch' "${verifier}" "${storage_dir}"

manifest_dir=$(mktemp -d "${tmp_root}/manifest.XXXXXX")
make_payload "${manifest_dir}" 32768 ROCKNIX STORAGE invalid
expect_failure 'manifest must state hardware boot is unverified' \
  env NIX_ON_ROCKS_BUILD_MANIFEST="${manifest_dir}/manifest.md" "${verifier}" "${manifest_dir}"

missing_extlinux_dir=$(mktemp -d "${tmp_root}/missing-extlinux.XXXXXX")
make_payload "${missing_extlinux_dir}" 32768 ROCKNIX STORAGE valid missing
expect_failure 'missing extlinux/extlinux.conf' "${verifier}" "${missing_extlinux_dir}"

no_fdt_dir=$(mktemp -d "${tmp_root}/no-fdt.XXXXXX")
make_payload "${no_fdt_dir}" 32768 ROCKNIX STORAGE valid no-fdt
expect_failure 'must reference a DTB' "${verifier}" "${no_fdt_dir}"

wrong_boot_dir=$(mktemp -d "${tmp_root}/wrong-boot.XXXXXX")
make_payload "${wrong_boot_dir}" 32768 ROCKNIX STORAGE valid wrong-boot
expect_failure 'must boot by ROCKNIX FAT label' "${verifier}" "${wrong_boot_dir}"

wrong_disk_dir=$(mktemp -d "${tmp_root}/wrong-disk.XXXXXX")
make_payload "${wrong_disk_dir}" 32768 ROCKNIX STORAGE valid wrong-disk
expect_failure 'must mount storage by STORAGE label' "${verifier}" "${wrong_disk_dir}"

missing_dtb_dir=$(mktemp -d "${tmp_root}/missing-dtb.XXXXXX")
make_payload "${missing_dtb_dir}" 32768 ROCKNIX STORAGE valid valid no
expect_failure 'device_trees/*.dtb' "${verifier}" "${missing_dtb_dir}"

gpt_dir=$(mktemp -d "${tmp_root}/gpt.XXXXXX")
make_payload "${gpt_dir}" 32768 ROCKNIX STORAGE valid valid yes gpt
expect_failure 'MBR/dos partition table' "${verifier}" "${gpt_dir}"

sha_dir=$(mktemp -d "${tmp_root}/sha.XXXXXX")
make_payload "${sha_dir}" 32768 ROCKNIX STORAGE valid valid yes dos invalid
expect_failure 'FAILED' "${verifier}" "${sha_dir}"

printf 'rk3566-payload-contract: ok\n'
