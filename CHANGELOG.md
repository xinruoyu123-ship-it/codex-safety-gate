# Changelog

## 3.0.0-alpha.8 - Unreleased

- Establish a canonical Git repository for the future public release.
- Support GitHub repository, release, tree, blob, and raw source URLs.
- Resolve GitHub refs through the API and use a commit-pinned codeload fallback when Git is unavailable or clone/fetch fails.
- Scope `tree` links to the selected directory and retain parent directories for `blob` / `raw` file links.
- Record source subpath, link kind, and upstream codeload archive hash in provenance.
- Add regression coverage for URL parsing, slash refs, commit refs, scoped selection, and Git temporary cleanup.
- Ignore legal-notice URLs when deriving executable capabilities from source text.
- Fix VirtualBox discovery after unattended installation when the current process PATH is stale.
- Resume partial Windows ISO downloads instead of deleting them.
- Require a pinned ISO SHA256 unless an explicit development-only override is used.
- Replace the documented default VM password with a generated per-VM password.
- Add Apache-2.0 licensing and a security reporting policy.
- Reject identifier/path traversal and reparse points at freeze, stage, promotion, and rollback boundaries.
- Block credential and session paths from generic promotion.
- Restrict frozen-artifact extraction to CSG-owned temporary directories.
- Write JSON state atomically to avoid truncating security records on interrupted writes.
- Restore all attempted destination changes when promotion fails before registry completion.
- Fail closed when a GitHub tree/blob/raw link cannot be mapped to an unambiguous ref.
- Enforce configurable artifact file-count, size, path-length, duplicate-path, and archive-traversal limits.
- Limit generic Promotion to isolated `skills/<name>/**` payloads; shared Codex state fails closed.
- Refuse automatic recovery when a target changed concurrently after Promotion touched it.
- Pin the official PowerShell runtime archive, full runtime tree, file count, and size.
- Add deterministic release assembly, per-file manifests, archive verification, and Windows CI release builds.
- Add maintainer publishing instructions and release notes that state unsupported profiles and residual risk.

## 3.0.0-alpha.6 - 2026-08-09

- Bundled the verified portable PowerShell 7.6.4 runtime so users no longer need
  `pwsh.exe` installed or present in `PATH` before double-clicking `CSG.cmd`.
- Updated the launcher to prefer the bundled runtime, then fall back to PATH and
  the standard Program Files location.
- Replaced inherited minimized startup with a hidden console and normally visible
  WinForms window.
- Added `CSG-Launch.ps1` to capture startup failures in
  `%LOCALAPPDATA%\CodexSafetyGate\logs\launcher-error.log` and display a readable
  dialog instead of silently exiting.
- Isolated launcher smoke tests in a unique temporary `CSG_HOME`; tests no longer
  create artifacts in the user's default CSG state.
- Added runtime executable hash verification and an end-to-end batch-launcher
  smoke test with PATH intentionally stripped of PowerShell 7.
- Quarantined four test artifacts accidentally written to the default state while
  diagnosing a full C drive; no real `.codex` content was touched.

## 3.0.0-alpha.5 - 2026-08-09

- Added a CSG-controlled Runtime Observer plan using the stable non-interactive
  `codex exec --json --ephemeral` interface with read-only Codex sandbox policy
  and ignored user configuration.
- Bound the observer plan, benchmark prompt, and raw newline-delimited Codex JSON
  events to SHA256 evidence.
- Added independent parsing of reported input, cached input, output, reasoning,
  and total token snapshots plus completed-event counts.
- Added a Runtime Observer receipt and schema. Addon-produced summaries are not
  trusted as evidence.
- Added explicit partial-evidence status: exact cross-Agent token totals, process
  counts, and isolated credential provisioning remain unverified and therefore
  cannot unlock Promotion.
- Added a second Promotion gate for Runtime Observer evidence, independent of the
  budget declaration gate, plus regressions for prompt tampering, JSONL tampering,
  and direct CLI bypass attempts.

## 3.0.0-alpha.4 - 2026-08-09

- Added a machine-readable `csg-budget.json` contract for Agent Router / Token
  tools, with limits for child agents, concurrency, delegation depth, Sol calls,
  and retries.
- Added required benchmark fields for input, output, and reasoning tokens; agent,
  call, and retry counts; success; and latency. Lower usage is not accepted as an
  improvement unless the quality gate still passes.
- Added fail-closed policy outcomes for missing, malformed, and over-limit budget
  declarations.
- Kept Sandbox inspection available for a valid declaration, but blocked final
  installation until a trusted CSG runtime observer exists. An author-provided
  declaration is not treated as proof of enforcement.
- Enforced the budget gate in both the GUI and `Invoke-SealedPromotion`, preventing
  the advanced CLI path from bypassing it.
- Added static and GUI regressions for compliant declarations, missing budgets,
  over-limit budgets, and CLI bypass attempts.

## 3.0.0-alpha.3 - 2026-08-09

- Replaced the four internal workflow buttons with `检查这个` and
  `安全测试并安装`; the same action continues after Sandbox completes.
- Added a human-readable permission card for Codex writes, child processes,
  networking, persistence, elevation, credential access, prompt artifacts, and
  Agent/Token cost risk.
- Hid Artifact IDs, Stage IDs, recipes, and raw capabilities behind technical
  details or the final verification dialog.
- Kept Proxy / Model Gateway addons blocked from the generic installation path.
- Added deterministic GUI smoke tests for plain Skill, Agent Router, and Fake
  Proxy states.

## 3.0.0-alpha.2 - 2026-08-08

- Fixed two PowerShell parser failures in inspection reporting and notebook output.
- Fixed the plain-skill copy recipe so wildcard text is not passed to
  `-LiteralPath`, hidden files are included, and the original skill directory
  name is retained.
- Added three deterministic security fixtures: plain skill, agent router, and
  fake proxy gateway.
- Added host-safe automated tests for parsing, classification, freezing, archive
  tamper rejection, notebook generation, copy-only promotion, approval binding,
  and conflict-safe rollback.
- Added the Windows real-machine test plan and evidence criteria.
- Made Sandbox diagnostics edition-aware so Windows Home is reported as
  unsupported instead of merely "not enabled"; host execution remains blocked.
- Blocked promotion replay from overwriting the original rollback baseline and
  disabled the GUI approval button after a successful install.
- Minimized the PowerShell 7 console for GUI startup without using a hidden
  `ExecutionPolicy Bypass` launcher pattern.
- Refused whole `.codex`, `.codex\sessions`, and recursive parent-directory
  freezes to prevent huge or self-recursing artifacts.
- Added structural capability findings for `SKILL.md` and `AGENTS.md` so risk
  classification does not depend on those filenames being repeated in prose.
- Fixed rollback registry completion under strict mode by explicitly adding the
  `rolled_back_at` property to the deserialized record.

## 3.0.0-alpha.1 - 2026-08-08

- Initial Windows-only, GUI-first Alpha handoff build.
