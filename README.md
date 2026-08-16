# Codex Safety Gate (CSG)

**Status: 3.0.0-alpha.7 / pre-release / Windows-first.**

This repository is the canonical source for the future public CSG release.
Historical local alpha packages are evidence, not the source of truth.

CSG V2 is an admission controller for third-party Codex extensions: Skills, agent routers, token savers, MCP helpers, model proxies, wrappers, and similar tooling.

CSG does not certify that a project is safe. It produces reviewable evidence,
blocks known unsafe deployment paths, and keeps unverified behavior from being
promoted into the primary Codex home.

The core invariant is:

> **A third-party installer may execute in Windows Sandbox, but it is never re-executed during promotion into the primary Codex home.**

Promotion copies only a sealed, hashed Codex payload produced by staging.

## V2 security model

```text
GitHub/local source
      │
      ▼
FREEZE
commit/ref + source-tree hash + source.zip hash
      │
      ▼
INSPECT
static capabilities/risk
      │
      ▼
WINDOWS SANDBOX
source read-only
control scripts read-only
dedicated output folder writable
network OFF by default
clipboard OFF
vGPU OFF
      │
      ▼
SEAL
merge only:
  output/codex-home/**
  output/user/.codex/**
hash complete payload
generate approval challenge
      │
      ▼
HUMAN APPROVAL
exact challenge string
      │
      ▼
PROMOTE
copy sealed payload only
NO third-party installer execution
```

CSG uses Windows Sandbox with networking and clipboard disabled by default,
read-only source/control mappings, and one dedicated writable output mapping.

## Repository verification

Run the host-safe checks from a PowerShell 7 terminal:

```powershell
pwsh -NoProfile -File .\tests\Run-StaticTests.ps1
pwsh -NoProfile -File .\tests\Run-GuiSmokeTests.ps1
pwsh -NoProfile -File .\tests\Run-LauncherTests.ps1
pwsh -NoProfile -File .\tests\Run-VmProvisioningTests.ps1
```

A source checkout intentionally excludes `runtime/pwsh/`. It uses an installed
PowerShell 7 and reports bundled-runtime verification as `SKIP`. A distributable
release package must include the reviewed runtime and pass the same checks with
no runtime skip.

These tests do not replace the real Windows Sandbox acceptance flow documented
in [WINDOWS_TEST_PLAN.md](WINDOWS_TEST_PLAN.md).

## Evidence levels

- **Source verified:** host-safe tests pass in a clean source checkout.
- **Package verified:** the exact release archive and bundled runtime hashes pass.
- **Sandbox verified:** the real VM/Sandbox workflow passes with retained logs.
- **Not verified:** missing or indirect evidence; never present this as a pass.

## Requirements

- Windows 10/11 edition that supports Windows Sandbox (Windows Home is not supported).
- Windows Sandbox feature enabled.
- PowerShell 7 on the host.
- Git on the host for GitHub source freezing.
- The installer command must be runnable **inside Windows Sandbox** using software available there.

### PowerShell 7 caveat

Windows Sandbox is not guaranteed to contain `pwsh`. CSG's bootstrap itself uses inbox `powershell.exe`.

If a third-party installer requires PowerShell 7 or another runtime, do **not** silently fall back to executing it on the host. Use one of these approaches:

1. provide a separately reviewed portable toolchain to the sandbox in a future CSG toolchain mapping;
2. enable sandbox networking explicitly and install the prerequisite inside the sandbox;
3. wait for an addon installation path compatible with inbox PowerShell.

V2 intentionally fails closed rather than converting a sandbox problem into a host-execution problem.

---

# Quick start

```powershell
pwsh -NoProfile -File .\csg.ps1 init
pwsh -NoProfile -File .\csg.ps1 doctor

# Recommended when addons require PowerShell 7 inside Sandbox:
pwsh -NoProfile -File .\csg.ps1 toolchain-pwsh
```

## 1. Freeze source

```powershell
pwsh -NoProfile -File .\csg.ps1 freeze `
  -Source "https://github.com/moonjoin/codex-auto-agent-router/releases/tag/v1.0.1"
```

仓库首页、`tree`、`blob` 和 `raw` 链接都会被识别；文件页链接会按链接所在的仓库和分支冻结源码。

You receive an `ArtifactId`.

The source is cloned once, `.git` is removed, the source tree is hashed, a frozen `source.zip` is created, and the archive is SHA256-pinned.

All later stages use the frozen archive. They do not refetch the repository.

## 2. Inspect the frozen artifact

```powershell
pwsh -NoProfile -File .\csg.ps1 inspect `
  -ArtifactId "<artifact-id>"
```

This emits a risk band and capability indicators such as:

- `codex.global_agents_write`
- `codex.config_write`
- `codex.launcher_wrap`
- `network.local_proxy`
- `network.outbound`
- `process.spawn`
- `os.persistence`
- `secrets.access`

## 3. Sandbox stage

```powershell
pwsh -NoProfile -File .\csg.ps1 stage `
  -ArtifactId "<artifact-id>" `
  -InstallCommand '<command runnable inside Windows Sandbox>'
```

Networking is disabled by default.

If network is genuinely required:

```powershell
... stage ... -AllowNetwork
```

Treat `-AllowNetwork` as a meaningful permission expansion, not a convenience flag.

CSG generates and launches a `.wsb` with:

- source artifact mapped **read-only**;
- CSG bootstrap mapped **read-only**;
- one dedicated stage-output directory mapped **read/write**;
- network disabled unless explicitly allowed;
- clipboard disabled;
- vGPU disabled;
- printer/audio/video redirection disabled.

The installer sees:

```text
HOME=C:\CSG\out\user
USERPROFILE=C:\CSG\out\user
CODEX_HOME=C:\CSG\out\codex-home
CSG_TARGET_HOME=C:\CSG\out\user
CSG_TARGET_CODEX_HOME=C:\CSG\out\codex-home
```

## 4. Seal the output

After Sandbox finishes:

```powershell
pwsh -NoProfile -File .\csg.ps1 seal `
  -StageId "<stage-id>"
```

Sealing:

1. requires a successful sandbox result;
2. considers only `codex-home/**` and `user/.codex/**` promotable;
3. rejects conflicting copies of the same relative path;
4. builds a single payload directory;
5. SHA256-hashes every file and the canonical payload tree;
6. derives observed Codex capabilities from actual output paths;
7. generates an exact approval challenge.

Example:

```text
APPROVE stage-20260808-... 2af3b8e91d42
```

## 5. Promotion plan

```powershell
pwsh -NoProfile -File .\csg.ps1 promote `
  -StageId "<stage-id>" `
  -Approval "APPROVE stage-... 2af3b8e91d42"
```

Without `-Apply`, this changes nothing.

## 6. Explicit promotion

```powershell
pwsh -NoProfile -File .\csg.ps1 promote `
  -StageId "<stage-id>" `
  -Approval "APPROVE stage-... 2af3b8e91d42" `
  -Apply
```

Promotion:

- verifies the sealed payload hash again;
- backs up the primary `.codex`;
- copies the sealed file overlay;
- verifies each destination hash;
- does not run the third-party installer;
- does not automatically delete existing main Codex files;
- records actual changes in the registry.

This removes the V1 TOCTOU problem where the installer was executed once in staging and again during promotion.

---

# Update/capability diff

Freeze two versions, then:

```powershell
pwsh -NoProfile -File .\csg.ps1 compare `
  -LeftArtifact "<old-artifact>" `
  -RightArtifact "<new-artifact>"
```

The first V2 implementation reports capability additions/removals and risk-band changes.

A permission expansion should trigger a fresh manual review.

---

# Deliberately unsupported promotion behaviors

CSG V2 only auto-promotes Codex-home files.

It does **not** automatically reproduce:

- Windows services;
- scheduled tasks;
- Registry changes;
- persistent PATH changes;
- global package installation;
- binaries installed outside `.codex`;
- credentials;
- arbitrary files elsewhere in the user profile.

This is intentional.

If an addon fundamentally depends on those capabilities, it should remain ORANGE/RED and require a separate, addon-specific deployment plan.

---

# Threat-model limits

Windows Sandbox materially reduces exposure, but no isolation technology is a mathematical guarantee.

Also:

- writable mapped folders are host-visible by design;
- enabling networking exposes the sandbox to network surfaces;
- only the dedicated output folder is writable-mapped by CSG;
- source and control folders are read-only-mapped;
- Windows Home does not support Windows Sandbox;
- CSG V2 does not yet capture full process/network/Registry telemetry from inside Sandbox;
- it does not yet enforce token/agent budgets at runtime;
- it does not yet verify GitHub release signatures or Sigstore/SLSA attestations.

Those are the next major work items.

---

# V2.1 roadmap

1. Portable, pinned sandbox toolchains (`pwsh`, Python, Node) with SHA256 manifests.
2. ETW/Sysmon-style behavior telemetry for process/network/Registry activity.
3. Network allowlist mode rather than only network on/off.
4. Semantic `AGENTS.md` / Skill behavior diff.
5. Token, concurrency, retry, escalation and model budgets.
6. Addon profiles:
   - Skill/router
   - MCP
   - local proxy/model gateway
   - Codex wrapper/shim
7. Release provenance:
   - GitHub release asset hashes
   - signature/attestation verification where available
8. Deterministic rollback packages and uninstall manifests.


# Frozen sandbox PowerShell 7 toolchain

Many Codex ecosystem projects require `pwsh`, while Windows Sandbox does not guarantee PowerShell 7 is present.

Run once:

```powershell
pwsh -NoProfile -File .\csg.ps1 toolchain-pwsh
```

CSG copies the host PowerShell 7 installation directory into:

```text
~/.codex-safety-v2/toolchains/pwsh/
```

and hashes the complete tree. During staging, that frozen runtime is mapped **read-only** into:

```text
C:\CSG\toolchains\pwsh
```

and prepended to the Sandbox `PATH`.

This avoids enabling networking merely to install PowerShell 7.

The toolchain hash is verified before use.

# Rollback

V2 no longer copies or hashes the entire primary `.codex` during promotion. This is important for long-lived Codex installations whose `sessions` directory may contain hundreds of megabytes or more.

Instead, CSG backs up only the exact destination files present in the sealed payload.

After promotion:

```powershell
pwsh -NoProfile -File .\csg.ps1 rollback `
  -StageId "<stage-id>" `
  -Confirmation "ROLLBACK <stage-id>"
```

This is a dry plan.

Apply:

```powershell
pwsh -NoProfile -File .\csg.ps1 rollback `
  -StageId "<stage-id>" `
  -Confirmation "ROLLBACK <stage-id>" `
  -Apply
```

Safety rule: rollback refuses to overwrite/delete a promoted file if that file has changed since promotion. That prevents rollback from silently destroying later user or Codex edits.
