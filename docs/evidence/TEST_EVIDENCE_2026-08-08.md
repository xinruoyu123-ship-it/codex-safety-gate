# CSG Alpha validation evidence — 2026-08-08

## Current machine

| Item | Result | Evidence status |
|---|---|---|
| OS | Microsoft Windows 11 家庭版 中文版 | Verified locally |
| Built-in PowerShell | 5.1.26100.8655 | Verified locally |
| Global PowerShell 7 | Not found on PATH | Verified locally |
| Portable validation PowerShell | 7.6.4, official ZIP SHA256 matched | Verified locally |
| Git | 2.53.0.windows.3 | Verified locally |
| Codex | Desktop-bundled `codex.exe` found | Verified locally |
| Windows Sandbox | Unsupported on Windows Home | Verified edition plus Microsoft documentation |

Microsoft's current Windows Sandbox documentation lists Pro, Enterprise, Pro
Education/SE, and Education as supported editions and explicitly excludes Home:
https://learn.microsoft.com/windows/security/application-security/application-isolation/windows-sandbox/

## Source validation completed

- The handoff ZIP contained 21 expected files and no absolute or parent-traversal
  archive entries.
- UTF-8 parsing found two original syntax defects:
  - invalid mixed-direction `Sort-Object` arguments in `Inspect.psm1`;
  - malformed Markdown backtick interpolation in `Notebook.psm1`.
- Both defects are fixed.
- All current PowerShell source files parse with zero parser errors.
- All current JSON files parse successfully.
- The plain-skill recipe no longer passes wildcard text to `-LiteralPath`.
- `tests\Run-StaticTests.ps1` passed all 19 regression assertions under
  PowerShell 7.6.4.
- `csg.ps1 doctor` correctly reported this edition as unsupported for Sandbox
  and kept `windows_sandbox_usable=False`.
- The real `CSG.cmd` wrapper created a responsive window titled
  `Codex Safety Gate — Windows`; the launcher file remained present afterward.
- The GUI startup check used an isolated `CSG_HOME`; no real `.codex` path was
  supplied or changed.

## Pending evidence

- Full visual layout and button-state observation. Window creation is verified,
  but the current session did not expose a callable Windows UI-control runtime.
- `.wsb` launch, mappings, bootstrap, and result collection.
- Seal after a real Sandbox run.

## Blocker classification

The Sandbox failure on this machine is an environment limitation, not evidence
that the CSG Sandbox integration works or fails. CSG must remain fail-closed. A
Windows 11 Pro, Enterprise, or Education test machine is required for that part
of P0 acceptance.
