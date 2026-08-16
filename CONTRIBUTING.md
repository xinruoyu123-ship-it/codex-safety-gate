# Contributing to CSG

CSG changes must preserve evidence and fail closed. A feature that makes the UI
look complete while weakening a security invariant will not be accepted.

## Development setup

- Windows 10/11 with PowerShell 7 and Git.
- Windows Sandbox is optional for host-safe tests and required for integration tests.
- Do not use a real primary Codex home for development fixtures.
- Do not commit `runtime/pwsh/`, VM images, credentials, logs containing secrets,
  or generated CSG state.

Run before opening a pull request:

```powershell
pwsh -NoProfile -File .\tests\Run-StaticTests.ps1
pwsh -NoProfile -File .\tests\Run-GuiSmokeTests.ps1
pwsh -NoProfile -File .\tests\Run-LauncherTests.ps1
pwsh -NoProfile -File .\tests\Run-VmProvisioningTests.ps1
```

## Change requirements

Every security-relevant change should state:

1. the threat or failure it addresses;
2. the trust boundary and invariant affected;
3. the expected and actual behavior;
4. the smallest reproducible test;
5. whether source, package, or Sandbox evidence was collected;
6. remaining unknowns and deliberately unsupported behavior.

Tests must use isolated temporary `CSG_HOME` and fake Codex homes. Never map or
modify the contributor's real `.codex` during automated tests.

## Pull requests

- Keep changes scoped and reviewable.
- Add or update tests for behavioral changes.
- Update `CHANGELOG.md` for user-visible or security-relevant changes.
- Do not silently lower a risk band, enable networking, broaden mapped folders,
  bypass exact approval, or execute third-party installers on the host.
- Treat a skipped integration test as missing evidence, not a pass.

Security reports follow [SECURITY.md](SECURITY.md), not public issues.

