#requires -Version 7.0
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
$script = Join-Path $repo 'tools\vm\Prepare-CsgSandboxVm.ps1'
$pwsh = Join-Path $PSHOME 'pwsh.exe'
$raw = & $pwsh -NoProfile -NonInteractive -File $script -ValidationOnly
if ($LASTEXITCODE -ne 0) {
    throw "VM validation mode failed with exit code $LASTEXITCODE."
}

$plan = ($raw -join "`n") | ConvertFrom-Json
if ([IO.Path]::GetFullPath($plan.project_root) -ne [IO.Path]::GetFullPath($repo)) {
    throw "VM script default project root is not repository-relative: $($plan.project_root)"
}
if ($plan.iso_sha256_required -ne $true) {
    throw 'VM script must require a pinned ISO hash unless explicitly overridden.'
}
if ($plan.vm_memory_mb -ne 8192 -or $plan.vm_cpu_count -ne 4) {
    throw 'VM defaults changed without updating the provisioning contract.'
}
$source = Get-Content -LiteralPath $script -Raw -Encoding UTF8
if ($source -match 'CsgTest123!' -or $source -match 'D:\\5\\CSG-codex-safety-gate-windows') {
    throw 'VM script contains a machine-specific path or the retired default password.'
}

[pscustomobject]@{test='VM provisioning validation';status='PASS';project_root=$plan.project_root;iso_sha256_required=$plan.iso_sha256_required}|Format-Table -AutoSize
Write-Host 'PASS: 1 VM provisioning test'
