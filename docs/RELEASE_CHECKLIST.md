# Release checklist

A green source test is not sufficient to publish a CSG release.

## Source

- [ ] Version and changelog agree.
- [ ] License, security policy, threat model, and contribution guide are present.
- [ ] No credentials, machine-specific paths, VM images, local state, or personal notes are tracked.
- [ ] Windows CI passes from a clean clone.
- [ ] All documented commands match the shipped interface.

## Package

- [ ] Portable PowerShell comes from a reviewed, pinned distribution.
- [ ] `runtime/manifest.json` matches the packaged executable.
- [ ] Launcher, static, GUI, and VM validation tests pass with no runtime skip.
- [ ] Archive inventory and SHA256 are recorded.
- [ ] `release-report.json` says source clean, runtime archive verified, and release eligible.
- [ ] A second build from the same commit produces the same ZIP SHA256.
- [ ] A clean Windows account can extract and launch the package.

## Sandbox acceptance

- [ ] Supported Windows guest and Windows Sandbox are confirmed.
- [ ] Source/control mappings are read-only and the primary `.codex` is absent.
- [ ] Networking, clipboard, vGPU, audio, video, and printer redirection match policy.
- [ ] Plain Skill stage, seal, dry-run promotion, apply, conflict, and rollback pass.
- [ ] Proxy/gateway and unverified Agent routes remain blocked.
- [ ] Logs and hashes are retained under `docs/evidence/` with sensitive data removed.

## GitHub

- [ ] Repository owner, name, description, topics, and visibility are confirmed.
- [ ] Private vulnerability reporting is enabled.
- [ ] Branch protection requires Windows CI.
- [ ] Release notes state unsupported profiles and residual risk.
- [ ] Tag, source commit, archive hash, and uploaded assets agree.
