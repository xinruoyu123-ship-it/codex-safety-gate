#requires -Version 7.0
[CmdletBinding()]
param([switch]$SmokeTest,[string]$SmokeSource)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference='Stop'
$base=$PSScriptRoot
$modules=Join-Path $base 'modules'
Import-Module (Join-Path $modules 'Common.psm1') -Force
Import-Module (Join-Path $modules 'Artifact.psm1') -Force
Import-Module (Join-Path $modules 'Inspect.psm1') -Force
Import-Module (Join-Path $modules 'Stage.psm1') -Force -WarningAction SilentlyContinue
Import-Module (Join-Path $modules 'Promote.psm1') -Force
Import-Module (Join-Path $modules 'Toolchain.psm1') -Force
Import-Module (Join-Path $modules 'Profiles.psm1') -Force
Import-Module (Join-Path $modules 'Notebook.psm1') -Force
Import-Module (Join-Path $modules 'Presentation.psm1') -Force
Import-Module (Join-Path $modules 'Budget.psm1') -Force

Initialize-CsgLayout|Out-Null

$form=New-Object Windows.Forms.Form
$form.Text='Codex Safety Gate — Windows'
$form.Size=New-Object Drawing.Size(920,720)
$form.StartPosition='CenterScreen'
$form.Font=New-Object Drawing.Font('Segoe UI',10)
$form.MinimumSize=New-Object Drawing.Size(840,660)
$form.BackColor=[Drawing.Color]::FromArgb(246,247,249)

$tabs=New-Object Windows.Forms.TabControl
$tabs.Dock='Fill'
$form.Controls.Add($tabs)

# ---------- New Addon tab ----------
$tab=New-Object Windows.Forms.TabPage
$tab.Text='接入新扩展'
$tab.BackColor=[Drawing.Color]::FromArgb(246,247,249)
$tabs.TabPages.Add($tab)

$title=New-Object Windows.Forms.Label
$title.Text='检查一个 Codex 扩展'
$title.Location='22,18';$title.AutoSize=$true
$title.Font=New-Object Drawing.Font('Segoe UI Semibold',17)
$tab.Controls.Add($title)

$intro=New-Object Windows.Forms.Label
$intro.Text='粘贴 GitHub 链接，或浏览、拖入本地文件/目录。CSG 会先冻结版本，再告诉你它想获得哪些权限。'
$intro.Location='23,54';$intro.AutoSize=$true
$intro.ForeColor=[Drawing.Color]::FromArgb(84,88,96)
$tab.Controls.Add($intro)

$urlLabel=New-Object Windows.Forms.Label
$urlLabel.Text='扩展来源'
$urlLabel.Location='22,84';$urlLabel.AutoSize=$true
$urlLabel.Font=New-Object Drawing.Font('Segoe UI Semibold',9.5)
$tab.Controls.Add($urlLabel)

$url=New-Object Windows.Forms.TextBox
$url.Location='22,108';$url.Size='502,30';$url.Anchor='Top,Left'
$url.TabIndex=0
$url.AllowDrop=$true
$tab.Controls.Add($url)

$browse=New-Object Windows.Forms.Button
$browse.Text='浏览目录'
$browse.Location='534,106';$browse.Size='88,34';$browse.Anchor='Top,Left'
$browse.TabIndex=1
$tab.Controls.Add($browse)

$browseFile=New-Object Windows.Forms.Button
$browseFile.Text='选择文件'
$browseFile.Location='634,106';$browseFile.Size='88,34';$browseFile.Anchor='Top,Left'
$browseFile.TabIndex=2
$tab.Controls.Add($browseFile)

