# CSG Windows Alpha 4 Test Evidence

Date: 2026-08-09

## Verified in this build

- PowerShell and repository JSON parsing: PASS.
- Core/static security regression: 26/26 PASS.
- Deterministic GUI state regression: 6/6 PASS.
- Agent Router with an in-policy declaration: Sandbox action enabled, Promotion
  disabled while runtime enforcement is unverified.
- Missing Agent budget: Sandbox evidence collection allowed, Promotion blocked.
- Over-limit Agent budget: automatic flow blocked.
- Direct CLI Promotion with an unverified runtime budget: blocked.
- Plain Skill behavior, frozen-artifact tamper detection, approval binding,
  copy-only Promotion, replay protection, and conflict-safe rollback still pass.

## Evidence classification

- Budget declaration parsing and policy comparison: verified.
- Runtime Agent/Token enforcement: not yet implemented.
- Exact Token savings: not measured and not claimed.
- Windows Sandbox integration: blocked on the current Windows 11 Home machine;
  no host-execution fallback was used.

## Next required evidence

Implement a trusted CSG-controlled runtime observer, then run Baseline vs Addon
tasks in Windows Sandbox while collecting quality result, input/output/reasoning
tokens, Agent count, call count, retries, latency, and budget-limit violations.
