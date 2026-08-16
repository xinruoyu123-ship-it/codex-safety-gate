[CmdletBinding()]
param(
    [switch]$OnlyPrintCommands
)

$ErrorActionPreference = 'Stop'

if ($OnlyPrintCommands) {
    Write-Host '请在 VM 内以管理员身份运行：'
    Write-Host 'Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -All -NoRestart'
    Write-Host 'Enable-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM -All -NoRestart'
    Write-Host 'Restart-Computer -Force'
    exit 0
}

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    throw '请在 VM 内以管理员身份运行此脚本。'
}

Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -All -NoRestart
Enable-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM -All -NoRestart

Write-Host '功能已启用，正在重启 VM。重启后运行 CSG 测试即可。'
Restart-Computer -Force

