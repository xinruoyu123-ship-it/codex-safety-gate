# CSG Windows Alpha 8 Test Evidence

Date: 2026-08-17

## Verified

- Static security regression: 100/100 PASS.
- GUI state regression: 9/9 PASS, including directory browse, direct file
  selection, drag-and-drop enablement, resolved file-source paths, and minimum
  layout bounds.
- Launcher regression: 1/1 PASS; bundled PowerShell 7.6.4 selected.
- VM provisioning contract: 1/1 PASS.
- Release archive verification: PASS; archive inventory contains 1,049 files,
  including 983 bundled runtime files.
- Bundled runtime tree SHA256:
  `760b749a09d44369199f38ffea19ba01676707a96210676f2f3d0800befcbe14`.
- Archive SHA256:
  `6e48cf6cc89a1ca0abea2a4268d3fca1d10167ee01e45ccd9f9215bc49f43b18`.
- The release archive's embedded static, GUI, launcher, and VM checks all pass.

## Evidence status

- The current worktree intentionally contains the alpha.8 source and GUI input
  changes, so `dist/release-report.json` correctly says `source_clean=false` and
  `release_eligible=false`.
- The archive is a verified development package, not a public release artifact.
- Public repository `xinruoyu123-ship-it/codex-safety-gate` was created with
  `main` as the default branch, and commit `ea40271` was pushed successfully.
- GitHub Windows CI run `32035257620` completed with `success` for commit
  `ea40271`.
- Windows Sandbox acceptance, clean-account extraction, branch protection, and
  final GitHub release review remain pending.

## Security conclusion

Alpha 8's local-source input and GUI changes are regression-tested and the public
source repository is CI-verified. Release-asset publication must still wait for
a clean final package and the outstanding Windows Sandbox acceptance evidence.
