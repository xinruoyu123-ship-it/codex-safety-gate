# Portable runtime policy

The source repository intentionally does not commit `runtime/pwsh/`.

The directory is populated only when building a release package from a reviewed
PowerShell 7 distribution. `runtime/manifest.json` records the executable hash
that the launcher and static tests verify. A source checkout can run with a
system PowerShell 7 installation; a release package must pass the bundled
runtime tests before it is published.

