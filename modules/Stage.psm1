Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Artifact.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Inspect.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Toolchain.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Profiles.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Budget.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'RuntimeObserver.psm1') -Force

function Test-WindowsSandboxAvailable {
    $feature=$null
    try { $feature=Get-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM -ErrorAction Stop } catch {}
    $wsbCmd=Get-Command 'WindowsSandbox.exe' -ErrorAction SilentlyContinue
    $newCli=Get-Command 'wsb.exe' -ErrorAction SilentlyContinue
    $caption=$null
    try{$caption=(Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).Caption}catch{}
    $editionSupported=if($caption){$caption -notmatch '(?i)\bHome\b|家庭'}else{$null}
    $launcherPresent=([bool]$wsbCmd -or [bool]$newCli)
    $usable=($editionSupported -ne $false) -and $launcherPresent -and ($null -eq $feature -or $feature.State -eq 'Enabled')
    $reason=if($editionSupported -eq $false){"Windows Sandbox is not supported by this Windows edition: $caption"}
            elseif(-not $launcherPresent){'Windows Sandbox launcher was not found. The feature may be unavailable or disabled.'}
            elseif($feature -and $feature.State -ne 'Enabled'){"Windows Sandbox feature state is $($feature.State)."}
            else{$null}
    return [pscustomobject]@{
        windows_edition=$caption
        edition_supported=$editionSupported
        feature_state=if($feature){$feature.State}else{'unknown'}
        windows_sandbox_exe=[bool]$wsbCmd
        wsb_cli=[bool]$newCli
        usable=$usable
        reason=$reason
    }
}

function New-SandboxBootstrap {
    param(
        [Parameter(Mandatory)][string]$InstallCommand,
        [Parameter(Mandatory)][string]$ControlDir,
        [switch]$AllowNetwork
    )
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($InstallCommand))
    $networkLiteral=if($AllowNetwork){'$true'}else{'$false'}
    $script=@"
`$ErrorActionPreference='Stop'
`$ProgressPreference='SilentlyContinue'
`$out='C:\CSG\out'
`$work='C:\CSG\work'
New-Item -ItemType Directory -Force -Path `$out,`$work | Out-Null
Expand-Archive -LiteralPath 'C:\CSG\artifact\source.zip' -DestinationPath `$work -Force

`$env:HOME='C:\CSG\out\user'
`$env:USERPROFILE='C:\CSG\out\user'
`$env:CODEX_HOME='C:\CSG\out\codex-home'
`$env:CSG_TARGET_HOME=`$env:HOME
`$env:CSG_TARGET_CODEX_HOME=`$env:CODEX_HOME
`$env:CSG_SANDBOX='1'
New-Item -ItemType Directory -Force -Path `$env:HOME,`$env:CODEX_HOME | Out-Null

if(Test-Path -LiteralPath 'C:\CSG\toolchains\pwsh'){
  `$env:PATH='C:\CSG\toolchains\pwsh;' + `$env:PATH
}

`$cmd=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('$encoded'))
Set-Location `$work

`$status=[ordered]@{
  started_at=(Get-Date).ToString('o')
  command=`$cmd
  network_allowed=$networkLiteral
  exit_code=`$null
  completed=`$false
  error=`$null
}
try {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command `$cmd 1> 'C:\CSG\out\installer.stdout.txt' 2> 'C:\CSG\out\installer.stderr.txt'
  `$status.exit_code=[int]`$LASTEXITCODE
  `$status.completed=`$true
} catch {
  `$status.exit_code=1
  `$status.error=(`$_|Out-String)
} finally {
  `$status.finished_at=(Get-Date).ToString('o')
  `$status | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath 'C:\CSG\out\sandbox-result.json' -Encoding utf8
}
shutdown.exe /s /t 2
"@
    Set-Content -LiteralPath (Join-Path $ControlDir 'bootstrap.ps1') -Value $script -Encoding utf8
}

