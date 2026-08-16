# CSG Windows Alpha 6 Test Evidence

Date: 2026-08-09

## Root cause fixed

Alpha 5 required `pwsh.exe` on PATH, so `CSG.cmd` exited with code 1 on this
machine. During diagnosis, a full C drive also produced one zero-byte test
`artifact.json`, correctly triggering the frozen-artifact hash gate.

## Verified

- Bundled PowerShell runtime: 7.6.4.
- Bundled `pwsh.exe` SHA256:
  `db6dd81183fe57d22e03b911ec9a30a2fd7c40542e97743615355a6fb44f458f`.
- Launcher with PATH stripped of PowerShell 7: PASS, bundled runtime selected.
- Launcher smoke default-state isolation: PASS, artifact count unchanged.
- Real non-smoke `CSG.cmd` launch: visible window found and responding.
- Core/static security regression: 32/32 PASS.
- GUI state regression: 6/6 PASS.
- Runtime Observer and dual Promotion gates remain passing.
- Real `.codex`: not read, written, or modified by this launcher repair.

## Recovery action

Four `plain-skill` smoke artifacts created during diagnosis were moved, not
deleted, to:

`D:\NVIDIA\codex-safety-gate-windows-alpha1-work\codex-safety-gate-windows\.devtools\quarantine-launcher-smoke-20260809-2320`

The user's default CSG artifact directory was empty after quarantine.
