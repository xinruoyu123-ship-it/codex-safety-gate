#requires -Version 7.0
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$repo=Split-Path -Parent $PSScriptRoot
$gui=Join-Path $repo 'CSG-GUI.ps1'
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('csg-gui-tests-'+[guid]::NewGuid().ToString('N'))
$oldCsgHome=$env:CSG_HOME
$results=New-Object System.Collections.Generic.List[object]

function Assert-Gui {
    param([bool]$Condition,[string]$Name,[string]$Evidence)
    if(-not $Condition){throw "FAIL: $Name -- $Evidence"}
    $script:results.Add([pscustomobject]@{test=$Name;status='PASS';evidence=$Evidence})
}

function Invoke-GuiCase {
    param([string]$Name,[string]$Source)
    $env:CSG_HOME=Join-Path $testRoot $Name
    $raw=& $gui -SmokeTest -SmokeSource $Source
    return (($raw -join "`n")|ConvertFrom-Json)
}

try{
    New-Item -ItemType Directory -Force -Path $testRoot|Out-Null
    $plain=Invoke-GuiCase 'plain' (Join-Path $PSScriptRoot 'fixtures\plain-skill')
    $plainFile=Join-Path $PSScriptRoot 'fixtures\plain-skill\demo-skill\SKILL.md'
    $fileInput=Invoke-GuiCase 'file-input' ('  "'+$plainFile+'"  ')
    $router=Invoke-GuiCase 'router' (Join-Path $PSScriptRoot 'fixtures\agent-router')
    $proxy=Invoke-GuiCase 'proxy' (Join-Path $PSScriptRoot 'fixtures\fake-proxy')

    Assert-Gui ($plain.detected_profile -eq 'skill' -and $plain.primary_action_enabled) 'Plain skill action' $plain.decision
    Assert-Gui ($fileInput.detected_profile -eq 'skill' -and $fileInput.primary_action_enabled -and $fileInput.resolved_source_path -eq (Split-Path -Parent $plainFile)) 'Direct file source' $fileInput.resolved_source_path
    Assert-Gui ($router.detected_profile -eq 'agent-router' -and $router.primary_action_enabled -and -not $router.promotion_allowed) 'Agent router declaration gate' "$($router.budget_status); $($router.decision)"
    Assert-Gui ($proxy.detected_profile -eq 'proxy-gateway' -and -not $proxy.primary_action_enabled) 'Proxy action blocked' $proxy.decision
    Assert-Gui ($plain.legacy_step_buttons -eq 0 -and $plain.audit_action -eq '检查这个') 'Two-step interface' "legacy buttons=$($plain.legacy_step_buttons)"
    Assert-Gui (-not $plain.technical_details_visible) 'Progressive disclosure' 'technical details hidden by default'
    Assert-Gui ($plain.permission_card_placeholder) 'Permission-card coverage' 'credential access is represented'
    Assert-Gui ($plain.source_browse_action -eq '浏览目录' -and $plain.source_file_action -eq '选择文件' -and $plain.source_drop_enabled) 'Source input helpers' 'directory browse, file selection, and file drop enabled'
    Assert-Gui ($plain.source_controls_visible -and $plain.primary_controls_visible -and $plain.minimum_layout_size -eq '840x660') 'Visible control bounds' 'source and primary actions remain inside the minimum-size tab'

    $results|Format-Table -AutoSize
    Write-Host "PASS: $($results.Count) GUI smoke tests"
}finally{
    if($null -eq $oldCsgHome){Remove-Item Env:CSG_HOME -ErrorAction SilentlyContinue}else{$env:CSG_HOME=$oldCsgHome}
    $resolved=[IO.Path]::GetFullPath($testRoot)
    $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if($resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolved).StartsWith('csg-gui-tests-')){
        Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
    }
}