function New-WsbConfig {
    param(
        [Parameter(Mandatory)][string]$ArtifactDir,
        [Parameter(Mandatory)][string]$ControlDir,
        [Parameter(Mandatory)][string]$OutputDir,
        [Parameter(Mandatory)][string]$Path,
        [string]$PwshToolchainPath,
        [switch]$AllowNetwork
    )
    $network=if($AllowNetwork){'Enable'}else{'Disable'}
    $toolchainXml=''
    if($PwshToolchainPath){
        $toolchainXml=@"
    <MappedFolder>
      <HostFolder>$([Security.SecurityElement]::Escape($PwshToolchainPath))</HostFolder>
      <SandboxFolder>C:\CSG\toolchains\pwsh</SandboxFolder>
      <ReadOnly>true</ReadOnly>
    </MappedFolder>
"@
    }
    $xml=@"
<Configuration>
  <VGpu>Disable</VGpu>
  <Networking>$network</Networking>
  <AudioInput>Disable</AudioInput>
  <VideoInput>Disable</VideoInput>
  <PrinterRedirection>Disable</PrinterRedirection>
  <ClipboardRedirection>Disable</ClipboardRedirection>
  <ProtectedClient>Enable</ProtectedClient>
  <MappedFolders>
    <MappedFolder>
      <HostFolder>$([Security.SecurityElement]::Escape($ArtifactDir))</HostFolder>
      <SandboxFolder>C:\CSG\artifact</SandboxFolder>
      <ReadOnly>true</ReadOnly>
    </MappedFolder>
    <MappedFolder>
      <HostFolder>$([Security.SecurityElement]::Escape($ControlDir))</HostFolder>
      <SandboxFolder>C:\CSG\control</SandboxFolder>
      <ReadOnly>true</ReadOnly>
    </MappedFolder>
    <MappedFolder>
      <HostFolder>$([Security.SecurityElement]::Escape($OutputDir))</HostFolder>
      <SandboxFolder>C:\CSG\out</SandboxFolder>
      <ReadOnly>false</ReadOnly>
    </MappedFolder>
$toolchainXml
  </MappedFolders>
  <LogonCommand>
    <Command>powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\CSG\control\bootstrap.ps1</Command>
  </LogonCommand>
</Configuration>
"@
    Set-Content -LiteralPath $Path -Value $xml -Encoding utf8
}