$audit=New-Object Windows.Forms.Button
$audit.Text='检查这个'
$audit.Location='738,106';$audit.Size='144,34';$audit.Anchor='Top,Left'
$audit.FlatStyle='Flat';$audit.FlatAppearance.BorderSize=0
$audit.BackColor=[Drawing.Color]::FromArgb(36,99,235);$audit.ForeColor=[Drawing.Color]::White
$audit.Font=New-Object Drawing.Font('Segoe UI Semibold',10)
$audit.TabIndex=3
$tab.Controls.Add($audit)

$summary=New-Object Windows.Forms.RichTextBox
$summary.Location='22,158';$summary.Size='860,330'
$summary.Anchor='Top,Left'
$summary.ReadOnly=$true
$summary.BackColor=[Drawing.Color]::White
$summary.BorderStyle='FixedSingle'
$summary.Font=New-Object Drawing.Font('Segoe UI',10.5)
$summary.Text="尚未检查。`r`n`r`n检查后，这里会显示：会改什么、是否联网、是否常驻、是否读取凭据，以及可能的 Agent / Token 成本。"
$tab.Controls.Add($summary)

$network=New-Object Windows.Forms.CheckBox
$network.Text='本次 Sandbox 测试允许联网（默认断网）'
$network.Location='22,505';$network.AutoSize=$true;$network.Anchor='Top,Left'
$network.TabIndex=4
$tab.Controls.Add($network)

$action=New-Object Windows.Forms.Button
$action.Text='安全测试并安装'
$action.Location='22,540';$action.Size='250,42';$action.Enabled=$false;$action.Anchor='Top,Left'
$action.FlatStyle='Flat';$action.FlatAppearance.BorderSize=0
$action.BackColor=[Drawing.Color]::FromArgb(36,99,235);$action.ForeColor=[Drawing.Color]::White
$action.Font=New-Object Drawing.Font('Segoe UI Semibold',10.5)
$action.TabIndex=5
$tab.Controls.Add($action)

$openNote=New-Object Windows.Forms.Button
$openNote.Text='打开安全笔记'
$openNote.Location='286,540';$openNote.Size='128,42';$openNote.Anchor='Top,Left'
$openNote.TabIndex=6
$tab.Controls.Add($openNote)

$flowStatus=New-Object Windows.Forms.Label
$flowStatus.Text='等待检查'
$flowStatus.Location='430,551';$flowStatus.Size='270,24';$flowStatus.Anchor='Top,Left'
$flowStatus.ForeColor=[Drawing.Color]::FromArgb(84,88,96)
$tab.Controls.Add($flowStatus)

$details=New-Object Windows.Forms.Button
$details.Text='查看技术详情'
$details.Location='742,540';$details.Size='140,42';$details.Anchor='Top,Left'
$details.TabIndex=7
$tab.Controls.Add($details)

$status=New-Object Windows.Forms.RichTextBox
$status.Location='22,592';$status.Size='860,70'
$status.Anchor='Top,Left';$status.ReadOnly=$true;$status.Visible=$false
$status.BackColor=[Drawing.Color]::FromArgb(248,248,248)
$status.Font=New-Object Drawing.Font('Consolas',8.5)
$tab.Controls.Add($status)
$form.AcceptButton=$audit

function Update-NewAddonLayout {
    $width=$tab.ClientSize.Width
    $height=$tab.ClientSize.Height
    if($width -lt 500 -or $height -lt 400){return}

    $right=$width-22
    $auditLeft=$right-144
    $browseFileLeft=$auditLeft-100
    $browseLeft=$browseFileLeft-100
    $url.SetBounds(22,108,[Math]::Max(220,$browseLeft-34),30)
    $browse.SetBounds($browseLeft,106,88,34)
    $browseFile.SetBounds($browseFileLeft,106,88,34)
    $audit.SetBounds($auditLeft,106,144,34)

    $actionTop=[Math]::Max(430,$height-103)
    $networkTop=$actionTop-35
    $summary.SetBounds(22,158,[Math]::Max(400,$width-44),[Math]::Max(220,$networkTop-175))
    $network.Location=New-Object Drawing.Point(22,$networkTop)
    $action.SetBounds(22,$actionTop,250,42)
    $openNote.SetBounds(286,$actionTop,128,42)
    $detailsLeft=$right-140
    $details.SetBounds($detailsLeft,$actionTop,140,42)
    $flowStatus.SetBounds(430,$actionTop+11,[Math]::Max(120,$detailsLeft-446),24)
    $status.SetBounds(22,$actionTop+52,[Math]::Max(400,$width-44),[Math]::Max(40,$height-$actionTop-62))
}

