#requires -Version 7.0
[CmdletBinding()]
param(
    [switch]$SmokeTest,
    [string]$RuntimeSource='unknown'
)

$ErrorActionPreference='Stop'
$gui=Join-Path $PSScriptRoot 'CSG-GUI.ps1'
$logRoot=Join-Path $env:LOCALAPPDATA 'CodexSafetyGate\logs'
$logPath=Join-Path $logRoot 'launcher-error.log'

try{
    Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue
    if($SmokeTest){
        $oldCsgHome=$env:CSG_HOME
        $smokeHome=Join-Path ([IO.Path]::GetTempPath()) ('csg-launcher-smoke-'+[guid]::NewGuid().ToString('N'))
        try{
            $env:CSG_HOME=$smokeHome
            $source=Join-Path $PSScriptRoot 'tests\fixtures\plain-skill'
            $raw=& $gui -SmokeTest -SmokeSource $source
            $result=($raw -join "`n")|ConvertFrom-Json
            $result|Add-Member -NotePropertyName runtime_source -NotePropertyValue $RuntimeSource -Force
            $result|Add-Member -NotePropertyName pwsh_version -NotePropertyValue $PSVersionTable.PSVersion.ToString() -Force
            $result|ConvertTo-Json -Depth 20
        }finally{
            if($null -eq $oldCsgHome){Remove-Item Env:CSG_HOME -ErrorAction SilentlyContinue}else{$env:CSG_HOME=$oldCsgHome}
            $resolved=[IO.Path]::GetFullPath($smokeHome)
            $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
            if($resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolved).StartsWith('csg-launcher-smoke-')){
                Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        exit 0
    }
    & $gui
}catch{
    New-Item -ItemType Directory -Force -Path $logRoot|Out-Null
    $message="$(Get-Date -Format o)`r`nPowerShell: $($PSVersionTable.PSVersion)`r`nRuntime: $RuntimeSource`r`n$($_|Out-String)"
    Set-Content -LiteralPath $logPath -Value $message -Encoding utf8
    try{
        Add-Type -AssemblyName System.Windows.Forms
        [Windows.Forms.MessageBox]::Show("Codex Safety Gate 启动失败。`r`n`r`n$($_.Exception.Message)`r`n`r`n错误日志：$logPath",'CSG 启动失败','OK','Error')|Out-Null
    }catch{Write-Error $message}
    exit 1
}
