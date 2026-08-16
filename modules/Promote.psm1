Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -Force

function New-TargetBackup {
    param(
        [Parameter(Mandatory)][string]$Payload,
        [Parameter(Mandatory)][string]$MainCodexHome,
        [Parameter(Mandatory)][string]$BackupDir
    )
    if(Test-Path -LiteralPath $BackupDir){Remove-Item -LiteralPath $BackupDir -Recurse -Force}
    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
    $entries=@()
    foreach($f in Get-ChildItem -LiteralPath $Payload -Recurse -Force -File){
        $rel=(Get-RelativePathSafe -Base $Payload -Full $f.FullName).Replace('/','\')
        $dst=Join-Path $MainCodexHome $rel
        $state=Get-FileState $dst
        if($state.exists -and -not $state.directory){
            $bak=Join-Path (Join-Path $BackupDir 'files') $rel
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $bak) | Out-Null
            Copy-Item -LiteralPath $dst -Destination $bak -Force
        }
        $entries += [pscustomobject]@{
            path=$rel
            existed_before=[bool]$state.exists
            before_sha256=$state.sha256
            promoted_sha256=(Get-Sha256 $f.FullName)
        }
    }
    Write-JsonFile ([ordered]@{schema_version=2;entries=$entries}) (Join-Path $BackupDir 'backup-manifest.json')
    return @($entries)
}