$tab.Add_SizeChanged({Update-NewAddonLayout})
$form.Add_Shown({Update-NewAddonLayout})

$state=[ordered]@{
    artifact=$null
    inspection=$null
    profile=$null
    budget=$null
    card=$null
    stage=$null
    sealed=$null
}

function Log([string]$msg){
    $status.AppendText("[$(Get-Date -Format HH:mm:ss)] $msg`r`n")
    $status.ScrollToCaret()
}
function SetSummary {
    if(-not $state.inspection){return}
    $state.card=Get-CsgPermissionCard -Inspection $state.inspection -Profile $state.profile -Budget $state.budget -NetworkRequested:$network.Checked
    $text=Format-CsgPermissionCard $state.card
    if($state.artifact.provenance.kind -eq 'local' -and $state.artifact.provenance.source_path){
        $sourceLabel=if($state.artifact.provenance.selected_file){'已从所选文件定位到扩展目录'}else{'本地来源'}
        $text="$sourceLabel：$($state.artifact.provenance.source_path)`r`n`r`n$text"
    }
    if($state.sealed){
        $text+="`r`n`r`nSandbox 已验证`r`n  产物文件：$(@($state.sealed.payload.files).Count) 个"
        if(@($state.sealed.capability_surprises).Count){
            $text+="`r`n  测试发现额外行为：$(@($state.sealed.capability_surprises)-join '；')"
        }else{
            $text+="`r`n  未发现超出静态审计的可安装行为"
        }
    }
    $summary.Text=$text
}

function Invoke-GuiAudit {
    param([switch]$SuppressDialogs)
    try{
        $action.Enabled=$false;$action.Text='安全测试并安装'
        $flowStatus.Text='正在检查…'
        $state.artifact=$null;$state.inspection=$null;$state.profile=$null;$state.budget=$null;$state.card=$null;$state.stage=$null;$state.sealed=$null
        $summary.Text='正在冻结版本并检查权限…'
        if([string]::IsNullOrWhiteSpace($url.Text)){throw '请先粘贴 GitHub 链接或本地目录。'}
        Log '冻结指定版本…'
        $state.artifact=New-FrozenArtifact -Source $url.Text.Trim()
        Log "Artifact 已冻结：$($state.artifact.artifact_id)"
        if($state.artifact.provenance.kind -eq 'local'){Log "本地来源已解析：$($state.artifact.provenance.source_path)"}
        $state.inspection=Invoke-ArtifactInspection -ArtifactId $state.artifact.artifact_id
        $state.profile=Get-AddonProfile -ArtifactId $state.artifact.artifact_id
        $state.budget=Get-CsgRuntimeBudget -ArtifactId $state.artifact.artifact_id -Profile $state.profile.profile
        SetSummary
        $action.Enabled=$state.card.action_allowed
        $flowStatus.Text=$state.card.decision
        Log "审计完成：$($state.card.risk_label) / $($state.card.profile_label)"
    }catch{
        $summary.Text="检查失败`r`n`r`n$($_.Exception.Message)"
        $flowStatus.Text='检查失败'
        Log "失败：$($_.Exception.Message)"
        if($SuppressDialogs){throw}
        [Windows.Forms.MessageBox]::Show($_.Exception.Message,'CSG 审计失败','OK','Error')|Out-Null
    }
}

$audit.Add_Click({Invoke-GuiAudit})

