# CSG Windows GUI Alpha test plan

## Goal

Move the Alpha from “source generated” to “evidence-backed on a real Windows
machine” without installing unsealed content into the user's real `.codex`.

## Evidence levels

- **Verified:** exercised in the current run with recorded output.
- **Static evidence:** parsed or inspected, but the Windows integration was not run.
- **Blocked:** the required Windows feature or prerequisite is unavailable.

## Prerequisites

| Check | Pass condition | Failure behavior |
|---|---|---|
| Windows | Windows 11 Pro/Enterprise/Education x64 | Home can run static checks but Sandbox acceptance is blocked. |
| PowerShell | `pwsh` 7.0 or newer | Launcher explains the missing prerequisite. |
| Git | `git` is callable (preferred) | If unavailable or clone/fetch fails, GitHub API + commit-pinned codeload fallback is exercised; local fixtures remain testable. |
| Codex | Codex Desktop or CLI is present | Record as a product-environment blocker. |
| Windows Sandbox | Feature enabled and launcher callable | Do not fall back to host execution. |

## Automated, host-safe checks

Run `tests\Run-LauncherTests.ps1`, `tests\Run-StaticTests.ps1`, and
`tests\Run-GuiSmokeTests.ps1` with the bundled PowerShell 7. They use unique temporary
`CSG_HOME` and a fake main Codex directory. It must verify:

1. All `.ps1` and `.psm1` files parse.
2. All JSON files parse.
3. Fixture A is classified as a plain skill and receives an automatic narrow
   copy recipe.
4. Fixture B is classified as an agent router and rated YELLOW.
   Its budget declaration must remain within the default ceiling, but Promotion
   stays blocked until trusted runtime observation exists.
5. Fixture C is classified as a proxy gateway, rated ORANGE or higher, and is
   blocked from generic automatic installation.
6. Changing the original directory after Freeze does not change inspection.
7. Tampering with the frozen archive is rejected.
8. Notebook generation works against an isolated output path.
9. Promotion dry-run changes nothing.
10. Wrong approval is rejected.
11. Apply copies only sealed payload files and verifies hashes.
12. Rollback refuses to overwrite later user changes.
13. Rollback succeeds after the promoted content again matches its recorded hash.
14. Plain Skill and Agent Router states enable the single safe-test action.
15. Proxy/Gateway state keeps the generic action disabled.
16. Legacy Seal/approval step buttons are absent and technical details are hidden
    by default.
17. A missing Agent budget allows evidence collection but blocks Promotion.
18. An over-limit Agent budget blocks the automatic flow.
19. Direct `Invoke-SealedPromotion` cannot bypass an unverified runtime budget.
20. Observer plan contains `--json`, `--ephemeral`, ignored user config, and a
    read-only Codex sandbox policy; it must not contain `--yolo`.
21. Observer plan, benchmark prompt, and raw Codex JSONL are hash-bound.
22. Prompt or raw-event modification after receipt creation invalidates evidence.
23. A budget marked pass cannot bypass a failed Runtime Observer gate.
24. With PATH stripped of PowerShell 7, `CSG.cmd --smoke` uses the bundled 7.6.4
    runtime and loads the GUI successfully.
25. Launcher smoke leaves the default CSG artifact directory unchanged.
26. The bundled `pwsh.exe` SHA256 matches `runtime\manifest.json`.

## Windows Sandbox integration

Use a dedicated test account or disposable VM. Do not use the real `.codex` as
`MainCodexHome` during Alpha verification.

1. Run `csg.ps1 doctor`; capture PowerShell, Git, Sandbox, and Codex evidence.
2. Freeze Fixture A and inspect it.
3. Start Stage with networking disabled.
4. Inspect the generated `.wsb` before launch:
   - artifact and control mappings are read-only;
   - only the dedicated output mapping is writable;
   - clipboard, vGPU, audio, video, and printer redirection are disabled;
   - the real `.codex` is absent.
5. Launch Sandbox and confirm `sandbox-result.json` is produced.
6. Seal and verify payload hash plus observed capabilities.
7. Promote first without `-Apply` into a fake Codex home.
8. Promote with `-Apply`; compare every destination hash.
9. Modify one promoted file and confirm rollback reports a conflict.
10. Restore the promoted hash, run rollback, and confirm the fake home returns to
    its pre-promotion state.

## GUI verification

1. Double-click `CSG.cmd`; no persistent console window remains.
2. Window opens centered and remains usable at its minimum size.
3. Empty input produces a clear Chinese error.
4. Fixture A enables Sandbox testing after audit.
5. Fixture C displays the proxy/gateway warning and keeps the generic test/install
   path disabled.
6. Each state transition disables invalid next actions.
7. Closing or failing Sandbox does not enable approval.
8. The final approval dialog shows risk, payload hash, and capabilities.
9. No real `.codex` write occurs until the final explicit approval.
10. The notebook opens and is rebuildable from registry JSON.

## Runtime Observer integration

Run only in a disposable Windows Sandbox or VM with an explicitly provisioned,
revocable test credential. Never map the real `.codex`, `auth.json`, or the host
OS credential store.

1. Generate the observer plan and inspect its exact command and prompt hash.
2. Verify the isolated `CODEX_HOME` contains no host config or session history.
3. Run a baseline task and the same task with the addon using the same model,
   prompt, workspace, and quality gate.
4. Retain raw JSONL, stderr, exit code, elapsed time, and process telemetry.
5. Verify prompt, plan, and raw-event hashes before parsing.
6. Reject incomplete JSONL, failed quality gates, unknown child processes, budget
   overruns, credential leakage, or any mismatch between declared and observed
   behavior.

## Exit criteria for Alpha P0

- Automated host-safe tests pass under PowerShell 7.
- Sandbox Fixture A completes with networking disabled.
- Copy-only promotion and conflict-safe rollback pass against a fake Codex home.
- GUI audit-to-approval state transitions are observed on the real desktop.
- Every failure is categorized as verified defect, likely cause, pending evidence,
  or excluded cause.
