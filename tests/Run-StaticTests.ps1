#requires -Version 7.0
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$repo=Split-Path -Parent $PSScriptRoot
$modules=Join-Path $repo 'modules'
Import-Module (Join-Path $modules 'Common.psm1') -Force
Import-Module (Join-Path $modules 'Artifact.psm1') -Force
Import-Module (Join-Path $modules 'Inspect.psm1') -Force
Import-Module (Join-Path $modules 'Profiles.psm1') -Force
Import-Module (Join-Path $modules 'Promote.psm1') -Force
Import-Module (Join-Path $modules 'Notebook.psm1') -Force
Import-Module (Join-Path $modules 'Presentation.psm1') -Force
Import-Module (Join-Path $modules 'Budget.psm1') -Force
Import-Module (Join-Path $modules 'RuntimeObserver.psm1') -Force

$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('csg-alpha-tests-'+[guid]::NewGuid().ToString('N'))
$oldCsgHome=$env:CSG_HOME
$results=New-Object System.Collections.Generic.List[object]

function Assert-Csg {
    param([bool]$Condition,[string]$Name,[string]$Evidence)
    if(-not $Condition){throw "FAIL: $Name -- $Evidence"}
    $script:results.Add([pscustomobject]@{test=$Name;status='PASS';evidence=$Evidence})
}

function Assert-Throws {
    param([scriptblock]$Action,[string]$Name,[string]$Pattern='')
    $message=$null
    try{& $Action}catch{$message=$_.Exception.Message}
    if($null -eq $message){throw "FAIL: $Name -- expected an exception"}
    if($Pattern -and $message -notmatch $Pattern){throw "FAIL: $Name -- unexpected exception: $message"}
    $script:results.Add([pscustomobject]@{test=$Name;status='PASS';evidence=$message})
}