$browse.Add_Click({
    $picker=New-Object Windows.Forms.FolderBrowserDialog
    $picker.Description='选择要检查的扩展目录'
    $picker.ShowNewFolderButton=$false
    try{
        $current=$url.Text.Trim().Trim('"',"'")
        if(Test-Path -LiteralPath $current -PathType Container){$picker.SelectedPath=(Resolve-Path -LiteralPath $current).Path}
        if($picker.ShowDialog($form) -eq [Windows.Forms.DialogResult]::OK){$url.Text=$picker.SelectedPath}
    }finally{$picker.Dispose()}
})

$browseFile.Add_Click({
    $picker=New-Object Windows.Forms.OpenFileDialog
    $picker.Title='选择要检查的扩展文件'
    $picker.Filter='Codex 扩展文件|SKILL.md;AGENTS.md;*.ps1;*.psm1;*.json;*.md|所有文件|*.*'
    $picker.CheckFileExists=$true
    $picker.Multiselect=$false
    try{
        $current=$url.Text.Trim().Trim('"',"'")
        if(Test-Path -LiteralPath $current -PathType Leaf){$picker.InitialDirectory=Split-Path -Parent (Resolve-Path -LiteralPath $current).Path}
        elseif(Test-Path -LiteralPath $current -PathType Container){$picker.InitialDirectory=(Resolve-Path -LiteralPath $current).Path}
        if($picker.ShowDialog($form) -eq [Windows.Forms.DialogResult]::OK){$url.Text=$picker.FileName}
    }finally{$picker.Dispose()}
})

$url.Add_DragEnter({
    param($sender,$eventArgs)
    if($eventArgs.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)){$eventArgs.Effect=[Windows.Forms.DragDropEffects]::Copy}
    else{$eventArgs.Effect=[Windows.Forms.DragDropEffects]::None}
})

$url.Add_DragDrop({
    param($sender,$eventArgs)
    $paths=@($eventArgs.Data.GetData([Windows.Forms.DataFormats]::FileDrop))
    if($paths.Count -eq 1){$url.Text=[string]$paths[0]}
    elseif($paths.Count -gt 1){[Windows.Forms.MessageBox]::Show('一次只能检查一个文件或目录。','CSG','OK','Information')|Out-Null}
})

$network.Add_CheckedChanged({if($state.inspection){SetSummary}})

