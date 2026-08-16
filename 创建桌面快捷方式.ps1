# Run once if you want a Desktop shortcut.
$target=Join-Path $PSScriptRoot 'CSG.cmd'
$desktop=[Environment]::GetFolderPath('Desktop')
$link=Join-Path $desktop 'Codex Safety Gate.lnk'
$shell=New-Object -ComObject WScript.Shell
$shortcut=$shell.CreateShortcut($link)
$shortcut.TargetPath=$target
$shortcut.WorkingDirectory=$PSScriptRoot
$shortcut.Description='Codex 第三方扩展安全准入'
$shortcut.Save()
Write-Host "Created: $link"
