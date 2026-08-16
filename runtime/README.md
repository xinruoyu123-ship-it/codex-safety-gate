# Portable runtime policy

The source repository intentionally does not commit `runtime/pwsh/`.

The directory is populated only when building a release package from a reviewed
PowerShell 7 distribution. `runtime/manifest.json` records the executable hash
and the complete runtime tree hash, together with the official release archive
URL and SHA256. A source checkout can run with a system PowerShell 7
installation; a release package must reproduce the manifest from that pinned
archive and pass the bundled runtime tests before it is published.
