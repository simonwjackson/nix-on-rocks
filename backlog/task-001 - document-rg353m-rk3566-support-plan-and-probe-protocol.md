---
id: task-001
title: Document RG353M RK3566 support plan and probe protocol
status: In Progress
priority: high
labels:
  - rg353m
  - rk3566
  - before-device
  - planning
created: 2026-06-04
source: user
---

# Document RG353M RK3566 support plan and probe protocol

## Why it matters

Capturing the research and first-boot probe protocol before the device arrives keeps later LLM runs grounded in durable repo context instead of this chat transcript.

## Acceptance Criteria

- [x] A repo-local plan or brainstorm document summarizes RG353M/RK3566 hardware facts, upstream ROCKNIX prior art, risks, and non-goals.
- [x] The document groups implementation work into before-device and after-device phases.
- [x] The arrival probe checklist includes exact commands for model, compatible strings, audio, DRM, input, WiFi/Bluetooth, panel, and relevant dmesg capture.
- [x] The document explicitly warns not to zero or overwrite eMMC without an explicit later decision.

## Related

- `docs/plans/`
- `docs/brainstorms/`
- `docs/brainstorms/evidence/`
- `work/rocknix/projects/ROCKNIX/devices/RK3566/`

## Notes

Logical work group: documentation and probe protocol. This should be the first LLM-run before hardware arrives.

Completed in `docs/plans/2026-06-04-001-feat-rg353m-rk3566-support-plan.md`. Keep this item until the plan/backlog changes land in git, then remove it per backlog lifecycle.
