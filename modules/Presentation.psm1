function Get-CsgRiskPresentation {
    param([Parameter(Mandatory)][string]$RiskBand)

    switch($RiskBand.ToUpperInvariant()){
        'GREEN'  {return [pscustomobject]@{label='低影响';summary='未发现高影响能力';color='2E7D32'}}
        'YELLOW' {return [pscustomobject]@{label='需要注意';summary='存在可理解、可审批的影响';color='B26A00'}}
        'ORANGE' {return [pscustomobject]@{label='高影响';summary='会影响 Codex 配置、连接或系统环境';color='C2410C'}}
        'RED'    {return [pscustomobject]@{label='已阻止';summary='发现默认禁止的高风险能力';color='B91C1C'}}
        default  {return [pscustomobject]@{label='尚未确认';summary='证据不足，不能自动放行';color='5F6368'}}
    }
}

function Get-CsgProfileLabel {
    param([string]$Profile)
    switch($Profile){
        'skill'         {'普通 Skill'}
        'agent-router'  {'Agent Router / Token 工具'}
        'mcp'           {'MCP / 工具服务'}
        'proxy-gateway' {'Proxy / Model Gateway'}
        default         {'未知扩展'}
    }
}

function Test-CsgCapability {
    param([string[]]$Capabilities,[string[]]$AnyOf)
    return [bool](@($Capabilities|Where-Object {$_ -in $AnyOf}).Count)
}

function New-CsgPermissionRow {
    param([string]$Name,[string]$Result,[string]$Detail,[ValidateSet('ok','notice','danger','unknown')][string]$Level='ok')
    return [pscustomobject]@{name=$Name;result=$Result;detail=$Detail;level=$Level}
}

