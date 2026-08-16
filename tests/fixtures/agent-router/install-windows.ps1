param([Parameter(Mandatory)][string]$HomePath)

$target = Join-Path $HomePath '.codex\skills\agent-router-fixture'
New-Item -ItemType Directory -Force -Path $target | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'AGENTS.md') -Destination $target -Force