function Invoke-SealedPromotion {
    param(
        [Parameter(Mandatory)][string]$StageId,
        [Parameter(Mandatory)][string]$Approval,
        [string]$MainCodexHome=(Join-Path $HOME '.codex'),
        [switch]$Apply
    )
    $root=Initialize-CsgLayout
    $sdir=Join-Path (Join-Path $root 'stages') $StageId
    $stagePath=Join-Path $sdir 'stage.json'
    if(-not (Test-Path -LiteralPath $stagePath)){throw "Unknown StageId: $StageId"}
    $s=Read-JsonFile $stagePath
    if($s.state -ne 'sealed'){throw 'Only sealed stages may be promoted.'}
    if($Approval -cne $s.approval_challenge){throw 'Approval challenge does not match exactly.'}
    if($s.runtime_budget -and [bool]$s.runtime_budget.requires_budget -and -not [bool]$s.runtime_budget.promotion_allowed){
        throw "Runtime budget gate blocked promotion: $($s.runtime_budget.summary)"
    }
    if($s.runtime_observer -and -not [bool]$s.runtime_observer.promotion_eligible){
        throw "Runtime observer gate blocked promotion: $($s.runtime_observer.blocker)"
    }

    $payload=$s.payload.path
    $currentHash=Get-PayloadTreeHash $payload
    if($currentHash -ne $s.payload.tree_sha256){throw 'Sealed payload changed after approval challenge was generated.'}

    Write-Host "Promotion plan"
    Write-Host "  Stage: $StageId"
    Write-Host "  Artifact: $($s.artifact_id)"
    Write-Host "  Risk: $($s.risk_band)"
    Write-Host "  Payload: $currentHash"
    Write-Host "  Destination: $MainCodexHome"
    Write-Host "  Files: $(@($s.payload.files).Count)"
    Write-Host "  THIRD-PARTY INSTALLER WILL NOT RUN."
    if(@($s.capability_surprises).Count){
        Write-Warning "Capability surprises: $(@($s.capability_surprises) -join ', ')"
    }

    if(-not $Apply){
        Write-Host ""
        Write-Host "Dry plan only. Re-run with -Apply after reviewing stage.json and capability-manifest.json."
        return
    }

    $registryPath=Join-Path (Join-Path $root 'registry') "$StageId.json"
    if(Test-Path -LiteralPath $registryPath){
        throw 'This sealed stage already has a registry record. Create and approve a new stage instead of replaying promotion.'
    }

    New-Item -ItemType Directory -Force -Path $MainCodexHome | Out-Null
    $backup=Join-Path (Join-Path $root 'backups') ("$StageId-before-promote")
    $backupEntries=New-TargetBackup -Payload $payload -MainCodexHome $MainCodexHome -BackupDir $backup

    $changes=@()
    foreach($f in Get-ChildItem -LiteralPath $payload -Recurse -Force -File){
        $rel=(Get-RelativePathSafe -Base $payload -Full $f.FullName).Replace('/','\')
        $dst=Join-Path $MainCodexHome $rel
        $before=Get-FileState $dst
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
        Copy-Item -LiteralPath $f.FullName -Destination $dst -Force
        $srcHash=Get-Sha256 $f.FullName
        $dstHash=Get-Sha256 $dst
        if($dstHash -ne $srcHash){throw "Post-copy hash mismatch: $rel"}
        $changes += [pscustomobject]@{
            action=if($before.exists){'modified'}else{'added'}
            path=$rel
            before=$before.sha256
            after=$dstHash
        }
    }

    $record=[ordered]@{
        schema_version=2;addon_id=$StageId;status='approved';promoted_at=(Get-Date).ToString('o')
        artifact_id=$s.artifact_id;risk_band=$s.risk_band;payload_sha256=$currentHash
        destination=$MainCodexHome;backup=$backup
        changes=@($changes);capability_surprises=@($s.capability_surprises)
        approval=$Approval
        rollback_challenge="ROLLBACK $StageId"
        invariant='No third-party installer was executed during promotion; only payload target files were touched.'
    }
    Write-JsonFile $record $registryPath
    Write-Host "Promotion status: approved"
    Write-Host "Backup: $backup"
    Write-Host "Rollback challenge: ROLLBACK $StageId"
}

function Invoke-CsgRollback {
    param(
        [Parameter(Mandatory)][string]$StageId,
        [Parameter(Mandatory)][string]$Confirmation,
        [switch]$Apply
    )
    $root=Initialize-CsgLayout
    $regPath=Join-Path (Join-Path $root 'registry') "$StageId.json"
    if(-not (Test-Path -LiteralPath $regPath)){throw "No registry record: $StageId"}
    $r=Read-JsonFile $regPath
    if($Confirmation -cne "ROLLBACK $StageId"){throw 'Rollback confirmation does not match exactly.'}
    $backupManifest=Read-JsonFile (Join-Path $r.backup 'backup-manifest.json')

    $conflicts=@()
    foreach($e in @($backupManifest.entries)){
        $dst=Join-Path $r.destination $e.path
        $now=Get-FileState $dst
        if(-not $now.exists -or $now.sha256 -ne $e.promoted_sha256){
            $conflicts += [pscustomobject]@{path=$e.path;expected_promoted=$e.promoted_sha256;current=$now.sha256}
        }
    }

    Write-Host "Rollback plan: $StageId"
    Write-Host "Files: $(@($backupManifest.entries).Count)"
    Write-Host "Conflicts since promotion: $($conflicts.Count)"
    if($conflicts.Count){
        $conflicts | Format-Table -AutoSize
        throw 'Rollback blocked: one or more promoted files changed after promotion. Manual merge required.'
    }
    if(-not $Apply){
        Write-Host 'Dry plan only. Re-run with -Apply.'
        return
    }

    foreach($e in @($backupManifest.entries)){
        $dst=Join-Path $r.destination $e.path
        if($e.existed_before){
            $bak=Join-Path (Join-Path $r.backup 'files') $e.path
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
            Copy-Item -LiteralPath $bak -Destination $dst -Force
            if((Get-Sha256 $dst) -ne $e.before_sha256){throw "Rollback hash mismatch: $($e.path)"}
        } else {
            Remove-Item -LiteralPath $dst -Force
        }
    }
    $r.status='rolled_back'
    $r|Add-Member -NotePropertyName rolled_back_at -NotePropertyValue (Get-Date).ToString('o') -Force
    Write-JsonFile $r $regPath
    Write-Host 'Rollback completed.'
}

Export-ModuleMember -Function *
