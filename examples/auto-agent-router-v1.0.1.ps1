# codex-auto-agent-router v1.0.1 — V2 example

$CSG = Join-Path $PSScriptRoot '..\csg.ps1'
$URL = 'https://github.com/moonjoin/codex-auto-agent-router/releases/tag/v1.0.1'

pwsh -NoProfile -File $CSG freeze -Source $URL

# Copy the printed ArtifactId:
$ArtifactId = '<artifact-id>'

pwsh -NoProfile -File $CSG inspect -ArtifactId $ArtifactId

# NOTE:
# v1.0.1 requires PowerShell 7. Freeze the host pwsh runtime once and map it
# read-only into Windows Sandbox:
pwsh -NoProfile -File $CSG toolchain-pwsh

# Then stage the actual installer with networking still disabled:
pwsh -NoProfile -File $CSG stage `
  -ArtifactId $ArtifactId `
  -InstallCommand 'pwsh -NoProfile -File .\install-windows.ps1 -HomePath $env:CSG_TARGET_HOME'