function Get-CsgPermissionCard {
    param(
        [Parameter(Mandatory)]$Inspection,
        [Parameter(Mandatory)]$Profile,
        $Budget=$null,
        [switch]$NetworkRequested
    )

    $caps=@($Inspection.capabilities)
    $risk=Get-CsgRiskPresentation ([string]$Inspection.risk_band)
    $profileName=[string]$Profile.profile
    $profileLabel=Get-CsgProfileLabel $profileName
    $rows=New-Object System.Collections.Generic.List[object]

    $writeDetails=New-Object System.Collections.Generic.List[string]
    if(Test-CsgCapability $caps @('codex.config_write')){$writeDetails.Add('Codex 模型或连接配置')}
    if(Test-CsgCapability $caps @('codex.global_agents_write')){$writeDetails.Add('全局 AGENTS.md 规则')}
    if(Test-CsgCapability $caps @('codex.skill_install')){$writeDetails.Add('Codex Skills 目录')}
    if(Test-CsgCapability $caps @('codex.other_write')){$writeDetails.Add('其他 Codex 文件')}
    if($writeDetails.Count){
        $rows.Add((New-CsgPermissionRow '修改 Codex' '会' ($writeDetails -join '；') 'notice'))
    }else{
        $rows.Add((New-CsgPermissionRow '修改 Codex' '未发现' '静态审计未发现 Codex 写入' 'ok'))
    }

    $spawns=Test-CsgCapability $caps @('process.spawn','process.dynamic_code')
    if($spawns -or $profileName -eq 'agent-router'){
        $rows.Add((New-CsgPermissionRow '启动进程' '会' '可能启动 codex exec 或其他子进程' 'notice'))
    }else{
        $rows.Add((New-CsgPermissionRow '启动进程' '未发现' '静态审计未发现子进程启动' 'ok'))
    }

    $networkCap=Test-CsgCapability $caps @('network.outbound','network.local_proxy')
    if($NetworkRequested){
        $rows.Add((New-CsgPermissionRow 'Sandbox 联网' '本次申请' '只对本次隔离测试开放网络' 'notice'))
    }elseif($networkCap){
        $rows.Add((New-CsgPermissionRow 'Sandbox 联网' '默认拒绝' '代码包含联网能力；需要单独批准' 'notice'))
    }else{
        $rows.Add((New-CsgPermissionRow 'Sandbox 联网' '不需要' '本次测试保持断网' 'ok'))
    }

    if(Test-CsgCapability $caps @('os.persistence')){
        $rows.Add((New-CsgPermissionRow '系统常驻' '会' '检测到服务或计划任务行为' 'danger'))
    }else{$rows.Add((New-CsgPermissionRow '系统常驻' '未发现' '未发现服务或计划任务' 'ok'))}

    if(Test-CsgCapability $caps @('os.elevation')){
        $rows.Add((New-CsgPermissionRow '管理员权限' '需要' '检测到提权行为' 'danger'))
    }else{$rows.Add((New-CsgPermissionRow '管理员权限' '不需要' '未发现提权行为' 'ok'))}

    if(Test-CsgCapability $caps @('secrets.access')){
        $rows.Add((New-CsgPermissionRow '凭据访问' '会' '检测到凭据或浏览器秘密访问' 'danger'))
    }else{$rows.Add((New-CsgPermissionRow '凭据访问' '未发现' '未发现凭据读取' 'ok'))}

    if(Test-CsgCapability $caps @('privacy.prompt_artifacts')){
        $rows.Add((New-CsgPermissionRow 'Prompt / 输出落盘' '会' '可能保存 prompt、stdout 或结果文件' 'notice'))
    }else{$rows.Add((New-CsgPermissionRow 'Prompt / 输出落盘' '未发现' '未发现已知 Prompt 落盘模式' 'ok'))}

    if($profileName -eq 'agent-router' -and $Budget -and $Budget.status -eq 'declared-unverified'){
        $limit=$Budget.limits
        $detail="子 Agent ≤ $($limit.max_children)；并发 ≤ $($limit.max_concurrent)；深度 ≤ $($limit.max_depth)；Sol ≤ $($limit.max_sol_calls)；单任务重试 ≤ $($limit.max_retry_per_task)"
        $rows.Add((New-CsgPermissionRow 'Agent / Token 预算' '声明待验证' ($detail+'；正式安装仍被门禁阻止') 'notice'))
    }elseif($profileName -eq 'agent-router' -and $Budget -and $Budget.status -eq 'missing'){
        $rows.Add((New-CsgPermissionRow 'Agent / Token 预算' '缺失' '允许 Sandbox 观察；预算补齐前禁止正式安装' 'danger'))
    }elseif($profileName -eq 'agent-router' -and $Budget){
        $rows.Add((New-CsgPermissionRow 'Agent / Token 预算' '不合规' ($Budget.violations -join '；') 'danger'))
    }elseif($profileName -eq 'proxy-gateway'){
        $rows.Add((New-CsgPermissionRow 'Agent / Token 预算' '尚未确认' '必须进入 Proxy 专用 Profile 评估' 'unknown'))
    }elseif($profileName -eq 'unknown'){
        $rows.Add((New-CsgPermissionRow 'Agent / Token 预算' '未知' '无法从当前证据判断' 'unknown'))
    }else{
        $rows.Add((New-CsgPermissionRow 'Agent / Token 预算' '不适用' '未发现自动派生 Agent 的行为' 'ok'))
    }

    $headline=switch($profileName){
        'skill' {'安装一项经过审计的 Codex Skill'}
        'agent-router' {'会改变 Agent 行为，并可能增加调用成本'}
        'mcp' {'会连接新的工具或服务能力'}
        'proxy-gateway' {'会进入模型连接链，不能走普通安装通道'}
        default {'扩展类型尚未确认，不能自动安装'}
    }

    $budgetSandboxAllowed=if($Budget){[bool]$Budget.sandbox_allowed}else{$true}
    $budgetPromotionAllowed=if($Budget){[bool]$Budget.promotion_allowed}else{$true}
    $blocked=([string]$Inspection.risk_band -eq 'RED') -or -not [bool]$Profile.automatic -or $profileName -eq 'proxy-gateway' -or -not $budgetSandboxAllowed
    $decision=if([string]$Inspection.risk_band -eq 'RED'){'已阻止：需要先移除高风险能力。'}
              elseif($profileName -eq 'proxy-gateway'){'需要 Proxy / Model Gateway 专用 Profile。'}
              elseif(-not [bool]$Profile.automatic){'需要专用安装 Profile 或人工审核。'}
              elseif($Budget -and $Budget.status -eq 'missing'){'可以进入 Sandbox；正式安装前必须提供预算声明。'}
              elseif($Budget -and $Budget.status -eq 'declared-unverified'){'可以进入 Sandbox；运行预算验证器完成前禁止正式安装。'}
              elseif($Budget -and -not $budgetSandboxAllowed){'预算声明不合规，自动流程已阻止。'}
              else{'可以进入 Windows Sandbox 安全测试。'}

    return [pscustomobject]@{
        risk_code=[string]$Inspection.risk_band
        risk_label=$risk.label
        risk_summary=$risk.summary
        risk_color=$risk.color
        profile=$profileName
        profile_label=$profileLabel
        headline=$headline
        decision=$decision
        action_allowed=(-not $blocked)
        promotion_allowed=((-not $blocked) -and $budgetPromotionAllowed)
        budget_status=if($Budget){$Budget.status}else{'not-evaluated'}
        rows=$rows.ToArray()
    }
}

function Format-CsgPermissionCard {
    param([Parameter(Mandatory)]$Card)
    $lines=New-Object System.Collections.Generic.List[string]
    $lines.Add("$($Card.risk_label) · $($Card.profile_label)")
    $lines.Add($Card.headline)
    $lines.Add('')
    foreach($row in @($Card.rows)){
        $lines.Add(('{0,-18} {1}' -f $row.name,$row.result))
        $lines.Add(('  {0}' -f $row.detail))
    }
    $lines.Add('')
    $lines.Add("结论：$($Card.decision)")
    return ($lines -join "`r`n")
}

Export-ModuleMember -Function Get-CsgRiskPresentation,Get-CsgProfileLabel,Get-CsgPermissionCard,Format-CsgPermissionCard
