#requires -Version 7.0
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$launcher=Join-Path $repo 'CSG.cmd'
$oldPath=$env:PATH
$bundle=Join-Path $repo 'runtime\pwsh\pwsh.exe'
$expectBundled=Test-Path -LiteralPath $bundle

try{
    if($expectBundled){$env:PATH="$env:SystemRoot\System32"}
    $raw=& cmd.exe /d /c "`"$launcher`" --smoke"
    if($LASTEXITCODE -ne 0){throw "FAIL: launcher smoke exited with $LASTEXITCODE -- $($raw -join ' ')"}
    $result=($raw -join "`n")|ConvertFrom-Json
    if($expectBundled -and $result.runtime_source -ne 'bundled'){throw "FAIL: expected bundled runtime, got $($result.runtime_source)"}
    if(-not $expectBundled -and $result.runtime_source -notin @('path','program-files')){throw "FAIL: source checkout expected system runtime, got $($result.runtime_source)"}
    if([version]$result.pwsh_version -lt [version]'7.0'){throw "FAIL: PowerShell version is $($result.pwsh_version)"}
    if($result.title -ne 'Codex Safety Gate — Windows'){throw "FAIL: GUI title was $($result.title)"}
    if(-not $result.primary_action_enabled){throw 'FAIL: GUI smoke did not enable the plain-skill action.'}
    [pscustomobject]@{
        test=if($expectBundled){'Bundled launcher smoke'}else{'Source-checkout launcher smoke'}
        status='PASS'
        runtime=$result.runtime_source
        pwsh=$result.pwsh_version
        title=$result.title
    }|Format-Table -AutoSize
    Write-Host 'PASS: 1 launcher test'
}finally{$env:PATH=$oldPath}