$action.Add_Click({
    try{
        if(-not $state.profile.install_command){throw '没有自动安装配方。'}

        if(-not $state.stage){
            $sandbox=Test-WindowsSandboxAvailable
            if(-not $sandbox.usable){
                if($sandbox.edition_supported -eq $false){
                    throw "当前 Windows 版本不支持 Windows Sandbox：$($sandbox.windows_edition)。CSG 不会降级到主机执行；请改用 Windows 11 Pro/Enterprise/Education 测试机。"
                }
                throw "Windows Sandbox 当前不可用。$($sandbox.reason) CSG 不会降级到主机执行。"
            }
            if(-not (Get-PwshToolchain)){
                $choice=[Windows.Forms.MessageBox]::Show(
                    '首次测试需要冻结一份本机 PowerShell 7，仅供 Sandbox 只读使用。现在创建？',
                    'CSG','YesNo','Question')
                if($choice -eq 'Yes'){Import-PwshToolchain|Out-Null}
                else{throw '未创建 Sandbox 所需的 PowerShell 7 工具链。'}
            }
            Log '启动 Windows Sandbox。主 .codex 不会映射进去。'
            $state.stage=Invoke-SandboxStage -ArtifactId $state.artifact.artifact_id -InstallCommand $state.profile.install_command -AllowNetwork:$network.Checked
            $action.Text='Sandbox 完成后继续验证'
            $flowStatus.Text='等待 Sandbox 完成；关闭后点击同一按钮继续'
            Log "StageId：$($state.stage.stage_id)"
            return
        }

        if(-not $state.sealed){
            $flowStatus.Text='正在验证 Sandbox 结果…'
            $state.sealed=Seal-SandboxStage -StageId $state.stage.stage_id
            SetSummary
            $action.Text='批准安装'
            Log "Seal 完成：$($state.sealed.payload.tree_sha256)"
        }

        if(-not $state.card.promotion_allowed){
            throw "预算门禁阻止正式安装：$($state.budget.summary) $(@($state.budget.violations)-join '；')"
        }

        $msg=(Format-CsgPermissionCard $state.card)+"`r`n`r`n验证编号：$($state.sealed.payload.tree_sha256.Substring(0,16))…`r`n第三方 installer 不会在主机执行。`r`n`r`n接受以上权限并安装？"
        if(@($state.sealed.capability_surprises).Count){
            $msg+="`r`n`r`n注意：Sandbox 发现额外行为：$(@($state.sealed.capability_surprises)-join '；')"
        }
        $choice=[Windows.Forms.MessageBox]::Show($msg,'CSG 最终批准','YesNo','Warning')
        if($choice -ne 'Yes'){
            $flowStatus.Text='等待你的最终批准'
            Log '用户暂未批准安装。'
            return
        }
        Invoke-SealedPromotion -StageId $state.sealed.stage_id -Approval $state.sealed.approval_challenge -Apply
        $action.Enabled=$false;$action.Text='已安全安装'
        $flowStatus.Text='安装完成，可在“已接入扩展”中查看'
        $note=Update-CsgNotebook
        Log '安装完成，已写入 Registry。'
        Log "安全笔记：$note"
        [Windows.Forms.MessageBox]::Show('安装完成。安全笔记已更新。','CSG','OK','Information')|Out-Null
    }catch{
        $action.Enabled=[bool]$state.card.action_allowed
        $action.Text=if($state.stage){'Sandbox 完成后继续验证'}else{'安全测试并安装'}
        $flowStatus.Text='未完成，请查看错误后重试'
        [Windows.Forms.MessageBox]::Show($_.Exception.Message,'CSG 未完成','OK','Error')|Out-Null
        Log "失败：$($_.Exception.Message)"
    }
})

$details.Add_Click({
    $status.Visible=-not $status.Visible
    $details.Text=if($status.Visible){'隐藏技术详情'}else{'查看技术详情'}
})

$openNote.Add_Click({
    try{
        $p=Update-CsgNotebook
        Start-Process $p
    }catch{
        [Windows.Forms.MessageBox]::Show($_.Exception.Message,'CSG','OK','Error')|Out-Null
    }
})

# ---------- Registry tab ----------
$regTab=New-Object Windows.Forms.TabPage
$regTab.Text='已接入扩展'
$tabs.TabPages.Add($regTab)

$refresh=New-Object Windows.Forms.Button
$refresh.Text='刷新';$refresh.Location='18,18';$refresh.Size='90,32'
$regTab.Controls.Add($refresh)
$openLedger=New-Object Windows.Forms.Button
$openLedger.Text='打开安全笔记';$openLedger.Location='120,18';$openLedger.Size='130,32'
$regTab.Controls.Add($openLedger)

$grid=New-Object Windows.Forms.DataGridView
$grid.Location='18,62';$grid.Size='847,520';$grid.Anchor='Top,Bottom,Left,Right'
$grid.ReadOnly=$true;$grid.AllowUserToAddRows=$false;$grid.AutoSizeColumnsMode='Fill'
$regTab.Controls.Add($grid)

