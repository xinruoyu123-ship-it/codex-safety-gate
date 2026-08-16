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
Import-Module (Join-Path $modules 'Stage.psm1') -Force -DisableNameChecking

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

function New-CsgTestZip {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Entries)
    $archive=[IO.Compression.ZipFile]::Open($Path,[IO.Compression.ZipArchiveMode]::Create)
    try{
        foreach($spec in $Entries){
            $entry=$archive.CreateEntry([string]$spec.name)
            $stream=$entry.Open()
            try{
                $bytes=[Text.Encoding]::UTF8.GetBytes([string]$spec.content)
                $stream.Write($bytes,0,$bytes.Length)
            }finally{$stream.Dispose()}
        }
    }finally{$archive.Dispose()}
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

    Assert-Throws {Get-RelativePathSafe -Base (Join-Path $testRoot 'inside') -Full (Join-Path $testRoot 'outside.txt')|Out-Null} 'Path containment' 'outside the allowed root'
    Assert-Throws {Resolve-CsgChildPath -Root $testRoot -RelativePath '..\escape.txt'|Out-Null} 'Relative traversal rejection' 'outside the allowed root'
    Assert-Throws {Assert-CsgSafeId -Id '..\outside' -Kind 'Artifact'|Out-Null} 'Identifier traversal rejection' 'unsafe path characters'

    $treeOne=Join-Path $testRoot 'tree-order-one'
    $treeTwo=Join-Path $testRoot 'tree-order-two'
    New-Item -ItemType Directory -Force -Path $treeOne,$treeTwo|Out-Null
    Set-Content -LiteralPath (Join-Path $treeOne '中.txt') -Value 'same' -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $treeOne 'a.txt') -Value 'same' -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $treeTwo 'a.txt') -Value 'same' -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join-Path $treeTwo '中.txt') -Value 'same' -Encoding utf8NoBOM
    Assert-Csg ((Get-PayloadTreeHash $treeOne) -eq (Get-PayloadTreeHash $treeTwo)) 'Unicode tree-hash stability' 'creation order does not affect canonical hash'
    foreach($protectedPath in @('auth.json','auth.json.backup','session_index.jsonl','sessions\2026\rollout.jsonl','archived_sessions\old.jsonl','.sandbox-secrets\fixture','state_5.sqlite','config.toml','AGENTS.md')){
        Assert-Csg (Test-CsgProtectedCodexPath $protectedPath) 'Protected Codex path gate' $protectedPath
    }
    Assert-Csg (Test-CsgPromotableCodexPath 'skills\demo-skill\SKILL.md') 'Skill path allowed' 'reviewed isolated skill payload remains promotable'
    Assert-Csg (-not (Test-CsgPromotableCodexPath 'plugins\demo\plugin.json')) 'Unsupported surface blocked' 'generic promotion is limited to isolated skills'
    $policy=Get-Content -LiteralPath (Join-Path $repo 'policy.default.json') -Raw -Encoding utf8|ConvertFrom-Json
    Assert-Csg ($policy.generic_promotion_destination -eq 'skills/<name>/**') 'Promotion policy consistency' $policy.generic_promotion_destination

    $limitRoot=Join-Path $testRoot 'limit-check'
    New-Item -ItemType Directory -Force -Path $limitRoot|Out-Null
    [IO.File]::WriteAllBytes((Join-Path $limitRoot 'one.txt'),[byte[]](1,2,3))
    [IO.File]::WriteAllBytes((Join-Path $limitRoot 'two.txt'),[byte[]](4,5,6))
    $tinyLimits=[pscustomobject]@{max_files=1;max_total_bytes=1024;max_single_file_bytes=1024;max_relative_path_chars=100}
    Assert-Throws {Assert-CsgContentLimits -Root $limitRoot -Limits $tinyLimits|Out-Null} 'Artifact file-count limit' 'limit is 1'
    Assert-Throws {Assert-CsgContentLimits -Root $limitRoot -Limits ([pscustomobject]@{max_files=10;max_total_bytes=1024;max_single_file_bytes=2;max_relative_path_chars=100})|Out-Null} 'Artifact single-file limit' 'single-file limit'
    Assert-Throws {Assert-CsgContentLimits -Root $limitRoot -Limits ([pscustomobject]@{max_files=10;max_total_bytes=5;max_single_file_bytes=10;max_relative_path_chars=100})|Out-Null} 'Artifact total-size limit' 'expanded size'
    Assert-Throws {Assert-CsgContentLimits -Root $limitRoot -Limits ([pscustomobject]@{max_files=10;max_total_bytes=1024;max_single_file_bytes=1024;max_relative_path_chars=6})|Out-Null} 'Artifact path-length limit' 'path exceeds'

    $safeZip=Join-Path $testRoot 'limits.zip'
    New-CsgTestZip -Path $safeZip -Entries @(
        [pscustomobject]@{name='a.txt';content='abc'},
        [pscustomobject]@{name='b.txt';content='def'}
    )
    Assert-Throws {Test-CsgZipArchive -Path $safeZip -Limits ([pscustomobject]@{max_files=1;max_total_bytes=1024;max_single_file_bytes=1024;max_relative_path_chars=100})|Out-Null} 'Archive file-count limit' 'file count'
    Assert-Throws {Test-CsgZipArchive -Path $safeZip -Limits ([pscustomobject]@{max_files=10;max_total_bytes=1024;max_single_file_bytes=2;max_relative_path_chars=100})|Out-Null} 'Archive single-file limit' 'single-file limit'
    Assert-Throws {Test-CsgZipArchive -Path $safeZip -Limits ([pscustomobject]@{max_files=10;max_total_bytes=5;max_single_file_bytes=10;max_relative_path_chars=100})|Out-Null} 'Archive total-size limit' 'expanded size'
    Assert-Throws {Test-CsgZipArchive -Path $safeZip -Limits ([pscustomobject]@{max_files=10;max_total_bytes=1024;max_single_file_bytes=1024;max_relative_path_chars=4})|Out-Null} 'Archive path-length limit' 'path exceeds'

    $duplicateZip=Join-Path $testRoot 'duplicate.zip'
    New-CsgTestZip -Path $duplicateZip -Entries @(
        [pscustomobject]@{name='same.txt';content='one'},
        [pscustomobject]@{name='SAME.txt';content='two'}
    )
    Assert-Throws {Test-CsgZipArchive -Path $duplicateZip -Limits (Get-CsgArtifactLimits)|Out-Null} 'Archive duplicate-path rejection' 'duplicate path'

    $unsafeZip=Join-Path $testRoot 'unsafe.zip'
    New-CsgTestZip -Path $unsafeZip -Entries @([pscustomobject]@{name='../escape.txt';content='fixture'})
    Assert-Throws {Test-CsgZipArchive -Path $unsafeZip -Limits (Get-CsgArtifactLimits)|Out-Null} 'Archive traversal rejection' 'escapes the artifact root'

    $reparseRoot=Join-Path $testRoot 'reparse-check'
    $reparseSource=Join-Path $reparseRoot 'source'
    $reparseTarget=Join-Path $reparseRoot 'target'
    New-Item -ItemType Directory -Force -Path $reparseSource,$reparseTarget|Out-Null
    $junction=Join-Path $reparseSource 'escape'
    try{
        New-Item -ItemType Junction -Path $junction -Target $reparseTarget|Out-Null
        Assert-Throws {Assert-NoReparsePoints -Root $reparseSource} 'Reparse point rejection' 'Reparse point is not allowed'
    }finally{
        if(Test-Path -LiteralPath $junction){Remove-Item -LiteralPath $junction -Force}
    }

    $protectedOut=Join-Path $testRoot 'protected-output'
    $protectedAuth=Join-Path $protectedOut 'codex-home\auth.json'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $protectedAuth)|Out-Null
    Set-Content -LiteralPath $protectedAuth -Value '{"token":"fixture"}' -Encoding utf8
    Assert-Throws {Merge-PromotablePayload -OutputDir $protectedOut -PayloadDir (Join-Path $testRoot 'protected-payload')|Out-Null} 'Protected Sandbox output gate' 'protected Codex path'

    $unsupportedOut=Join-Path $testRoot 'unsupported-output'
    $unsupportedFile=Join-Path $unsupportedOut 'codex-home\plugins\demo\plugin.json'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $unsupportedFile)|Out-Null
    Set-Content -LiteralPath $unsupportedFile -Value '{}' -Encoding utf8
    Assert-Throws {Merge-PromotablePayload -OutputDir $unsupportedOut -PayloadDir (Join-Path $testRoot 'unsupported-payload')|Out-Null} 'Generic surface allowlist' 'only isolated skills'

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

    $git=(Get-Command git -ErrorAction Stop).Source
    $gitSource=Join-Path $testRoot 'git-ref-source'
    $gitRemote=Join-Path $testRoot 'git-ref-remote.git'
    & $git init -q $gitSource
    & $git -C $gitSource config user.name 'CSG test'
    & $git -C $gitSource config user.email 'csg-test@localhost'
    Set-Content -LiteralPath (Join-Path $gitSource 'README.md') -Value 'fixture' -Encoding utf8
    & $git -C $gitSource add README.md
    & $git -C $gitSource commit -q -m fixture
    & $git -C $gitSource branch 'feature/foo'
    & $git clone -q --bare $gitSource $gitRemote
    $resolvedRef=Resolve-GitHubRef -RepositoryUrl $gitRemote -Candidate 'feature/foo/path/file.md' -Git $git
    Assert-Csg ($resolvedRef -eq 'feature/foo') 'GitHub slash-ref resolution' $resolvedRef
    Assert-Throws {Resolve-GitHubRef -RepositoryUrl $gitRemote -Candidate 'missing/path/file.md' -Git $git|Out-Null} 'GitHub ambiguous-ref rejection' '无法可靠识别'

    $runtimeManifest=Get-Content -LiteralPath (Join-Path $repo 'runtime\manifest.json') -Raw -Encoding utf8|ConvertFrom-Json
    $runtimeExe=Join-Path $repo ('runtime\'+$runtimeManifest.executable)
    $runtimeSourceValid=([string]$runtimeManifest.source.url -match '^https://github\.com/PowerShell/PowerShell/releases/download/v[0-9.]+/PowerShell-[0-9.]+-win-x64\.zip$') -and
        ([string]$runtimeManifest.source.archive_sha256 -match '^[0-9a-f]{64}$') -and
        ([string]$runtimeManifest.runtime_tree_sha256 -match '^[0-9a-f]{64}$')
    Assert-Csg $runtimeSourceValid 'Bundled PowerShell provenance' $runtimeManifest.source.archive_sha256
    if(Test-Path -LiteralPath $runtimeExe){
        Assert-Csg ((Get-Sha256 $runtimeExe) -eq $runtimeManifest.executable_sha256) 'Bundled PowerShell integrity' $runtimeManifest.executable_sha256
        $runtimeRoot=Split-Path -Parent $runtimeExe
        $runtimeRows=@(Get-TreeSnapshot $runtimeRoot)
        $runtimeBytes=($runtimeRows|Measure-Object -Property size -Sum).Sum
        $runtimeTreeValid=$runtimeRows.Count -eq [int]$runtimeManifest.file_count -and
            [long]$runtimeBytes -eq [long]$runtimeManifest.total_bytes -and
            (Get-PayloadTreeHash $runtimeRoot) -eq [string]$runtimeManifest.runtime_tree_sha256
        Assert-Csg $runtimeTreeValid 'Bundled PowerShell tree integrity' "$($runtimeRows.Count) files; $runtimeBytes bytes; $($runtimeManifest.runtime_tree_sha256)"
    }else{
        $results.Add([pscustomobject]@{test='Bundled PowerShell integrity';status='SKIP';evidence='runtime/pwsh is intentionally excluded from source checkout; release-package verification is required before publishing.'})
        $results.Add([pscustomobject]@{test='Bundled PowerShell tree integrity';status='SKIP';evidence='runtime/pwsh is intentionally excluded from source checkout; release-package verification is required before publishing.'})
    }

    $plain=New-FrozenArtifact -Source (Join-Path $PSScriptRoot 'fixtures\plain-skill')
    Assert-Throws {Expand-FrozenArtifact -ArtifactId $plain.artifact_id -Destination (Join-Path $testRoot 'outside-csg-tmp')|Out-Null} 'Frozen expansion boundary' 'outside the allowed root'
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

    $pathStageId='stage-path-'+[guid]::NewGuid().ToString('N').Substring(0,8)
    $pathStageDir=Join-Path (Join-Path $env:CSG_HOME 'stages') $pathStageId
    New-Item -ItemType Directory -Force -Path $pathStageDir|Out-Null
    $pathApproval="APPROVE $pathStageId $($treeHash.Substring(0,12))"
    $pathStage=[ordered]@{
        schema_version=2;stage_id=$pathStageId;artifact_id='local-test';state='sealed';risk_band='YELLOW'
        approval_challenge=$pathApproval;capability_surprises=@()
        payload=[ordered]@{path=$payload;tree_sha256=$treeHash;files=@(Get-TreeSnapshot $payload)}
    }
    Write-JsonFile $pathStage (Join-Path $pathStageDir 'stage.json')
    Assert-Throws {Invoke-SealedPromotion -StageId $pathStageId -Approval $pathApproval -MainCodexHome $main} 'Stage payload redirect rejection' 'does not match its CSG-controlled directory'

    $recoveryPayload=Join-Path $testRoot 'recovery-payload'
    $recoveryMain=Join-Path $testRoot 'recovery-main'
    $recoveryBackup=Join-Path $testRoot 'recovery-backup'
    $existingPayload=Join-Path $recoveryPayload 'skills\existing\SKILL.md'
    $newPayload=Join-Path $recoveryPayload 'skills\new\SKILL.md'
    $existingTarget=Join-Path $recoveryMain 'skills\existing\SKILL.md'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $existingPayload),(Split-Path -Parent $newPayload),(Split-Path -Parent $existingTarget)|Out-Null
    Set-Content -LiteralPath $existingPayload -Value 'promoted existing' -Encoding utf8
    Set-Content -LiteralPath $newPayload -Value 'promoted new' -Encoding utf8
    Set-Content -LiteralPath $existingTarget -Value 'original existing' -Encoding utf8
    $recoveryEntries=New-TargetBackup -Payload $recoveryPayload -MainCodexHome $recoveryMain -BackupDir $recoveryBackup
    Copy-Item -LiteralPath $existingPayload -Destination $existingTarget -Force
    $newTarget=Join-Path $recoveryMain 'skills\new\SKILL.md'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $newTarget)|Out-Null
    Copy-Item -LiteralPath $newPayload -Destination $newTarget -Force
    Restore-TargetBackupEntries -Entries $recoveryEntries -MainCodexHome $recoveryMain -BackupDir $recoveryBackup -Paths @('skills\existing\SKILL.md','skills\new\SKILL.md')
    Assert-Csg ((Get-Content -LiteralPath $existingTarget -Raw).Trim() -eq 'original existing' -and -not (Test-Path -LiteralPath $newTarget)) 'Promotion automatic recovery' 'existing file restored and newly added file removed'

    Copy-Item -LiteralPath $existingPayload -Destination $existingTarget -Force
    Copy-Item -LiteralPath $newPayload -Destination $newTarget -Force
    Set-Content -LiteralPath $existingTarget -Value 'concurrent existing edit' -Encoding utf8
    Set-Content -LiteralPath $newTarget -Value 'concurrent new edit' -Encoding utf8
    Assert-Throws {Restore-TargetBackupEntries -Entries $recoveryEntries -MainCodexHome $recoveryMain -BackupDir $recoveryBackup -Paths @('skills\existing\SKILL.md','skills\new\SKILL.md')} 'Automatic recovery conflict protection' 'changed concurrently'
    Assert-Csg ((Get-Content -LiteralPath $existingTarget -Raw).Trim() -eq 'concurrent existing edit' -and (Get-Content -LiteralPath $newTarget -Raw).Trim() -eq 'concurrent new edit') 'Automatic recovery conflict atomicity' 'no target changed after conflict detection'

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
