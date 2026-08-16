Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -Force

function Get-CsgTextSha256 {
    param([Parameter(Mandatory)][string]$Text)
    $sha=[Security.Cryptography.SHA256]::Create()
    try{
        $bytes=[Text.Encoding]::UTF8.GetBytes($Text)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()
    }finally{$sha.Dispose()}
}

function New-CsgRuntimeObserverPlan {
    param(
        [Parameter(Mandatory)][string]$ArtifactId,
        [Parameter(Mandatory)]$Budget,
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][string]$OutputDir,
        [string]$TaskName='csg-runtime-budget-check'
    )

    New-Item -ItemType Directory -Force -Path $OutputDir|Out-Null
    $promptPath=Join-Path $OutputDir 'observer-prompt.txt'
    Set-Content -LiteralPath $promptPath -Value $Prompt -Encoding utf8NoBOM
    $budgetJson=$Budget|ConvertTo-Json -Depth 20 -Compress
    $observerId=New-Id 'observer'
    $plan=[ordered]@{
        schema_version=1
        observer_id=$observerId
        created_at=(Get-Date).ToString('o')
        artifact_id=$ArtifactId
        task_name=$TaskName
        prompt=[ordered]@{
            path='observer-prompt.txt'
            sha256=(Get-Sha256 $promptPath)
        }
        budget_contract_sha256=(Get-CsgTextSha256 $budgetJson)
        command=[ordered]@{
            executable='codex'
            arguments=@('exec','--json','--ephemeral','--ignore-user-config','--sandbox','read-only','--skip-git-repo-check','-')
            stdin='observer-prompt.txt'
            stdout='codex-events.jsonl'
            stderr='codex-stderr.txt'
        }
        authentication=[ordered]@{
            isolated_codex_home_required=$true
            real_codex_home_mapping_forbidden=$true
            note='Authentication must use an explicitly provisioned isolated credential. Never map the real auth.json or OS credential store into the test environment.'
        }
        trust_boundary=[ordered]@{
            controller_owns_command=$true
            addon_summary_is_not_trusted=$true
            raw_jsonl_required=$true
            process_telemetry_required_for_promotion=$true
        }
    }
    $planPath=Join-Path $OutputDir 'observer-plan.json'
    Write-JsonFile $plan $planPath
    return [pscustomobject]@{
        observer_id=$observerId
        plan_path=$planPath
        plan_sha256=(Get-Sha256 $planPath)
        prompt_path=$promptPath
        command=$plan.command
    }
}

function Add-CsgUsageSamples {
    param($Value,[System.Collections.Generic.List[object]]$Samples,[int]$Depth=0)
    if($null -eq $Value -or $Depth -gt 24){return}

    if($Value -is [string] -or $Value -is [ValueType]){return}
    if($Value -is [Collections.IEnumerable] -and $Value -isnot [Collections.IDictionary] -and $Value -isnot [pscustomobject]){
        foreach($item in $Value){Add-CsgUsageSamples -Value $item -Samples $Samples -Depth ($Depth+1)}
        return
    }

    $properties=@{}
    if($Value -is [Collections.IDictionary]){
        foreach($key in $Value.Keys){$properties[[string]$key]=$Value[$key]}
    }else{
        foreach($property in $Value.PSObject.Properties){$properties[$property.Name]=$property.Value}
    }

    $recognized=@('input_tokens','prompt_tokens','output_tokens','completion_tokens','reasoning_tokens','reasoning_output_tokens','cached_input_tokens','cached_tokens','total_tokens')
    if(@($properties.Keys|Where-Object {$_ -in $recognized}).Count){
        $sample=[ordered]@{}
        foreach($name in $recognized){if($properties.ContainsKey($name)){$sample[$name]=$properties[$name]}}
        $Samples.Add([pscustomobject]$sample)
    }
    foreach($child in $properties.Values){Add-CsgUsageSamples -Value $child -Samples $Samples -Depth ($Depth+1)}
}

function Get-CsgMaxMetric {
    param([object[]]$Samples,[string[]]$Names)
    $values=New-Object System.Collections.Generic.List[long]
    foreach($sample in @($Samples)){
        foreach($name in $Names){
            $property=$sample.PSObject.Properties[$name]
            if($property -and $null -ne $property.Value){
                $number=0L
                if([long]::TryParse([string]$property.Value,[ref]$number) -and $number -ge 0){$values.Add($number)}
            }
        }
    }
    if(-not $values.Count){return $null}
    return [long](($values|Measure-Object -Maximum).Maximum)
}

