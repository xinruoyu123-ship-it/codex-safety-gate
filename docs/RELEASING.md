# Releasing CSG

CSG releases are built from a clean Git commit on Windows. The source repository
does not contain the portable PowerShell runtime.

## 1. Import the pinned runtime

```powershell
pwsh -NoProfile -File .\tools\release\Get-CsgRuntime.ps1
```

The importer downloads the exact archive recorded in `runtime/manifest.json`,
checks its official SHA256 before extraction, rejects unsafe ZIP paths, and
verifies the expanded file count, size, executable hash, and complete tree hash.

The verified archive is retained under `.devtools/runtime/` for the build step.

## 2. Build and verify

```powershell
$runtimeArchive = '.\.devtools\runtime\PowerShell-7.6.4-win-x64.zip'
pwsh -NoProfile -File .\tools\release\Build-CsgRelease.ps1 `
  -RuntimeArchivePath $runtimeArchive
```

The build refuses a dirty worktree. It copies only Git-managed source files,
adds the verified portable runtime, runs all host-safe tests, writes
`RELEASE-MANIFEST.json`, creates a deterministic ZIP, verifies every ZIP entry,
and writes:

- `dist/codex-safety-gate-<version>-win-x64.zip`
- `dist/SHA256SUMS.txt`
- `dist/release-report.json`

`release-report.json` must contain:

```json
{
  "source_clean": true,
  "runtime_archive_verified": true,
  "release_eligible": true
}
```

`-AllowDirty` exists only for development verification. It permanently marks
that package as ineligible for publication.

## 3. Independent archive verification

```powershell
pwsh -NoProfile -File .\tools\release\Test-CsgRelease.ps1 `
  -ArchivePath .\dist\codex-safety-gate-<version>-win-x64.zip `
  -RequireReleaseEligible
```

Rebuild once with the same commit and runtime archive. The ZIP SHA256 must be
identical.

## 4. Acceptance before publishing

Complete `docs/RELEASE_CHECKLIST.md`, including the real Windows Sandbox flow
in `WINDOWS_TEST_PLAN.md`. Source, package, and contract tests do not substitute
for retained Sandbox evidence.

Only after the acceptance evidence is reviewed should the commit be tagged and
the ZIP plus `SHA256SUMS.txt` uploaded to a GitHub release.
