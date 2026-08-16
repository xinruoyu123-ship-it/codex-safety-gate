# CSG V2 Architecture Notes

## Trust boundaries

### Trusted host code

- CSG entrypoint/modules
- frozen artifact metadata
- stage metadata
- promotion logic
- explicit human approval

### Untrusted code

- downloaded/cloned third-party source
- third-party installer
- addon runtime until promoted

### Sandbox host exposure

Read-only:
- frozen artifact directory
- CSG sandbox control directory

Read/write:
- dedicated stage output directory only

Not mapped:
- primary `.codex`
- browser profile
- SSH directory
- Git credentials
- arbitrary user home folders

## Core invariants

1. Freeze once, then verify hashes before every stage.
2. Stage never receives the primary `.codex`.
3. Network is deny-by-default.
4. Promotion never executes third-party code.
5. Promotion only overlays sealed `.codex` files.
6. Deletion from primary `.codex` is never automatic in V2.
7. Human approval is exact-string gated and bound to payload hash.
8. A payload hash change invalidates approval.
9. RED static artifacts do not stage by default.
10. Unsupported capabilities fail closed rather than being recreated automatically.

## Why promotion is a copy, not installer replay

Installer replay breaks the core equivalence between "what was tested" and "what is installed."

A stage could differ from promotion because of:

- environment-sensitive installer branches;
- mutable remote dependencies;
- `latest` package versions;
- time-dependent scripts;
- explicit CSG_STAGE/CSG_PROMOTE detection;
- compromised upstream between runs.

V2 therefore promotes a content-addressed output payload instead.

## Remaining hard problem

Some extensions are not "file overlays." A proxy may need:
- a binary runtime,
- a service,
- a port listener,
- credentials,
- firewall/network behavior.

Those must not be forced through the simple overlay model. CSG should classify them into a higher-risk deployment profile with explicit runtime policy and additional observability.


## Promotion performance invariant

Promotion must not hash/copy the entire `~/.codex` tree. Session rollouts can become hundreds of MB.

V2 backs up and verifies only target files present in the sealed payload.

## Frozen host toolchains

A sandbox may need trusted runtimes unavailable in the base image. CSG may import an explicitly selected host runtime into its own content-addressed toolchain store and map it read-only. Toolchain mutation invalidates its hash and blocks staging.
