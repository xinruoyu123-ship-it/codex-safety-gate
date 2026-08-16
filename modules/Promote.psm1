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
        $null=Assert-CsgPromotableCodexPath -RelativePath $rel
        $dst=Resolve-CsgChildPath -Root $MainCodexHome -RelativePath $rel -RejectReparsePoints
        $state=Get-FileState $dst
        if($state.exists -and $state.directory){throw "Promotion target is an existing directory, not a file: $rel"}
        if($state.exists -and -not $state.directory){
            $bak=Join-Path (Join-Path $BackupDir 'files') $rel
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $bak) | Out-Null
            Copy-Item -LiteralPath $dst -Destination $bak -Force
            if((Get-Sha256 $bak) -ne $state.sha256){throw "Backup hash mismatch: $rel"}
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

function Restore-TargetBackupEntries {
    param(
        [Parameter(Mandatory)]$Entries,
        [Parameter(Mandatory)][string]$MainCodexHome,
        [Parameter(Mandatory)][string]$BackupDir,
        [Parameter(Mandatory)][string[]]$Paths
    )
    $pathSet=@{}
    foreach($path in $Paths){$pathSet[$path.ToLowerInvariant()]=$true}
    $selected=@($Entries|Where-Object {$pathSet.ContainsKey(([string]$_.path).ToLowerInvariant())})
    $plan=New-Object System.Collections.Generic.List[object]
    $conflicts=New-Object System.Collections.Generic.List[string]

    foreach($entry in $selected){
        $rel=[string]$entry.path
        $dst=Resolve-CsgChildPath -Root $MainCodexHome -RelativePath $rel -RejectReparsePoints
        $now=Get-FileState $dst
        if([bool]$entry.existed_before){
            if($now.exists -and -not $now.directory -and [string]$now.sha256 -eq [string]$entry.before_sha256){
                $plan.Add([pscustomobject]@{entry=$entry;destination=$dst;action='none'})
            }elseif($now.exists -and -not $now.directory -and [string]$now.sha256 -eq [string]$entry.promoted_sha256){
                $plan.Add([pscustomobject]@{entry=$entry;destination=$dst;action='restore'})
            }else{
                $conflicts.Add($rel)
            }
        }else{
            if(-not $now.exists){
                $plan.Add([pscustomobject]@{entry=$entry;destination=$dst;action='none'})
            }elseif(-not $now.directory -and [string]$now.sha256 -eq [string]$entry.promoted_sha256){
                $plan.Add([pscustomobject]@{entry=$entry;destination=$dst;action='remove'})
            }else{
                $conflicts.Add($rel)
            }
        }
    }

    if($conflicts.Count){
        throw "Automatic recovery blocked because target files changed concurrently: $($conflicts -join ', ')"
    }

    foreach($item in $plan){
        if($item.action -eq 'none'){continue}
        $entry=$item.entry
        $rel=[string]$entry.path
        $dst=[string]$item.destination
        $now=Get-FileState $dst
        if(-not $now.exists -or $now.directory -or [string]$now.sha256 -ne [string]$entry.promoted_sha256){
            throw "Automatic recovery target changed after conflict check: $rel"
        }
        if($item.action -eq 'restore'){
            $filesRoot=Join-Path $BackupDir 'files'
            $bak=Resolve-CsgChildPath -Root $filesRoot -RelativePath $rel -RejectReparsePoints
            Copy-Item -LiteralPath $bak -Destination $dst -Force
            if((Get-Sha256 $dst) -ne [string]$entry.before_sha256){throw "Automatic recovery hash mismatch: $rel"}
        }else{
            Remove-Item -LiteralPath $dst -Force
        }
    }
}

function Invoke-SealedPromotion {
    param(
        [Parameter(Mandatory)][string]$StageId,
        [Parameter(Mandatory)][string]$Approval,
        [string]$MainCodexHome=(Join-Path $HOME '.codex'),
        [switch]$Apply
    )
    $null=Assert-CsgSafeId -Id $StageId -Kind 'Stage'
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

    $payload=Join-Path $sdir 'payload'
    if([IO.Path]::GetFullPath([string]$s.payload.path) -ne [IO.Path]::GetFullPath($payload)){
        throw 'Stage payload path does not match its CSG-controlled directory.'
    }
    Assert-NoReparsePoints -Root $payload
    $currentHash=Get-PayloadTreeHash $payload
    if($currentHash -ne $s.payload.tree_sha256){throw 'Sealed payload changed after approval challenge was generated.'}
    $payloadFiles=@(Get-ChildItem -LiteralPath $payload -Recurse -Force -File -ErrorAction Stop)
    foreach($f in $payloadFiles){
        $rel=(Get-RelativePathSafe -Base $payload -Full $f.FullName).Replace('/','\')
        $null=Assert-CsgPromotableCodexPath -RelativePath $rel
    }

    Write-Host "Promotion plan"
    Write-Host "  Stage: $StageId"
    Write-Host "  Artifact: $($s.artifact_id)"
    Write-Host "  Risk: $($s.risk_band)"
    Write-Host "  Payload: $currentHash"
    Write-Host "  Destination: $MainCodexHome"
    Write-Host "  Files: $($payloadFiles.Count)"
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
    $attempted=New-Object System.Collections.Generic.List[string]
    try {
        foreach($f in $payloadFiles){
            $rel=(Get-RelativePathSafe -Base $payload -Full $f.FullName).Replace('/','\')
            $null=Assert-CsgPromotableCodexPath -RelativePath $rel
            $dst=Resolve-CsgChildPath -Root $MainCodexHome -RelativePath $rel -RejectReparsePoints
            $backupEntry=@($backupEntries|Where-Object {$_.path -ieq $rel})
            if($backupEntry.Count -ne 1){throw "Backup manifest entry is missing or ambiguous: $rel"}
            $before=Get-FileState $dst
            if([bool]$backupEntry[0].existed_before -ne [bool]$before.exists -or ([bool]$before.exists -and [string]$backupEntry[0].before_sha256 -ne [string]$before.sha256)){
                throw "Promotion target changed after backup: $rel"
            }
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
            $attempted.Add($rel)
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
        if((Get-PayloadTreeHash $payload) -ne $currentHash){throw 'Sealed payload changed during promotion.'}

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
    } catch {
        $promotionError=$_.Exception.Message
        try {
            Restore-TargetBackupEntries -Entries $backupEntries -MainCodexHome $MainCodexHome -BackupDir $backup -Paths $attempted.ToArray()
        } catch {
            throw "Promotion failed: $promotionError Automatic recovery also failed: $($_.Exception.Message) Backup: $backup"
        }
        throw "Promotion failed and all attempted file changes were restored: $promotionError"
    }
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
    $null=Assert-CsgSafeId -Id $StageId -Kind 'Stage'
    $root=Initialize-CsgLayout
    $regPath=Join-Path (Join-Path $root 'registry') "$StageId.json"
    if(-not (Test-Path -LiteralPath $regPath)){throw "No registry record: $StageId"}
    $r=Read-JsonFile $regPath
    if($Confirmation -cne "ROLLBACK $StageId"){throw 'Rollback confirmation does not match exactly.'}
    $backupManifest=Read-JsonFile (Join-Path $r.backup 'backup-manifest.json')

    $conflicts=@()
    foreach($e in @($backupManifest.entries)){
        $dst=Resolve-CsgChildPath -Root $r.destination -RelativePath ([string]$e.path) -RejectReparsePoints
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
        $dst=Resolve-CsgChildPath -Root $r.destination -RelativePath ([string]$e.path) -RejectReparsePoints
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
