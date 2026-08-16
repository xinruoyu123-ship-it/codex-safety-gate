Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Artifact.psm1') -Force

function Get-CsgBudgetPolicy {
    $policyPath=Join-Path (Split-Path -Parent $PSScriptRoot) 'policy.default.json'
    $policy=Read-JsonFile $policyPath
    return $policy.runtime_budget
}

function Get-CsgRuntimeBudget {
    param(
        [Parameter(Mandatory)][string]$ArtifactId,
        [Parameter(Mandatory)][string]$Profile
    )

    $requiresBudget=$Profile -eq 'agent-router'
    $policy=Get-CsgBudgetPolicy
    if(-not $requiresBudget){
        return [pscustomobject]@{
            status='not-applicable';requires_budget=$false;declared=$false
            sandbox_allowed=$true;promotion_allowed=$true;violations=@()
            limits=$null;source=$null
            summary='该类型不要求 Agent Runtime Budget。'
        }
    }

    $root=Initialize-CsgLayout
    $tmp=Join-Path (Join-Path $root 'tmp') (New-Id 'budget')
    $null=Expand-FrozenArtifact -ArtifactId $ArtifactId -Destination $tmp
    try{
        $files=@(Get-ChildItem -LiteralPath $tmp -Recurse -Force -File -Filter 'csg-budget.json')
        if($files.Count -ne 1){
            $why=if($files.Count -eq 0){'未找到 csg-budget.json。'}else{'发现多个 csg-budget.json，声明来源不唯一。'}
            return [pscustomobject]@{
                status='missing';requires_budget=$true;declared=$false
                sandbox_allowed=$true;promotion_allowed=$false;violations=@($why)
                limits=$null;source=$null
                summary='可以进入 Sandbox 观察，但正式安装被预算门禁阻止。'
            }
        }

        try{$manifest=Read-JsonFile $files[0].FullName}catch{
            return [pscustomobject]@{
                status='invalid';requires_budget=$true;declared=$true
                sandbox_allowed=$false;promotion_allowed=$false
                violations=@("预算声明无法解析：$($_.Exception.Message)")
                limits=$null;source=(Get-RelativePathSafe -Base $tmp -Full $files[0].FullName)
                summary='预算声明无效，不能进入自动流程。'
            }
        }

        $violations=New-Object System.Collections.Generic.List[string]
        if([int]$manifest.schema_version -ne 1){$violations.Add('schema_version 必须为 1。')}
        if([string]$manifest.enforcement -ne 'runtime'){$violations.Add('enforcement 必须为 runtime，只有文档承诺不算执行约束。')}

        $requiredLimits=@('max_children','max_concurrent','max_depth','max_sol_calls','max_retry_per_task')
        foreach($name in $requiredLimits){
            $value=$manifest.limits.$name
            $ceiling=$policy.limits.$name
            if($null -eq $value -or [int]$value -lt 0){
                $violations.Add("$name 必须是非负整数。")
            }elseif([int]$value -gt [int]$ceiling){
                $violations.Add("$name=$value 超过 CSG 上限 $ceiling。")
            }
        }

        $tiers=@($manifest.allowed_model_tiers)
        if(-not $tiers.Count){$violations.Add('allowed_model_tiers 不能为空。')}
        foreach($tier in $tiers){
            if([string]$tier -notin @($policy.allowed_model_tiers)){
                $violations.Add("模型层级 '$tier' 不在允许列表中。")
            }
        }
        if([bool]$policy.require_quality_gate -and -not [bool]$manifest.benchmark.require_quality_gate){
            $violations.Add('benchmark.require_quality_gate 必须为 true；不能以失败率换取低 Token。')
        }
        foreach($metric in @($policy.required_metrics)){
            if([string]$metric -notin @($manifest.benchmark.metrics)){
                $violations.Add("benchmark.metrics 缺少 '$metric'。")
            }
        }

        $ok=$violations.Count -eq 0
        return [pscustomobject]@{
            status=if($ok){'declared-unverified'}else{'exceeds-policy'}
            requires_budget=$true;declared=$true
            contract_compliant=$ok
            sandbox_allowed=$ok;promotion_allowed=$false
            violations=$violations.ToArray()
            limits=$manifest.limits
            allowed_model_tiers=$tiers
            benchmark=$manifest.benchmark
            source=(Get-RelativePathSafe -Base $tmp -Full $files[0].FullName)
            summary=if($ok){'预算声明完整且未超过默认上限；运行时执行尚未由 CSG 验证，因此禁止正式安装。'}else{'预算声明违反 CSG 默认策略，自动流程已阻止。'}
        }
    }finally{
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Export-ModuleMember -Function Get-CsgBudgetPolicy,Get-CsgRuntimeBudget
