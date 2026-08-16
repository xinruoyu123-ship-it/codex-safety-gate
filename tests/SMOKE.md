# Manual smoke checklist for a Windows test machine

1. `csg.ps1 doctor` reports Windows Sandbox usable.
2. Freeze a local harmless fixture.
3. Modify the original fixture after freeze; inspect must still use frozen content.
4. Tamper with `source.zip`; inspect/stage must refuse due to hash mismatch.
5. Stage a fixture that writes only `$env:CSG_TARGET_HOME\.codex\skills\demo`.
6. Seal; approval challenge includes payload hash prefix.
7. Tamper with payload after seal; promote must refuse.
8. Promote without `-Apply`; primary `.codex` unchanged.
9. Promote with wrong Approval; refuse.
10. Promote with exact Approval + `-Apply`; files copied and hashes match.
11. Stage fixture writes outside `.codex` under sandbox output; it is not promoted.
12. Stage fixture requires network with default stage; request fails.
13. Compare old/new fixtures; capability expansion is shown.
