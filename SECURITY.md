# Security Policy

CSG is security-sensitive pre-release software. A passing CSG report is evidence about the checks that ran; it is not a guarantee that third-party code is safe.

## Reporting a vulnerability

Do not open a public issue for a vulnerability that could enable host code execution, credential access, sandbox escape, approval bypass, payload substitution, or destructive rollback.

Use GitHub Private Vulnerability Reporting for this repository. If private reporting is not enabled yet, do not publish exploit details; open a minimal issue asking the maintainers to enable a private reporting channel.

Include:

- affected CSG version and Windows version;
- the violated security invariant;
- a minimal reproducible case;
- expected and actual behavior;
- whether credentials, the primary Codex home, or host execution were exposed.

## Supported versions

No version is production-supported before the first public release. Security fixes will be applied to the latest development branch only until a support policy is published.

## Core invariants

- Third-party installers never execute on the host during promotion.
- The primary Codex home is never mapped into Windows Sandbox.
- Promotion copies only a sealed payload whose hashes are rechecked.
- Approval is bound to the stage and payload hash.
- Unsupported or unverifiable behavior fails closed.