function Measure-CsgCodexJsonl {
    param([Parameter(Mandatory)][string]$Path)
    if(-not (Test-Path -LiteralPath $Path)){throw "Codex JSONL not found: $Path"}

    $events=New-Object System.Collections.Generic.List[object]
    $types=@{}
    $lineNumber=0
    foreach($line in Get-Content -LiteralPath $Path -Encoding utf8){
        $lineNumber++
        if([string]::IsNullOrWhiteSpace($line)){continue}
        try{$event=$line|ConvertFrom-Json -Depth 100}catch{throw "Invalid Codex JSONL at line ${lineNumber}: $($_.Exception.Message)"}
        $events.Add($event)
        $typeProperty=$event.PSObject.Properties['type']
        $type=if($typeProperty){[string]$typeProperty.Value}else{'(missing)'}
        if(-not $types.ContainsKey($type)){$types[$type]=0}
        $types[$type]++
    }
    if(-not $events.Count){throw 'Codex JSONL contains no events.'}

    $samples=New-Object System.Collections.Generic.List[object]
    foreach($event in $events){Add-CsgUsageSamples -Value $event -Samples $samples}
    $typeRows=@($types.Keys|Sort-Object|ForEach-Object {[pscustomobject]@{type=$_;count=$types[$_]}})
    return [pscustomobject]@{
        schema_version=1
        event_count=$events.Count
        event_types=$typeRows
        completed_event_count=@($types.Keys|Where-Object {$_ -match '(?i)(turn|task|thread)\.completed$|completed$'}|ForEach-Object {$types[$_]}|Measure-Object -Sum).Sum
        usage_sample_count=$samples.Count
        usage=[pscustomobject]@{
            input_tokens=Get-CsgMaxMetric $samples @('input_tokens','prompt_tokens')
            output_tokens=Get-CsgMaxMetric $samples @('output_tokens','completion_tokens')
            reasoning_tokens=Get-CsgMaxMetric $samples @('reasoning_tokens','reasoning_output_tokens')
            cached_input_tokens=Get-CsgMaxMetric $samples @('cached_input_tokens','cached_tokens')
            total_tokens=Get-CsgMaxMetric $samples @('total_tokens')
        }
        accounting_mode='max-reported-snapshot'
        exact_token_total=$false
        agent_process_count=$null
        exact_agent_telemetry=$false
        note='Codex JSONL is parsed independently. Until event semantics and process telemetry are pinned, token values are conservative reported snapshots rather than an exact cross-agent total.'
    }
}

function New-CsgRuntimeObserverReceipt {
    param(
        [Parameter(Mandatory)][string]$PlanPath,
        [Parameter(Mandatory)][string]$JsonlPath,
        [Parameter(Mandatory)][int]$ExitCode,
        [Parameter(Mandatory)][bool]$QualityGatePassed,
        [string]$Path
    )
    $plan=Read-JsonFile $PlanPath
    $measurement=Measure-CsgCodexJsonl $JsonlPath
    $receipt=[ordered]@{
        schema_version=1
        observer_id=$plan.observer_id
        created_at=(Get-Date).ToString('o')
        source='csg-controller'
        plan=[ordered]@{path=$PlanPath;sha256=(Get-Sha256 $PlanPath)}
        raw_jsonl=[ordered]@{path=$JsonlPath;sha256=(Get-Sha256 $JsonlPath)}
        exit_code=$ExitCode
        quality_gate_passed=$QualityGatePassed
        measurement=$measurement
        integrity=[ordered]@{
            controller_command_expected=$true
            raw_event_hash_bound=$true
            process_telemetry_complete=$false
            credential_isolation_verified=$false
        }
        promotion_eligible=$false
        blocker='Process-level Agent telemetry and isolated credential provisioning are not yet verified.'
    }
    if($Path){Write-JsonFile $receipt $Path}
    return [pscustomobject]$receipt
}

function Test-CsgRuntimeObserverReceipt {
    param([Parameter(Mandatory)]$Receipt)
    $violations=New-Object System.Collections.Generic.List[string]
    if([string]$Receipt.source -ne 'csg-controller'){$violations.Add('Observer source is not csg-controller.')}
    $planValid=(Test-Path -LiteralPath ([string]$Receipt.plan.path)) -and (Get-Sha256 $Receipt.plan.path) -eq [string]$Receipt.plan.sha256
    if(-not $planValid){$violations.Add('Observer plan hash mismatch.')}
    if($planValid){
        $plan=Read-JsonFile $Receipt.plan.path
        $promptPath=Join-Path (Split-Path -Parent ([string]$Receipt.plan.path)) ([string]$plan.prompt.path)
        if(-not (Test-Path -LiteralPath $promptPath) -or (Get-Sha256 $promptPath) -ne [string]$plan.prompt.sha256){$violations.Add('Observer prompt hash mismatch.')}
    }
    if(-not (Test-Path -LiteralPath ([string]$Receipt.raw_jsonl.path)) -or (Get-Sha256 $Receipt.raw_jsonl.path) -ne [string]$Receipt.raw_jsonl.sha256){$violations.Add('Raw Codex JSONL hash mismatch.')}
    if([int]$Receipt.exit_code -ne 0){$violations.Add("Codex observer command exited with $($Receipt.exit_code).")}
    if(-not [bool]$Receipt.quality_gate_passed){$violations.Add('Quality gate did not pass.')}
    if(-not [bool]$Receipt.integrity.raw_event_hash_bound){$violations.Add('Raw event stream is not hash-bound.')}
    if(-not [bool]$Receipt.integrity.process_telemetry_complete){$violations.Add('Process-level Agent telemetry is incomplete.')}
    if(-not [bool]$Receipt.integrity.credential_isolation_verified){$violations.Add('Credential isolation is unverified.')}
    $valid=@($violations|Where-Object {$_ -match 'hash mismatch|source|exited|Quality|not hash-bound'}).Count -eq 0
    return [pscustomobject]@{
        evidence_valid=$valid
        promotion_eligible=($valid -and $violations.Count -eq 0 -and [bool]$Receipt.promotion_eligible)
        violations=$violations.ToArray()
        status=if(-not $valid){'invalid'}elseif($violations.Count){'partial'}else{'verified'}
    }
}

Export-ModuleMember -Function New-CsgRuntimeObserverPlan,Measure-CsgCodexJsonl,New-CsgRuntimeObserverReceipt,Test-CsgRuntimeObserverReceipt