function Merge-PromotablePayload {
    param([Parameter(Mandatory)][string]$OutputDir,[Parameter(Mandatory)][string]$PayloadDir)

    if(Test-Path -LiteralPath $PayloadDir){Remove-Item -LiteralPath $PayloadDir -Recurse -Force}
    New-Item -ItemType Directory -Force -Path $PayloadDir | Out-Null

    $sources=@(
        [pscustomobject]@{root=(Join-Path $OutputDir 'codex-home');label='CODEX_HOME'},
        [pscustomobject]@{root=(Join-Path (Join-Path $OutputDir 'user') '.codex');label='HOME\.codex'}
    )

    $seen=@{}
    $origins=@()
    foreach($s in $sources){
        if(-not (Test-Path -LiteralPath $s.root)){continue}
        Assert-NoReparsePoints -Root $s.root
        foreach($f in Get-ChildItem -LiteralPath $s.root -Recurse -Force -File){
            $rel=(Get-RelativePathSafe -Base $s.root -Full $f.FullName).Replace('/','\')
            $null=Assert-CsgPromotableCodexPath -RelativePath $rel
            $key=$rel.ToLowerInvariant()
            $hash=Get-Sha256 $f.FullName
            if($seen.ContainsKey($key) -and $seen[$key] -ne $hash){
                throw "Conflicting staged outputs for '$rel' between CODEX_HOME and HOME\.codex."
            }
            $seen[$key]=$hash
            $dst=Join-Path $PayloadDir $rel
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
            Copy-Item -LiteralPath $f.FullName -Destination $dst -Force
            $origins += [pscustomobject]@{path=$rel;source=$s.label;sha256=$hash}
        }
    }
    return @($origins)
}

function Invoke-SandboxStage {
    param(
        [Parameter(Mandatory)][string]$ArtifactId,
        [Parameter(Mandatory)][string]$InstallCommand,
        [switch]$AllowNetwork
    )
    $root=Initialize-CsgLayout
    $artifact=Get-FrozenArtifact $ArtifactId
    $inspection=Invoke-ArtifactInspection $ArtifactId
    $profile=Get-AddonProfile $ArtifactId
    $runtimeBudget=Get-CsgRuntimeBudget -ArtifactId $ArtifactId -Profile $profile.profile

    if($inspection.risk_band -eq 'RED'){throw 'RED artifact cannot be staged without changing policy. Review source first.'}

    $available=Test-WindowsSandboxAvailable
    if(-not $available.usable){throw 'Windows Sandbox is not available/enabled on this system. CSG V2 refuses to silently fall back to local execution.'}

    $sid=New-Id 'stage'
    $sdir=Join-Path (Join-Path $root 'stages') $sid
    $control=Join-Path $sdir 'control'
    $outDir=Join-Path $sdir 'sandbox-output'
    $payload=Join-Path $sdir 'payload'
    foreach($p in @($sdir,$control,$outDir)){New-Item -ItemType Directory -Force -Path $p|Out-Null}

    New-SandboxBootstrap -InstallCommand $InstallCommand -ControlDir $control -AllowNetwork:$AllowNetwork
    $wsb=Join-Path $sdir 'stage.wsb'
    $pwshToolchain=Get-PwshToolchain
    $pwshPath=if($pwshToolchain){[string]$pwshToolchain.payload}else{$null}
    New-WsbConfig -ArtifactDir $artifact.dir -ControlDir $control -OutputDir $outDir -Path $wsb -PwshToolchainPath $pwshPath -AllowNetwork:$AllowNetwork

    $pre=[ordered]@{
        schema_version=2;stage_id=$sid;artifact_id=$ArtifactId;created_at=(Get-Date).ToString('o')
        state='prepared';risk_band=$inspection.risk_band;allow_network=[bool]$AllowNetwork
        install_command=$InstallCommand
        profile=$profile.profile
        runtime_budget=$runtimeBudget
        sandbox=$available
        toolchains=[ordered]@{pwsh=if($pwshToolchain){[ordered]@{version=$pwshToolchain.version;tree_sha256=$pwshToolchain.tree_sha256}}else{$null}}
        wsb_config=$wsb
        note='Open the generated .wsb. CSG will not promote until sandbox-result.json exists and payload is sealed.'
    }
    Write-JsonFile $pre (Join-Path $sdir 'stage.json')

    Start-Process -FilePath $wsb
    Write-Host "Windows Sandbox launched."
    Write-Host "StageId: $sid"
    Write-Host "After the sandbox closes, run:"
    Write-Host "  csg.ps1 seal -StageId $sid"
    return $pre
}

function Seal-SandboxStage {
    param([Parameter(Mandatory)][string]$StageId)
    $null=Assert-CsgSafeId -Id $StageId -Kind 'Stage'
    $root=Initialize-CsgLayout
    $sdir=Join-Path (Join-Path $root 'stages') $StageId
    Assert-NoReparsePoints -Root $sdir
    $stagePath=Join-Path $sdir 'stage.json'
    if(-not (Test-Path -LiteralPath $stagePath)){throw "Unknown StageId: $StageId"}
    $stage=Read-JsonFile $stagePath
    $outDir=Join-Path $sdir 'sandbox-output'
    $resultPath=Join-Path $outDir 'sandbox-result.json'
    if(-not (Test-Path -LiteralPath $resultPath)){throw 'Sandbox result not found. The sandbox may still be running or bootstrap failed.'}
    $result=Read-JsonFile $resultPath
    if(-not $result.completed -or $result.exit_code -ne 0){throw "Sandbox installer failed (exit=$($result.exit_code)). Review sandbox-output logs."}

    $payload=Join-Path $sdir 'payload'
    $origins=Merge-PromotablePayload -OutputDir $outDir -PayloadDir $payload
    if(@($origins).Count -eq 0){throw 'No promotable Codex payload was produced.'}

    $treeHash=Get-PayloadTreeHash $payload
    $snapshot=Get-TreeSnapshot $payload
    $inspection=Invoke-ArtifactInspection $stage.artifact_id
    $runtimeBudget=if($stage.runtime_budget){$stage.runtime_budget}else{
        $profile=Get-AddonProfile $stage.artifact_id
        Get-CsgRuntimeBudget -ArtifactId $stage.artifact_id -Profile $profile.profile
    }
    $runtimeObserver=if([bool]$runtimeBudget.requires_budget){
        [ordered]@{
            status='not-collected'
            promotion_eligible=$false
            blocker='CSG-controlled process telemetry and isolated credential evidence were not collected.'
        }
    }else{
        [ordered]@{status='not-required';promotion_eligible=$true;blocker=$null}
    }

    $capabilities=@()
    foreach($x in $snapshot){
        $p=$x.path.ToLowerInvariant()
        if($p -eq 'config.toml' -or $p -eq 'auth.json' -or $p -eq 'models_cache.json'){$capabilities+='codex.config_write'}
        elseif($p -eq 'agents.md'){$capabilities+='codex.global_agents_write'}
        elseif($p.StartsWith('skills\')){$capabilities+='codex.skill_install'}
        else{$capabilities+='codex.other_write'}
    }
    $capabilities=@($capabilities|Sort-Object -Unique)
    $staticCaps=@($inspection.capabilities)
    $surprises=@($capabilities|Where-Object {$_ -notin $staticCaps -and $_ -ne 'codex.skill_install'})
    $capManifest=[ordered]@{
        schema_version=2;stage_id=$StageId
        static_capabilities=$staticCaps
        observed_capabilities=$capabilities
        capability_surprises=$surprises
        note='Observed capabilities come from promotable output paths. Full runtime telemetry is not yet implemented.'
    }
    Write-JsonFile $capManifest (Join-Path $sdir 'capability-manifest.json')

    $challenge="APPROVE $StageId $($treeHash.Substring(0,12))"
    $sealed=[ordered]@{
        schema_version=2;stage_id=$StageId;artifact_id=$stage.artifact_id
        sealed_at=(Get-Date).ToString('o');state='sealed'
        risk_band=$stage.risk_band;allow_network=$stage.allow_network
        install_command=$stage.install_command
        payload=[ordered]@{
            path=$payload;tree_sha256=$treeHash;files=@($snapshot);origins=@($origins)
        }
        static_capabilities=$staticCaps
        observed_capabilities=$capabilities
        capability_surprises=$surprises
        capability_manifest=(Join-Path $sdir 'capability-manifest.json')
        runtime_budget=$runtimeBudget
        runtime_observer=$runtimeObserver
        approval_challenge=$challenge
        non_promotable_outputs=@(
            Get-ChildItem -LiteralPath $outDir -Force -File -ErrorAction SilentlyContinue |
            Where-Object {$_.Name -notin @('sandbox-result.json','installer.stdout.txt','installer.stderr.txt')} |
            Select-Object -ExpandProperty Name
        )
        invariant='Promotion copies only this sealed payload. The third-party installer is never executed on the host during promotion.'
    }
    Write-JsonFile $sealed $stagePath
    Write-Host "Stage sealed."
    Write-Host "Payload SHA256: $treeHash"
    Write-Host "Approval challenge:"
    Write-Host "  $challenge"
    return $sealed
}

Export-ModuleMember -Function *
