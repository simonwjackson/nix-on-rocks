# Upstream Intake

This directory is the additive memory for ROCKNIX upstream drift. It lets us run
periodic SM8550-focused reviews without starting a rebase branch each time.

## Run the intake

```bash
scripts/upstream-intake-report
```

The script reads `upstream.lock`, compares `UPSTREAM_SHA` to `origin/UPSTREAM_REF`
in the ROCKNIX checkout, writes a dated report under `docs/upstream-intake/runs/`,
and appends the run to `docs/upstream-intake/ledger.md`.

Useful variants:

```bash
# Avoid network fetch when origin/next is already current locally.
scripts/upstream-intake-report --no-fetch

# Compare a proposed target ref or SHA.
scripts/upstream-intake-report --to origin/next

# Use a non-default ROCKNIX checkout.
scripts/upstream-intake-report --work-dir ../distribution
```

When running from a git worktree, the script falls back to the main checkout's
`work/rocknix` if the worktree does not have its own ROCKNIX checkout.

## How to use the output

- Generated run reports are evidence snapshots. They are safe to overwrite by
  rerunning the same date/range.
- Promote durable decisions, conflicts, and validation gates into
  `ledger.md` so they survive across generated reports.
- Do not bump `upstream.lock` because a report exists. The report is a starting
  point for a deliberate rebase/import plan.

## What the report captures

- SM8550-specific hardware paths changed upstream.
- Shared Qualcomm / hardware paths changed upstream.
- Relevant upstream commits by message.
- Files changed upstream that overlap `patches/rocknix/*.patch`.
- A first-failing patch application forecast against the target upstream SHA.
- Candidate ledger rows for unresolved decisions.
