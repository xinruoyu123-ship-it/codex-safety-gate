# Alpha 7 release-pipeline evidence - 2026-08-17

This record covers source, runtime, and package tooling. It is not Windows
Sandbox acceptance evidence and does not authorize a public release.

## Source regression

- Static security regression: 77/77 passed.
- GUI state regression: 6/6 passed.
- Launcher regression: 1/1 passed.
- VM provisioning contract: 1/1 passed.
- The same suite passed from a source snapshot with `runtime/pwsh/` absent.
- `git diff --check` passed; only expected line-ending notices were emitted.

## Portable runtime provenance

- Upstream: `PowerShell/PowerShell` release `v7.6.4`.
- Archive: `PowerShell-7.6.4-win-x64.zip`.
- Official archive SHA256:
  `80832551c52809301e6071c8bac977beb5a2f1ec953eb4db9f94deb953333793`.
- Expanded runtime: 983 files, 296,034,085 bytes.
- Runtime tree SHA256:
  `760b749a09d44369199f38ffea19ba01676707a96210676f2f3d0800befcbe14`
  using canonical UTF-8 byte ordering.
- The retained official archive and local runtime were compared file by file:
  983 files matched and zero mismatches were found.

## Package pipeline

- A dirty-tree development build was marked `release_eligible=false`.
- A build without `-AllowDirty` correctly rejected the dirty repository.
- Two development builds from identical input produced the same ZIP SHA256.
- A temporary clean Git snapshot exercised the publishable branch:
  - source clean: true;
  - runtime archive verified: true;
  - release eligible: true;
  - package inventory: 1,045 files plus `RELEASE-MANIFEST.json`;
  - bundled runtime: 983 files;
  - independent archive verification: passed;
  - pipeline-test ZIP SHA256:
    `66b11412840ce0db81ac87b1b435c5d3530f1791f40e5a644706ddbb38df6cf3`.

The temporary clean-snapshot archive is a pipeline fixture, not the public
release artifact. The public artifact must be rebuilt from the final repository
commit and must produce a release report with all eligibility fields true.

## Still required

- GitHub Windows CI on the final pushed commit.
- Real Windows Sandbox acceptance on a supported Windows edition.
- Proof that the primary Codex home and credentials are absent from mappings.
- Clean-account extraction and launch test.
- Repository owner/name/visibility, commit identity, branch protection, private
  vulnerability reporting, final tag, and release asset review.
