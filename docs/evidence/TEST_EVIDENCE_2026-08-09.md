# CSG Alpha 3 validation evidence — 2026-08-09

## Verified in this sprint

- Static/core regression: **22 passed** under PowerShell 7.6.4.
- GUI state regression:
  - Plain Skill: YELLOW, automatic safe-test action enabled.
  - Agent Router: YELLOW, action enabled, Agent/Token cost warning present.
  - Fake Proxy: ORANGE, generic action disabled, dedicated Profile required.
- The old four-step action buttons are absent.
- Technical details are hidden by default.
- The real `CSG.cmd` wrapper created a responsive window titled
  `Codex Safety Gate — Windows` and remained present after shutdown.
- Impeccable's mechanical detector returned no findings for the changed GUI and
  presentation module.

## Model correction from evidence

The previous GUI exposed the internal state machine as the user's workflow.
Freeze, Stage, Seal, and approval are still necessary security states, but they
do not each deserve a normal-user button. Alpha 3 keeps those states internally
and exposes only the decisions the user must make.

## Still not verified

- A real `.wsb` launch and mapped-folder behavior.
- Automatic result collection after Sandbox exits.
- Full visual inspection through a Windows UI-control runtime.

The current Windows 11 Home machine cannot supply the first item. CSG remains
fail-closed and does not execute third-party installers on the host.
