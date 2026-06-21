#!/usr/bin/env bash
set -euo pipefail

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)"
script="${repo_root}/scripts/upstream-intake-report"
tmp=$(mktemp -d)
trap 'rm -rf "${tmp}"' EXIT

fixture="${tmp}/rocknix-fixture"
mkdir -p \
  "${fixture}/config" \
  "${fixture}/projects/ROCKNIX/devices/SM8550/linux/dts/qcom"
git -C "${tmp}" init -q rocknix-fixture
git -C "${fixture}" config user.email test@example.invalid
git -C "${fixture}" config user.name 'Upstream Intake Test'
printf 'base\n' > "${fixture}/projects/ROCKNIX/devices/SM8550/linux/dts/qcom/qcs8550-ayn-thor.dts"
git -C "${fixture}" add .
git -C "${fixture}" commit -q -m 'base fixture'
base_sha=$(git -C "${fixture}" rev-parse HEAD)
printf 'base\nchanged\n' > "${fixture}/projects/ROCKNIX/devices/SM8550/linux/dts/qcom/qcs8550-ayn-thor.dts"
printf 'armv9\n' > "${fixture}/config/arch.aarch64"
git -C "${fixture}" add .
git -C "${fixture}" commit -q -m 'SM8550: fixture touchscreen change'
target_sha=$(git -C "${fixture}" rev-parse HEAD)

output_dir="${tmp}/reports"
ledger="${tmp}/ledger.md"
cat > "${ledger}" <<'LEDGER'
# Upstream Intake Ledger

## Run index

## Open decisions

Human-maintained decisions stay below the run index.
LEDGER

"${script}" \
  --work-dir "${fixture}" \
  --since "${base_sha}" \
  --to "${target_sha}" \
  --date 2026-05-29 \
  --output-dir "${output_dir}" \
  --ledger "${ledger}" \
  --no-fetch \
  --skip-apply-check >"${tmp}/upstream-intake-test.out"

report=$(find "${output_dir}" -type f -name '*-sm8550.md' | head -1)
[ -f "${report}" ] || { echo 'missing generated report' >&2; exit 1; }

grep -q 'SM8550 upstream intake' "${report}" || { echo 'report missing title' >&2; exit 1; }
grep -q 'projects/ROCKNIX/devices/SM8550/linux/dts/qcom/qcs8550-ayn-thor.dts' "${report}" \
  || { echo 'report missing SM8550 changed path' >&2; exit 1; }
grep -q 'config/arch.aarch64' "${report}" \
  || { echo 'report missing common hardware changed path' >&2; exit 1; }
grep -q 'Skipped by --skip-apply-check' "${report}" \
  || { echo 'report missing skipped apply forecast' >&2; exit 1; }
grep -q 'SM8550: fixture touchscreen change' "${report}" \
  || { echo 'report missing relevant commit' >&2; exit 1; }
grep -q 'upstream commits reviewed' "${ledger}" \
  || { echo 'ledger missing run index entry' >&2; exit 1; }
run_idx=$(grep -n 'upstream commits reviewed' "${ledger}" | cut -d: -f1)
decision_idx=$(grep -n '## Open decisions' "${ledger}" | cut -d: -f1)
[ "${run_idx}" -lt "${decision_idx}" ] \
  || { echo 'ledger run entry was not inserted under Run index' >&2; exit 1; }

"${script}" \
  --work-dir "${fixture}" \
  --since "${base_sha}" \
  --to "${target_sha}" \
  --date 2026-05-29 \
  --output-dir "${output_dir}" \
  --ledger "${ledger}" \
  --no-fetch \
  --skip-apply-check >"${tmp}/upstream-intake-test-rerun.out"

entry_count=$(grep -c 'upstream commits reviewed' "${ledger}")
[ "${entry_count}" -eq 1 ] || { echo "ledger duplicated run index entry (${entry_count})" >&2; exit 1; }

cross_tree_ledger="${tmp}/ledger-dir/ledger.md"
cross_tree_output="${tmp}/external/reports"
mkdir -p "$(dirname -- "${cross_tree_ledger}")"
"${script}" \
  --work-dir "${fixture}" \
  --since "${base_sha}" \
  --to "${target_sha}" \
  --date 2026-05-30 \
  --output-dir "${cross_tree_output}" \
  --ledger "${cross_tree_ledger}" \
  --no-fetch \
  --skip-apply-check >"${tmp}/upstream-intake-cross-tree.out"
grep -q '(../external/reports/' "${cross_tree_ledger}" \
  || { echo 'ledger did not use a relative link for cross-tree output' >&2; exit 1; }

echo 'upstream-intake-report: ok'