function RefreshRegistry {
    $root=Initialize-CsgLayout
    $rows=@()
    foreach($f in Get-ChildItem -LiteralPath (Join-Path $root 'registry') -Filter '*.json' -File -ErrorAction SilentlyContinue){
        $r=Read-JsonFile $f.FullName
        $rows += [pscustomobject]@{
            扩展=$r.addon_id
            状态=$r.status
            风险=$r.risk_band
            Artifact=$r.artifact_id
            安装时间=$r.promoted_at
        }
    }
    $grid.DataSource=[Collections.ArrayList]@($rows)
}
$refresh.Add_Click({RefreshRegistry})
$openLedger.Add_Click({$p=Update-CsgNotebook;Start-Process $p})
RefreshRegistry

# ---------- Rules tab ----------
$rulesTab=New-Object Windows.Forms.TabPage
$rulesTab.Text='我的安全规则'
$tabs.TabPages.Add($rulesTab)
$rulesText=New-Object Windows.Forms.RichTextBox
$rulesText.Dock='Fill';$rulesText.ReadOnly=$true;$rulesText.BackColor=[Drawing.Color]::White
$rulesText.Text=@'
CSG Windows 默认规则

1. 只按 Windows 设计，不提供 macOS/Linux 分支。
2. 普通使用只进入 GUI；PowerShell 命令属于高级/调试接口。
3. 第三方代码在主机正式安装阶段永不执行。
4. GitHub 版本先冻结 commit 和 SHA256，后续不重新下载 latest。
5. Windows Sandbox 默认断网、禁剪贴板、源码只读。
6. 只允许专用 Sandbox 输出目录映射为可写。
7. 普通 Skill / Agent Router 可走快速通道。
8. Proxy / Gateway / Shim / Service 必须使用专门的高风险 Profile。
9. capability 新增属于“权限扩张”，版本升级必须重新审批。
10. 回滚前检查文件是否被后续修改；发生冲突时禁止自动覆盖。
11. 安全笔记是人类可读台账；registry JSON 是机器可验证事实。
12. 目标不是让插件“绝对安全”，而是让未经理解的副作用难以进入主 Codex。
'@
$rulesTab.Controls.Add($rulesText)

if($SmokeTest){
    $form.Opacity=0
    $form.Show()
    [Windows.Forms.Application]::DoEvents()
    Update-NewAddonLayout
    if(-not [string]::IsNullOrWhiteSpace($SmokeSource)){
        $url.Text=$SmokeSource
        Invoke-GuiAudit -SuppressDialogs
    }
    $form.Size=$form.MinimumSize
    [Windows.Forms.Application]::DoEvents()
    Update-NewAddonLayout
    [pscustomobject]@{
        title=$form.Text
        width=$form.Width
        height=$form.Height
        audit_action=$audit.Text
        primary_action=$action.Text
        primary_action_enabled=$action.Enabled
        detected_profile=if($state.card){$state.card.profile}else{$null}
        detected_risk=if($state.card){$state.card.risk_code}else{$null}
        decision=if($state.card){$state.card.decision}else{$null}
        budget_status=if($state.card){$state.card.budget_status}else{$null}
        promotion_allowed=if($state.card){$state.card.promotion_allowed}else{$false}
        technical_details_visible=$status.Visible
        permission_card_placeholder=($summary.Text -match '凭据')
        source_browse_action=$browse.Text
        source_file_action=$browseFile.Text
        source_drop_enabled=$url.AllowDrop
        source_controls_visible=($url.Right -lt $browse.Left -and $browse.Right -lt $browseFile.Left -and $browseFile.Right -lt $audit.Left -and $audit.Right -le $tab.ClientSize.Width)
        primary_controls_visible=($action.Bottom -le $tab.ClientSize.Height -and $details.Right -le $tab.ClientSize.Width)
        minimum_layout_size="$($form.Width)x$($form.Height)"
        resolved_source_path=if($state.artifact){$state.artifact.provenance.source_path}else{$null}
        legacy_step_buttons=@($tab.Controls|Where-Object {$_.Text -match '自动审计|生成 Seal|批准安装到主 Codex'}).Count
    }|ConvertTo-Json
    $form.Dispose()
    return
}

[void]$form.ShowDialog()