try {
    New-Item -ItemType Directory -Force -Path $testRoot|Out-Null
    $env:CSG_HOME=Join-Path $testRoot 'state'
    Initialize-CsgLayout|Out-Null

    $parseErrors=@()
    $runtimeRoot=[IO.Path]::GetFullPath((Join-Path $repo 'runtime')).TrimEnd('\')+'\'
    foreach($file in Get-ChildItem -LiteralPath $repo -Recurse -File|Where-Object {$_.Extension -in @('.ps1','.psm1') -and -not $_.FullName.StartsWith($runtimeRoot,[StringComparison]::OrdinalIgnoreCase)}){
        $tokens=$null;$errors=$null
        $content=Get-Content -LiteralPath $file.FullName -Raw -Encoding utf8
        [Management.Automation.Language.Parser]::ParseInput($content,$file.FullName,[ref]$tokens,[ref]$errors)|Out-Null
        $parseErrors+=@($errors)
    }
    Assert-Csg ($parseErrors.Count -eq 0) 'PowerShell syntax' "$($parseErrors.Count) parser errors"

    foreach($json in Get-ChildItem -LiteralPath $repo -Recurse -File -Filter '*.json'|Where-Object {-not $_.FullName.StartsWith($runtimeRoot,[StringComparison]::OrdinalIgnoreCase) -or $_.Name -eq 'manifest.json'}){
        Get-Content -LiteralPath $json.FullName -Raw -Encoding utf8|ConvertFrom-Json|Out-Null
    }
    Assert-Csg $true 'JSON syntax' 'all CSG-authored JSON files parsed'

    $githubUrls=@(
        @{url='https://github.com/octocat/Hello-World';owner='octocat';repo='Hello-World';reference=$null;candidate=$null}
        @{url='https://github.com/octocat/Hello-World/releases/tag/v1.0';owner='octocat';repo='Hello-World';reference='v1.0';candidate=$null}
        @{url='https://github.com/octocat/Hello-World/tree/main';owner='octocat';repo='Hello-World';reference=$null;candidate='main'}
        @{url='https://github.com/octocat/Hello-World/blob/main/README.md';owner='octocat';repo='Hello-World';reference=$null;candidate='main/README.md'}
        @{url='https://github.com/octocat/Hello-World/raw/main/README.md';owner='octocat';repo='Hello-World';reference=$null;candidate='main/README.md'}
        @{url='https://raw.githubusercontent.com/octocat/Hello-World/main/README.md';owner='octocat';repo='Hello-World';reference=$null;candidate='main/README.md'}
    )
    foreach($case in $githubUrls){
        $parsed=Split-GitHubSourceUrl -Source $case.url
        $ok=($null -ne $parsed) -and $parsed.owner -eq $case.owner -and $parsed.repo -eq $case.repo -and $parsed.reference -eq $case.reference -and $parsed.candidate -eq $case.candidate
        Assert-Csg $ok 'GitHub URL parsing' $case.url
    }
    Assert-Csg ($null -eq (Split-GitHubSourceUrl -Source 'https://gist.github.com/octocat/example')) 'GitHub URL rejection' 'unsupported gist URL rejected'

    $runtimeManifest=Get-Content -LiteralPath (Join-Path $repo 'runtime\manifest.json') -Raw -Encoding utf8|ConvertFrom-Json
    $runtimeExe=Join-Path $repo ('runtime\'+$runtimeManifest.executable)
    if(Test-Path -LiteralPath $runtimeExe){
        Assert-Csg ((Get-Sha256 $runtimeExe) -eq $runtimeManifest.executable_sha256) 'Bundled PowerShell integrity' $runtimeManifest.executable_sha256
    }else{
        $results.Add([pscustomobject]@{test='Bundled PowerShell integrity';status='SKIP';evidence='runtime/pwsh is intentionally excluded from source checkout; release-package verification is required before publishing.'})
    }

    $plain=New-FrozenArtifact -Source (Join-Path $PSScriptRoot 'fixtures\plain-skill')
    $plainInspection=Invoke-ArtifactInspection -ArtifactId $plain.artifact_id
    $plainProfile=Get-AddonProfile -ArtifactId $plain.artifact_id
    Assert-Csg ($plainInspection.risk_band -eq 'YELLOW') 'Plain skill risk' $plainInspection.risk_band
    Assert-Csg ($plainProfile.profile -eq 'skill' -and $plainProfile.automatic) 'Plain skill profile' "$($plainProfile.profile), automatic=$($plainProfile.automatic)"
    Assert-Csg ($plainProfile.install_command -match 'Get-ChildItem -LiteralPath' -and $plainProfile.install_command -match 'skills\\demo-skill') 'Safe skill recipe' $plainProfile.install_command
    $plainCard=Get-CsgPermissionCard -Inspection $plainInspection -Profile $plainProfile
    Assert-Csg ($plainCard.action_allowed -and $plainCard.profile_label -eq '普通 Skill') 'Plain skill permission card' $plainCard.decision

    $router=New-FrozenArtifact -Source (Join-Path $PSScriptRoot 'fixtures\agent-router')
    $routerInspection=Invoke-ArtifactInspection -ArtifactId $router.artifact_id
    $routerProfile=Get-AddonProfile -ArtifactId $router.artifact_id
    $routerBudget=Get-CsgRuntimeBudget -ArtifactId $router.artifact_id -Profile $routerProfile.profile
    Assert-Csg ($routerInspection.risk_band -eq 'YELLOW') 'Agent router risk' $routerInspection.risk_band
    Assert-Csg ($routerProfile.profile -eq 'agent-router' -and $routerProfile.automatic) 'Agent router profile' "$($routerProfile.profile), automatic=$($routerProfile.automatic)"
    Assert-Csg ($routerBudget.status -eq 'declared-unverified' -and $routerBudget.contract_compliant -and -not $routerBudget.promotion_allowed) 'Agent budget declaration gate' $routerBudget.summary
    $routerCard=Get-CsgPermissionCard -Inspection $routerInspection -Profile $routerProfile -Budget $routerBudget
    Assert-Csg (@($routerCard.rows|Where-Object {$_.name -eq 'Agent / Token 预算' -and $_.result -eq '声明待验证'}).Count -eq 1) 'Agent budget card' $routerCard.headline

    $missingSource=Join-Path $testRoot 'router-without-budget'
    New-Item -ItemType Directory -Force -Path $missingSource|Out-Null
    Set-Content -LiteralPath (Join-Path $missingSource 'AGENTS.md') -Value 'Run codex exec once; do not recursively delegate.' -Encoding utf8
    $missingArtifact=New-FrozenArtifact -Source $missingSource
    $missingBudget=Get-CsgRuntimeBudget -ArtifactId $missingArtifact.artifact_id -Profile 'agent-router'
    Assert-Csg ($missingBudget.sandbox_allowed -and -not $missingBudget.promotion_allowed) 'Missing budget promotion gate' $missingBudget.summary

    $overSource=Join-Path $testRoot 'router-over-budget'
    New-Item -ItemType Directory -Force -Path $overSource|Out-Null
    Set-Content -LiteralPath (Join-Path $overSource 'AGENTS.md') -Value 'Run codex exec with delegated sub-agents.' -Encoding utf8
    $overBudget=@{
        schema_version=1;enforcement='runtime'
        limits=@{max_children=99;max_concurrent=9;max_depth=5;max_sol_calls=9;max_retry_per_task=9}
        allowed_model_tiers=@('luna','terra','sol')
        benchmark=@{require_quality_gate=$true;metrics=@('input_tokens','output_tokens','reasoning_tokens','agent_count','call_count','retry_count','success','latency_ms')}
    }
    Write-JsonFile $overBudget (Join-Path $overSource 'csg-budget.json')
    $overArtifact=New-FrozenArtifact -Source $overSource
    $overResult=Get-CsgRuntimeBudget -ArtifactId $overArtifact.artifact_id -Profile 'agent-router'
    Assert-Csg (-not $overResult.sandbox_allowed -and @($overResult.violations).Count -ge 5) 'Over-budget block' ($overResult.violations -join '; ')

    $observerDir=Join-Path $testRoot 'observer'
    $observerPlan=New-CsgRuntimeObserverPlan -ArtifactId $router.artifact_id -Budget $routerBudget -Prompt 'Return exactly: fixture result' -OutputDir $observerDir
    Assert-Csg ((Get-Content -LiteralPath $observerPlan.plan_path -Raw|ConvertFrom-Json).command.arguments -contains '--ephemeral') 'Observer controlled plan' $observerPlan.plan_sha256
    $observerJsonl=Join-Path $observerDir 'codex-events.jsonl'
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'fixtures\codex-events.jsonl') -Destination $observerJsonl
    $observerReceipt=New-CsgRuntimeObserverReceipt -PlanPath $observerPlan.plan_path -JsonlPath $observerJsonl -ExitCode 0 -QualityGatePassed $true
    $observerCheck=Test-CsgRuntimeObserverReceipt $observerReceipt
    Assert-Csg ($observerCheck.evidence_valid -and -not $observerCheck.promotion_eligible -and $observerReceipt.measurement.usage.input_tokens -eq 120) 'Observer partial evidence' ($observerCheck.violations -join '; ')
    Set-Content -LiteralPath $observerPlan.prompt_path -Value 'mutated prompt' -Encoding utf8NoBOM
    $promptTamperedCheck=Test-CsgRuntimeObserverReceipt $observerReceipt
    Assert-Csg (-not $promptTamperedCheck.evidence_valid) 'Observer prompt tamper detection' ($promptTamperedCheck.violations -join '; ')
    Add-Content -LiteralPath $observerJsonl -Value '{"type":"tampered"}' -Encoding utf8
    $tamperedCheck=Test-CsgRuntimeObserverReceipt $observerReceipt
    Assert-Csg (-not $tamperedCheck.evidence_valid -and $tamperedCheck.status -eq 'invalid') 'Observer raw tamper detection' ($tamperedCheck.violations -join '; ')

    $proxy=New-FrozenArtifact -Source (Join-Path $PSScriptRoot 'fixtures\fake-proxy')
    $proxyInspection=Invoke-ArtifactInspection -ArtifactId $proxy.artifact_id
    $proxyProfile=Get-AddonProfile -ArtifactId $proxy.artifact_id
    Assert-Csg ($proxyInspection.risk_band -in @('ORANGE','RED')) 'Proxy risk gate' $proxyInspection.risk_band
    Assert-Csg ($proxyProfile.profile -eq 'proxy-gateway' -and -not $proxyProfile.automatic) 'Proxy generic-install block' "$($proxyProfile.profile), automatic=$($proxyProfile.automatic)"
    $proxyCard=Get-CsgPermissionCard -Inspection $proxyInspection -Profile $proxyProfile
    Assert-Csg (-not $proxyCard.action_allowed -and $proxyCard.decision -match '专用 Profile') 'Proxy permission card block' $proxyCard.decision

    Assert-Throws {New-FrozenArtifact -Source $testRoot|Out-Null} 'Recursive local-source guard' 'contains the CSG artifact destination'

    $mutable=Join-Path $testRoot 'mutable-source'
    Copy-Tree -Source (Join-Path $PSScriptRoot 'fixtures\plain-skill') -Destination $mutable
    $frozen=New-FrozenArtifact -Source $mutable
    Set-Content -LiteralPath (Join-Path $mutable 'demo-skill\SKILL.md') -Value 'openai_base_url = http://127.0.0.1:9999/v1' -Encoding utf8
    $afterMutation=Invoke-ArtifactInspection -ArtifactId $frozen.artifact_id
    Assert-Csg ('codex.config_write' -notin @($afterMutation.capabilities)) 'Freeze isolation' 'source mutation did not affect frozen inspection'

    $artifact=Get-FrozenArtifact $frozen.artifact_id
    $stream=[IO.File]::Open($artifact.zip,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try{$stream.Position=0;$first=$stream.ReadByte();$stream.Position=0;$stream.WriteByte(($first -bxor 0xff))}finally{$stream.Dispose()}
    Assert-Throws {Get-FrozenArtifact $frozen.artifact_id|Out-Null} 'Frozen archive tamper detection' 'hash mismatch'

    $notebook=Join-Path $testRoot 'notebook\扩展安全笔记.md'
    Update-CsgNotebook -Path $notebook|Out-Null
    Assert-Csg (Test-Path -LiteralPath $notebook) 'Notebook generation' $notebook

    $stageId='stage-test-'+[guid]::NewGuid().ToString('N').Substring(0,8)
    $stageDir=Join-Path (Join-Path $env:CSG_HOME 'stages') $stageId
    $payload=Join-Path $stageDir 'payload'
    $payloadFile=Join-Path $payload 'skills\promotion-fixture\SKILL.md'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $payloadFile)|Out-Null
    Set-Content -LiteralPath $payloadFile -Value '# Promotion fixture' -Encoding utf8
    $treeHash=Get-PayloadTreeHash $payload
    $approval="APPROVE $stageId $($treeHash.Substring(0,12))"
    $stage=[ordered]@{
        schema_version=2;stage_id=$stageId;artifact_id='local-test';state='sealed';risk_band='YELLOW'
        approval_challenge=$approval;capability_surprises=@()
        payload=[ordered]@{path=$payload;tree_sha256=$treeHash;files=@(Get-TreeSnapshot $payload)}
    }
    Write-JsonFile $stage (Join-Path $stageDir 'stage.json')
    $main=Join-Path $testRoot 'main-codex'
    Invoke-SealedPromotion -StageId $stageId -Approval $approval -MainCodexHome $main
    Assert-Csg (-not (Test-Path -LiteralPath $main)) 'Promotion dry run' 'destination was not created'
    Assert-Throws {Invoke-SealedPromotion -StageId $stageId -Approval 'WRONG' -MainCodexHome $main -Apply} 'Approval binding' 'does not match'

    $budgetBlockedId='stage-budget-'+[guid]::NewGuid().ToString('N').Substring(0,8)
    $budgetBlockedDir=Join-Path (Join-Path $env:CSG_HOME 'stages') $budgetBlockedId
    New-Item -ItemType Directory -Force -Path $budgetBlockedDir|Out-Null
    $budgetApproval="APPROVE $budgetBlockedId $($treeHash.Substring(0,12))"
    $budgetBlocked=[ordered]@{
        schema_version=2;stage_id=$budgetBlockedId;artifact_id='agent-router-test';state='sealed';risk_band='YELLOW'
        approval_challenge=$budgetApproval;capability_surprises=@()
        runtime_budget=[ordered]@{requires_budget=$true;promotion_allowed=$false;summary='runtime enforcement unverified'}
        payload=[ordered]@{path=$payload;tree_sha256=$treeHash;files=@(Get-TreeSnapshot $payload)}
    }
    Write-JsonFile $budgetBlocked (Join-Path $budgetBlockedDir 'stage.json')
    Assert-Throws {Invoke-SealedPromotion -StageId $budgetBlockedId -Approval $budgetApproval -MainCodexHome $main} 'CLI budget bypass protection' 'Runtime budget gate blocked promotion'

    $observerBlockedId='stage-observer-'+[guid]::NewGuid().ToString('N').Substring(0,8)
    $observerBlockedDir=Join-Path (Join-Path $env:CSG_HOME 'stages') $observerBlockedId
    New-Item -ItemType Directory -Force -Path $observerBlockedDir|Out-Null
    $observerApproval="APPROVE $observerBlockedId $($treeHash.Substring(0,12))"
    $observerBlocked=[ordered]@{
        schema_version=2;stage_id=$observerBlockedId;artifact_id='agent-router-test';state='sealed';risk_band='YELLOW'
        approval_challenge=$observerApproval;capability_surprises=@()
        runtime_budget=[ordered]@{requires_budget=$true;promotion_allowed=$true;summary='test-only budget pass'}
        runtime_observer=[ordered]@{promotion_eligible=$false;blocker='process telemetry incomplete'}
        payload=[ordered]@{path=$payload;tree_sha256=$treeHash;files=@(Get-TreeSnapshot $payload)}
    }
    Write-JsonFile $observerBlocked (Join-Path $observerBlockedDir 'stage.json')
    Assert-Throws {Invoke-SealedPromotion -StageId $observerBlockedId -Approval $observerApproval -MainCodexHome $main} 'CLI observer bypass protection' 'Runtime observer gate blocked promotion'

    Invoke-SealedPromotion -StageId $stageId -Approval $approval -MainCodexHome $main -Apply
    $promoted=Join-Path $main 'skills\promotion-fixture\SKILL.md'
    Assert-Csg ((Get-Sha256 $promoted) -eq (Get-Sha256 $payloadFile)) 'Copy-only promotion' 'source and destination hashes match'
    Assert-Throws {Invoke-SealedPromotion -StageId $stageId -Approval $approval -MainCodexHome $main -Apply} 'Promotion replay protection' 'already has a registry record'
    Set-Content -LiteralPath $promoted -Value '# User changed this after promotion' -Encoding utf8
    Assert-Throws {Invoke-CsgRollback -StageId $stageId -Confirmation "ROLLBACK $stageId" -Apply} 'Rollback conflict protection' 'conflict|changed'
    Copy-Item -LiteralPath $payloadFile -Destination $promoted -Force
    Invoke-CsgRollback -StageId $stageId -Confirmation "ROLLBACK $stageId" -Apply
    Assert-Csg (-not (Test-Path -LiteralPath $promoted)) 'Rollback apply' 'newly promoted file removed after hash check'

    $results|Format-Table -AutoSize
    Write-Host "PASS: $($results.Count) tests"
} finally {
    if($null -eq $oldCsgHome){Remove-Item Env:CSG_HOME -ErrorAction SilentlyContinue}else{$env:CSG_HOME=$oldCsgHome}
    $resolved=[IO.Path]::GetFullPath($testRoot)
    $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if($resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolved).StartsWith('csg-alpha-tests-')){
        Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
    }
}
