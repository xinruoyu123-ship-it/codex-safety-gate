Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -Force

function Get-CsgNotebookPath {
    $docs=[Environment]::GetFolderPath('MyDocuments')
    if([string]::IsNullOrWhiteSpace($docs)){$docs=$HOME}
    $dir=Join-Path $docs 'Codex Safety'
    New-Item -ItemType Directory -Force -Path $dir|Out-Null
    return (Join-Path $dir '扩展安全笔记.md')
}

function Update-CsgNotebook {
    param([string]$Path)
    $root=Initialize-CsgLayout
    if([string]::IsNullOrWhiteSpace($Path)){$Path=Get-CsgNotebookPath}
    $parent=Split-Path -Parent $Path
    if($parent){New-Item -ItemType Directory -Force -Path $parent|Out-Null}
    $lines=New-Object System.Collections.Generic.List[string]
    $lines.Add('# Codex 第三方扩展安全笔记')
    $lines.Add('')
    $lines.Add("> 由 Codex Safety Gate 自动生成。最后更新：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    $lines.Add('')
    $lines.Add('## 我的默认规则')
    $lines.Add('')
    $lines.Add('- Windows-only：所有方案以 Windows 11 / PowerShell 7 / Windows Sandbox 为基准。')
    $lines.Add('- 新扩展先冻结版本，再审计，再进入 Windows Sandbox。')
    $lines.Add('- 默认断网；确实需要网络时单独批准。')
    $lines.Add('- 主 `.codex` 永远不执行第三方 installer。')
    $lines.Add('- 正式安装只复制已 seal 且哈希固定的产物。')
    $lines.Add('- Proxy / Model Gateway / Shim / Service 不走普通 Skill 的快速通道。')
    $lines.Add('- 更新版本如果新增 capability，必须重新审批。')
    $lines.Add('')
    $lines.Add('## 已接入/审批扩展')
    $lines.Add('')

    $records=@(Get-ChildItem -LiteralPath (Join-Path $root 'registry') -Filter '*.json' -File -ErrorAction SilentlyContinue)
    if(-not $records){
        $lines.Add('_暂无正式接入记录。_')
    } else {
        foreach($f in $records|Sort-Object LastWriteTime -Descending){
            $r=Read-JsonFile $f.FullName
            $lines.Add("### $($r.addon_id)")
            $lines.Add('')
            $lines.Add("- 状态：**$($r.status)**")
            $lines.Add("- 风险：**$($r.risk_band)**")
            $lines.Add(('- Artifact：`{0}`' -f $r.artifact_id))
            $lines.Add("- 安装时间：$($r.promoted_at)")
            $lines.Add(('- Payload SHA256：`{0}`' -f $r.payload_sha256))
            if(@($r.capability_surprises).Count){
                $lines.Add("- ⚠ Capability surprises：$(@($r.capability_surprises) -join ', ')")
            }
            $lines.Add(('- 回滚：`ROLLBACK {0}`' -f $r.addon_id))
            $lines.Add('')
        }
    }

    $lines.Add('## 工作流')
    $lines.Add('')
    $lines.Add('```text')
    $lines.Add('粘贴 GitHub 链接')
    $lines.Add('      ↓')
    $lines.Add('自动冻结版本 + 审计')
    $lines.Add('      ↓')
    $lines.Add('显示：类型 / 风险 / 会改什么 / 是否联网')
    $lines.Add('      ↓')
    $lines.Add('Windows Sandbox 安全测试')
    $lines.Add('      ↓')
    $lines.Add('生成 Seal + SHA256')
    $lines.Add('      ↓')
    $lines.Add('我点击“批准安装”')
    $lines.Add('      ↓')
    $lines.Add('CSG 复制验证后的文件')
    $lines.Add('```')
    $lines.Add('')
    $lines.Add('## 说明')
    $lines.Add('')
    $lines.Add('这份笔记是给人看的长期台账；真正的机器可验证记录仍保存在 `~/.codex-safety-v2/registry/`。')

    $lines|Set-Content -LiteralPath $Path -Encoding utf8
    return $Path
}

Export-ModuleMember -Function *
