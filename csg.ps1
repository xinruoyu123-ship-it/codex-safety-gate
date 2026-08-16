#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Position=0,Mandatory=$true)]
    [ValidateSet('init','doctor','toolchain-pwsh','freeze','inspect','stage','seal','promote','rollback','list','compare')]
    [string]$Command,

    [string]$Source,
    [string]$ArtifactId,
    [string]$InstallCommand,
    [string]$StageId,
    [string]$Approval,
    [string]$Confirmation,
    [string]$LeftArtifact,
    [string]$RightArtifact,
    [string]$MainCodexHome=(Join-Path $HOME '.codex'),
    [switch]$AllowNetwork,
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$modules=Join-Path $PSScriptRoot 'modules'
Import-Module (Join-Path $modules 'Common.psm1') -Force
Import-Module (Join-Path $modules 'Artifact.psm1') -Force
Import-Module (Join-Path $modules 'Inspect.psm1') -Force
Import-Module (Join-Path $modules 'Toolchain.psm1') -Force
Import-Module (Join-Path $modules 'Stage.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $modules 'Promote.psm1') -Force

switch($Command){
    'init' {
        $root=Initialize-CsgLayout
        Write-Host "CSG V2 initialized: $root"
    }
    'doctor' {
        $root=Initialize-CsgLayout
        $sandbox=Test-WindowsSandboxAvailable
        [pscustomobject]@{
            csg_root=$root
            powershell=$PSVersionTable.PSVersion.ToString()
            git=[bool](Get-Command git -ErrorAction SilentlyContinue)
            windows_edition=$sandbox.windows_edition
            windows_sandbox_usable=$sandbox.usable
            windows_sandbox_feature=$sandbox.feature_state
            windows_sandbox_reason=$sandbox.reason
            main_codex_home=$MainCodexHome
            main_codex_exists=(Test-Path -LiteralPath $MainCodexHome)
        } | Format-List
    }
    'toolchain-pwsh' {
        Import-PwshToolchain | Out-Null
    }
    'freeze' {
        if(-not $Source){throw 'freeze requires -Source.'}
        $a=New-FrozenArtifact -Source $Source
        Write-Host "ArtifactId: $($a.artifact_id)"
        Write-Host "Commit: $($a.provenance.commit)"
        Write-Host "Archive SHA256: $($a.provenance.archive_sha256)"
    }
    'inspect' {
        if(-not $ArtifactId){throw 'inspect requires -ArtifactId.'}
        $r=Invoke-ArtifactInspection $ArtifactId
        Write-Host "Risk: $($r.risk_band)"
        Write-Host "Capabilities:"
        $r.capabilities | ForEach-Object {Write-Host "  $_"}
        Write-Host "Findings: $($r.counts.total)"
    }
    'stage' {
        if(-not $ArtifactId -or -not $InstallCommand){throw 'stage requires -ArtifactId and -InstallCommand.'}
        Invoke-SandboxStage -ArtifactId $ArtifactId -InstallCommand $InstallCommand -AllowNetwork:$AllowNetwork | Out-Null
    }
    'seal' {
        if(-not $StageId){throw 'seal requires -StageId.'}
        Seal-SandboxStage -StageId $StageId | Out-Null
    }
    'promote' {
        if(-not $StageId -or -not $Approval){throw 'promote requires -StageId and exact -Approval challenge.'}
        Invoke-SealedPromotion -StageId $StageId -Approval $Approval -MainCodexHome $MainCodexHome -Apply:$Apply
    }
    'rollback' {
        if(-not $StageId -or -not $Confirmation){throw 'rollback requires -StageId and -Confirmation "ROLLBACK <stage-id>".'}
        Invoke-CsgRollback -StageId $StageId -Confirmation $Confirmation -Apply:$Apply
    }
    'list' {
        $root=Initialize-CsgLayout
        $rows=@()
        foreach($f in Get-ChildItem -LiteralPath (Join-Path $root 'registry') -Filter '*.json' -File -ErrorAction SilentlyContinue){
            $r=Read-JsonFile $f.FullName
            $rows += [pscustomobject]@{id=$r.addon_id;status=$r.status;risk=$r.risk_band;artifact=$r.artifact_id;promoted=$r.promoted_at}
        }
        if($rows.Count){$rows|Format-Table -AutoSize}else{Write-Host 'Registry empty.'}
    }
    'compare' {
        if(-not $LeftArtifact -or -not $RightArtifact){throw 'compare requires -LeftArtifact and -RightArtifact.'}
        $l=Invoke-ArtifactInspection $LeftArtifact
        $r=Invoke-ArtifactInspection $RightArtifact
        $lc=@($l.capabilities);$rc=@($r.capabilities)
        [pscustomobject]@{
            left=$LeftArtifact;right=$RightArtifact
            left_risk=$l.risk_band;right_risk=$r.risk_band
            capability_added=@($rc|Where-Object {$_ -notin $lc})
            capability_removed=@($lc|Where-Object {$_ -notin $rc})
        } | Format-List
    }
}
