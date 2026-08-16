# Publishing CSG to GitHub

This document is the maintainer handoff for the first public repository and each
later release. It intentionally leaves the owner, repository name, and commit
identity as explicit choices; never infer them from a local machine.

## Before creating the repository

Confirm these values with the maintainer:

- GitHub owner or organization;
- repository name and public/private visibility;
- commit author name and email;
- default branch name;
- whether GitHub Private Vulnerability Reporting is available for the account.

Do not publish until the release checklist has evidence for the source, package,
and supported Windows Sandbox flow. A green host test alone is not sufficient.

## Create and push the source repository

Create an empty GitHub repository in the browser. Do not add a README, license, or
`.gitignore` because this worktree already contains them. From a clean worktree:

```powershell
git config user.name "<confirmed commit name>"
git config user.email "<confirmed commit email>"
git remote add origin https://github.com/<owner>/<repository>.git
git push -u origin main
```

Review the first push in the browser before changing repository settings. The
source repository must not contain `runtime/pwsh/`, `.devtools/`, `dist/`, VM
images, credentials, or local CSG state.

## Repository settings

After the first push:

1. Enable Actions and confirm `.github/workflows/ci.yml` passes from a clean clone.
2. Require the Windows CI check on the protected default branch.
3. Enable Private Vulnerability Reporting if the account supports it.
4. Add the repository description and topics only after the owner confirms the
   intended public wording.

## Build and publish a release

On a supported Windows machine with the pinned runtime archive available:

```powershell
pwsh -NoProfile -File .\tools\release\Get-CsgRuntime.ps1
$archive = '.\.devtools\runtime\PowerShell-7.6.4-win-x64.zip'
pwsh -NoProfile -File .\tools\release\Build-CsgRelease.ps1 `
  -RuntimeArchivePath $archive
pwsh -NoProfile -File .\tools\release\Test-CsgRelease.ps1 `
  -ArchivePath .\dist\codex-safety-gate-<version>-win-x64.zip `
  -RunTests -RequireReleaseEligible
```

Only when `release-report.json` says `source_clean=true`,
`runtime_archive_verified=true`, and `release_eligible=true` should the
maintainer create a tag and upload the ZIP plus `SHA256SUMS.txt` to a GitHub
Release. The tag, source commit, archive hash, and release manifest must agree.
Use `docs/RELEASE_NOTES_3.0.0-alpha.8.md` as the release body and recheck that its
supported profiles and residual-risk statements still match the shipped code.

## Never publish as proof

- a development package with `release_eligible=false`;
- a skipped runtime or Sandbox test;
- a report from a dirty worktree;
- credentials, session data, or raw private prompts;
- a claim that static inspection proves arbitrary third-party code is safe.
