# Codex Safety Gate 3.0.0-alpha.8

This is a Windows-first pre-release for reviewing third-party Codex extensions
before they are allowed into a primary Codex home.

## What is included

- a self-contained Windows ZIP with the pinned PowerShell 7.6.4 runtime;
- a double-click `CSG.cmd` launcher and WinForms review flow;
- commit-pinned GitHub repository, release, `tree`, `blob`, and `raw` source freezing;
- GitHub API/codeload fallback when Git clone or fetch is unavailable;
- static capability findings, risk bands, profile detection, and permission cards;
- Windows Sandbox staging with deny-by-default mappings and networking;
- sealed-payload promotion, exact approval binding, conflict protection, and rollback;
- deterministic release manifests and SHA256 verification;
- tolerant local-source input with directory/file browsing, drag-and-drop, direct file selection, and ambiguity-safe path resolution.

## Supported path in this alpha

The generic automatic installation path supports isolated Codex Skills whose
promotable output is limited to `skills/<name>/**`. The supported operating-system
target is Windows 11 Pro, Enterprise, or Education with Windows Sandbox enabled.

## Blocked or unsupported

- Windows Home cannot run the required Windows Sandbox acceptance path.
- Proxy/model-gateway deployment is blocked from generic promotion.
- Agent routers may enter controlled observation, but final promotion remains
  blocked while runtime budget and child-process evidence are incomplete.
- MCP, shared configuration, global `AGENTS.md`, credentials, sessions, history,
  application state, services, scheduled tasks, Registry writes, and PATH changes
  require dedicated profiles or are rejected.
- CSG does not provide complete process, network, Registry, filesystem, or
  child-agent telemetry in this release.

## Residual risk

CSG is an evidence-producing admission gate, not a proof that arbitrary software
is safe. Static matching can miss behavior or report false positives. Windows
Sandbox reduces exposure but does not prove the absence of sandbox escapes. A
compromised dependency or installer can behave differently at runtime, especially
when networking is explicitly enabled.

Do not install when the result is `RED`, the profile is unknown, the permission
card does not match your intent, or Sandbox evidence is missing. Third-party
installers must never be rerun on the host during promotion.

## Verify the download

Download both the Windows ZIP and `SHA256SUMS.txt` from the same GitHub Release,
then verify before extraction:

```powershell
$expected = (Get-Content .\SHA256SUMS.txt -Raw).Split()[0]
$actual = (Get-FileHash .\codex-safety-gate-3.0.0-alpha.8-win-x64.zip -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actual -ne $expected) { throw 'CSG release SHA256 mismatch.' }
```

After extraction, run `CSG.cmd --smoke` once, then double-click `CSG.cmd` for the
normal GUI.
