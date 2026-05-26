## Institutional Learnings Search Results

### Search Context
- **Feature/Task**: Plan a refactor that moves Nix-owned test/check invariants out of shell/text greps into `nix/tests/*.nix` flake checks, splits shell smoke from package/output/docs checks, and updates CI to use canonical flake checks.
- **Keywords Used**: `nix checks`, `flake check`, `nix/tests`, `static-checks`, `CI`, `image-only`, `artifact verification`, `patch application`, `SM8550`, `payloads`, `contract boundary`, `shell smoke`, `grep`.
- **Files Scanned**: 28 `docs/solutions` files by grep pre-filter, plus targeted related docs in `docs/ci`, `docs/contracts`, `docs/thinking`, and `docs/plans`.
- **Relevant Matches**: 8 files.

### Relevant Learnings

#### 1. Fast-iter CI is for packaging/output changes after cheap checks pass
- **File**: `docs/solutions/developer-experience/fast-iter-and-local-rocknix-build-2026-05-08.md`
- **Supporting File**: `docs/ci/fast-builds.md`
- **Module**: ROCKNIX build system / CI
- **Problem Type**: developer_experience (inferred from category/frontmatter shape)
- **Relevance**: The refactor should make cheap flake checks the canonical pre-build gate, then reserve `build-image-only.yml` for packaging/output validation rather than broad static grep coverage.
- **Key Insight**: Do not burn 5-hour SM8550 builds to validate Nix/source contracts. Existing fast lanes already separate reusable base artifacts from image/output verification; mirror that split in the test boundary.

#### 2. Wrong-file patch failures should be caught before CI/image builds
- **File**: `docs/solutions/developer-experience/nix-layer-9-nspawn-guest-proof-rocknix-2026-05-06.md`
- **Module**: ROCKNIX nix-integration
- **Problem Type**: developer_experience
- **Relevance**: Patch/path invariants are high-value preflight checks, but not all belong in evaluated Nix module tests.
- **Key Insight**: A previous patch edited `packages/sysutils/systemd/package.mk` instead of the active `projects/ROCKNIX/packages/sysutils/systemd/package.mk`, costing a full CI/device loop. Keep path/patch-application guardrails early and explicit. Move only Nix-owned invariants into flake checks; keep patch queue/application checks in shell preflight where they validate generated `work/rocknix` state.
- **Severity**: medium

#### 3. Host/guest/product boundaries are contract tests, not incidental greps
- **File**: `docs/contracts/layer14-main-space-contract.md`
- **Supporting Files**: `docs/thinking/base-safety-review.md`, `docs/thinking/rocknix-nix-guest-scout.md`
- **Module**: Layer 14 main-space substrate
- **Problem Type**: architecture_pattern (inferred)
- **Relevance**: The proposed `nix/tests/*.nix` checks should encode evaluated contract facts: no broad host binds, SM8550-only substrate exposure, guest owns product UX, packages stay product-agnostic, and downstream products own Korri composition.
- **Key Insight**: Prefer evaluated Nix checks for NixOS options, module imports, package outputs, passthru/manifest data, service dependency graphs, and package-vs-session boundaries. Keep shell smoke for runtime observations and generated tree/output inspection.

#### 4. Artifact verification is a post-build/output gate, not a flake check
- **File**: `docs/solutions/runtime-errors/sm8550-mkimage-vfat-logical-sector-size-too-small-2026-05-25.md`
- **Supporting File**: `scripts/verify-sm8550-payloads`
- **Module**: sm8550-image-build
- **Problem Type**: runtime_error
- **Relevance**: The plan should not try to fold image/tar/FAT geometry checks into source-only flake checks.
- **Key Insight**: FAT logical sector size, `target/SYSTEM`/`target/KERNEL`, seed archive presence, checksums, gzip integrity, and manifest seed records depend on produced artifacts. Keep them as package/output checks after image creation and ensure CI still runs them in `build-sm8550`, `continue-sm8550-from-toolchain`, and `build-image-only`.
- **Severity**: high

#### 5. Static checks should guard both the intended pattern and known bad anti-patterns
- **File**: `docs/solutions/runtime-errors/guest-main-space-pipewire-runtime-dir-socket-vanish-rocknix-2026-05-24.md`
- **Module**: Layer 14 main-space guest substrate
- **Problem Type**: runtime_error
- **Relevance**: When moving checks from greps to Nix, preserve negative assertions, not just happy-path structure.
- **Key Insight**: The PipeWire fix added guards for anchor unit presence, consumer ordering, and rejected dead-end fixes (`ExecStartPre=install -d /run/user/0`, hardcoded runtime env, `KillUserProcesses`, `RemoveIPC`). In Nix checks, model these as evaluated service graph/env assertions where possible; leave text greps only for non-Nix shell/docs/patch surfaces.
- **Severity**: high

#### 6. Deployment safety depends on artifact and device-side smoke remaining separate
- **File**: `docs/solutions/developer-experience/custom-fork-update-sm8550-rocknix-2026-05-04.md`
- **Module**: ROCKNIX SM8550 custom-fork deployment
- **Problem Type**: developer_experience
- **Relevance**: CI check refactors must not blur pre-build source checks with install/deploy safety checks.
- **Key Insight**: Host-side SHA256, device-side SHA256, ABL skip precheck, `/storage/.update` hygiene, and post-update service validation are operational smoke/deployment gates. Keep them outside flake checks, but make sure package/output docs point operators to the canonical artifact verifier.
- **Severity**: medium

### Recommendations

- Create `nix/tests/*.nix` modules for evaluated Nix-owned invariants and expose them through `checks.<system>.*`; make `nix flake check --no-write-lock-file --print-build-logs` the canonical source-contract CI gate.
- Split checks by boundary:
  - **Flake/Nix checks**: NixOS option values, service ordering/env, package outputs, manifests/passthru, package-vs-session/product boundaries.
  - **Shell static/preflight**: patch application, generated `work/rocknix` presence, shell syntax, lock/package alignment, text docs that are not Nix data.
  - **Package/output checks**: built derivation contents and package evidence.
  - **Artifact checks**: SM8550 update tar/image payloads, seed/checksum/manifest/FAT geometry.
  - **Runtime smoke/soak**: on-device SSH, guest status, services, recovery toggles, and long-running stability.
- Preserve existing early guard ordering: apply patches → verify SM8550 contract/locks → canonical flake checks/preflight → build lane → `verify-sm8550-payloads` → device smoke/soak.
- Convert negative grep assertions only when Nix can evaluate the same fact directly; otherwise keep a small shell check with a clear failure message and a comment pointing to the learning file.
