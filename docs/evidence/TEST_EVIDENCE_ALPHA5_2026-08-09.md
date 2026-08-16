# CSG Windows Alpha 5 Test Evidence

Date: 2026-08-09

## Verified

- PowerShell parser and repository JSON validation: PASS.
- Core/static security regression: 31/31 PASS.
- Deterministic GUI state regression: 6/6 PASS.
- Controlled observer plan includes JSONL output, ephemeral execution, ignored
  user config, read-only Codex sandbox policy, and no dangerous bypass flag.
- Observer plan SHA256: generated and verified per test run.
- Benchmark prompt tampering: detected.
- Raw Codex JSONL tampering: detected.
- Reported token snapshots and completed events: independently parsed from the
  fixture JSONL.
- Budget-gate CLI bypass: blocked.
- Runtime-observer-gate CLI bypass: blocked independently.
- All Alpha 4 Freeze, Seal, copy-only Promotion, replay protection, and
  conflict-safe Rollback regressions remain passing.

## Evidence status

- Observer plan and receipt format: verified locally.
- Hash-chain and parser behavior: verified locally.
- Exact total Token accounting across multiple Agents: pending.
- Child-process count, concurrency peak, and delegation depth telemetry: pending.
- Isolated Codex authentication: pending.
- Real Windows Sandbox observer execution: blocked on this Windows 11 Home host.
- Local packaged Codex executable was discovered, but direct invocation from the
  current automation shell returned Access Denied; no workaround copied or exposed
  host credentials.

## Security conclusion

Alpha 5 improves evidence collection but does not unlock Agent Router Promotion.
The receipt remains partial until process telemetry and isolated credentials are
verified on a supported disposable Windows environment.
