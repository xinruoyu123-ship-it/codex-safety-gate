# CSG threat model

## Security objective

Let a Windows user inspect and test a third-party Codex extension while keeping
untrusted installer execution, credentials, and unsealed output away from the
primary Codex home. Installation is allowed only by copying an explicitly
approved, content-addressed payload.

CSG reduces risk; it does not prove that arbitrary software is safe.

## Protected assets

- the user's primary Codex home, configuration, sessions, and credentials;
- browser, Git, SSH, cloud, and operating-system credentials;
- host files outside the explicit promotion destination;
- the integrity of frozen source, Sandbox output, approvals, backups, and logs;
- the user's ability to understand what will change before promotion.

## Adversaries

- a malicious extension author;
- a compromised repository, release asset, dependency, or installer endpoint;
- a benign project with unsafe installation behavior;
- local tampering between freeze, inspection, staging, seal, and promotion;
- misleading metadata or declared Agent/Token budgets;
- an operator who enables a broader permission without understanding it.

## Trust boundaries

Trusted for the current alpha:

- reviewed CSG source and exact release package;
- Windows and Windows Sandbox security boundaries;
- the selected PowerShell, Git, and VirtualBox/VM toolchains;
- explicit human approval of the displayed stage and payload hash.

Untrusted until evidence proves otherwise:

- GitHub/local extension source;
- install scripts, binaries, dependencies, generated output, and runtime behavior;
- extension-provided capability or budget declarations;
- mutable URLs and unpinned downloads.

## Required invariants

1. Third-party installer code runs only inside Windows Sandbox.
2. The primary Codex home, credentials, and arbitrary home folders are not mapped.
3. Source and CSG control mappings are read-only.
4. Only a dedicated stage-output directory is writable from the Sandbox.
5. Networking is disabled unless the user explicitly expands that permission.
6. Freeze, stage, seal, and promotion recheck content hashes at their boundaries.
7. Promotion never replays the third-party installer.
8. Promotion copies only the sealed payload and verifies destination hashes.
9. Approval is exact, case-sensitive, and bound to the stage and payload hash.
10. Rollback refuses to overwrite files changed after promotion.
11. Missing runtime-budget or observer evidence blocks affected profiles.
12. Unsupported capabilities fail closed.
13. Generic promotion accepts only isolated `skills/<name>/**` payloads; shared
    configuration, credentials, sessions, history, and application state fail closed.
14. Reparse points and paths outside CSG-controlled roots are rejected.
15. A failed promotion restores attempted destination files only when they still
    match the promoted hash; concurrent changes stop recovery and preserve backups.
16. Artifact and archive resource limits are checked before hashing or extraction.
17. GitHub source links resolve to a full commit before freezing; `tree` links are
    scoped to the selected directory and `blob` / `raw` links retain only the
    containing directory. GitHub API/codeload fallback is commit-pinned and its
    upstream archive hash is recorded.

## Current detection coverage

- PowerShell and JSON syntax;
- source/archive/payload hash tampering;
- selected static capability indicators;
- legal-notice files are excluded from executable capability matching so license
  URLs do not become false network permissions;
- profile-specific gates for Skills, agent routers, and proxies;
- generated Codex-home output paths;
- promotion replay, approval mismatch, and rollback conflicts;
- partial Codex JSONL and budget-contract evidence.

## Known gaps

- no complete process, network, Registry, filesystem, or child-agent telemetry;
- no proof against a Windows Sandbox or hypervisor escape;
- no semantic proof that an `AGENTS.md` or `SKILL.md` instruction is benign;
- no general dependency or build-provenance verification;
- no complete Sigstore/SLSA/release-signature verification;
- no trusted initial SHA256 for the Windows evaluation ISO in the repository yet;
- proxy/gateway deployment is not supported by the generic promotion path;
- real Sandbox acceptance is still pending on a supported Windows guest.

Any gap that affects a requested profile is a blocker or explicit permission
expansion. It must never be converted into a silent host fallback.

## Evidence required for a public release

- clean source-checkout CI on Windows;
- release archive inventory and SHA256;
- bundled runtime provenance and executable hash verification;
- real Windows Sandbox logs for freeze, stage, seal, promote, conflict, rollback;
- proof that the real `.codex` and credentials were not mapped or modified;
- documented known gaps and support matrix matching actual behavior.
