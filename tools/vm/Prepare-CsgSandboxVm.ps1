[CmdletBinding()]
param(
    [string]$ProjectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')),
    [string]$VmName = 'CSG-Win11-Sandbox',
    [string]$IsoUrl = 'https://go.microsoft.com/fwlink/p/?linkid=2334169&clcid=0x409&culture=en-us&country=us',
    [string]$IsoFile = 'Win11_Enterprise_Eval_zh-cn.iso',
    [string]$VmUser = 'csg',
    [string]$VmPassword,
    [long]$ExpectedIsoBytes = 7371034624,
    [ValidatePattern('^[A-Fa-f0-9]{64}$')]
    [string]$ExpectedIsoSha256,
    [switch]$AllowUnpinnedIso,
    [int]$VmMemoryMb = 8192,
    [int]$VmCpuCount = 4,
    [int]$MinHostReserveMb = 4096,
    [int]$MinProjectDriveFreeGb = 30,
    [int]$MinSystemDriveFreeGb = 10,
    [switch]$ValidationOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Test-IsAdmin {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Find-VBoxManage {
    $command = Get-Command VBoxManage.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $candidates = [System.Collections.Generic.List[string]]::new()
    if ($env:ProgramFiles) {
        $candidates.Add((Join-Path $env:ProgramFiles 'Oracle\VirtualBox\VBoxManage.exe'))
    }
    $programFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    if ($programFilesX86) {
        $candidates.Add((Join-Path $programFilesX86 'Oracle\VirtualBox\VBoxManage.exe'))
    }
    return ($candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1)
}

function New-CsgVmPassword {
    $alphabet = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'
    $bytes = New-Object byte[] 16
    [Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    $random = -join ($bytes | ForEach-Object { $alphabet[$_ % $alphabet.Length] })
    return "Csg!$random"
}

if ($ValidationOnly) {
    [pscustomobject]@{
        project_root = [IO.Path]::GetFullPath($ProjectRoot)
        vm_name = $VmName
        vm_memory_mb = $VmMemoryMb
        vm_cpu_count = $VmCpuCount
        expected_iso_bytes = $ExpectedIsoBytes
        iso_sha256_required = (-not $AllowUnpinnedIso)
        generated_password_pattern = 'Csg!<16 random characters>'
        vbox_manage = Find-VBoxManage
    } | ConvertTo-Json -Depth 5
    exit 0
}

if (-not (Test-IsAdmin)) {
    Write-Host '请使用管理员权限运行此脚本。' -ForegroundColor Yellow
    exit 1
}

$work = Join-Path $ProjectRoot 'work'
$outputs = Join-Path $ProjectRoot 'outputs'
New-Item -ItemType Directory -Force -Path $work, $outputs | Out-Null

if ([string]::IsNullOrWhiteSpace($VmPassword)) {
    $VmPassword = New-CsgVmPassword
}

$os = Get-CimInstance Win32_OperatingSystem
$freeGb = [math]::Round(($os.FreePhysicalMemory / 1MB), 1)
$requiredFreeGb = [math]::Round(($VmMemoryMb + $MinHostReserveMb) / 1024, 1)
if ($freeGb -lt $requiredFreeGb) {
    throw "当前可用内存 ${freeGb}GB，至少需要 ${requiredFreeGb}GB（VM 加主机保留内存）。"
}

$driveName = (Split-Path $ProjectRoot -Qualifier).TrimEnd(':')
$drive = Get-PSDrive -Name $driveName
if ($drive.Free -lt ($MinProjectDriveFreeGb * 1GB)) {
    throw "项目盘剩余空间不足，需要至少 ${MinProjectDriveFreeGb}GB。当前剩余：$([math]::Round($drive.Free / 1GB, 1))GB。"
}

$systemDriveName = $env:SystemDrive.TrimEnd(':')
$systemDrive = Get-PSDrive -Name $systemDriveName
if ($systemDrive.Free -lt ($MinSystemDriveFreeGb * 1GB)) {
    throw "系统盘剩余空间不足，需要至少 ${MinSystemDriveFreeGb}GB。当前剩余：$([math]::Round($systemDrive.Free / 1GB, 1))GB。"
}

$vboxExe = Find-VBoxManage
if (-not $vboxExe) {
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        throw '未找到 VirtualBox，也未找到 winget。请先从 Oracle 官方渠道安装 VirtualBox。'
    }
    Write-Host '正在通过 winget 安装 Oracle VirtualBox...'
    & winget.exe install --id Oracle.VirtualBox --exact --silent --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) { throw 'VirtualBox 安装失败。' }
    $vboxExe = Find-VBoxManage
}

if (-not $vboxExe) { throw 'VirtualBox 安装完成，但未找到 VBoxManage.exe。请重开终端后重试。' }

$iso = Join-Path $work $IsoFile
$vdi = Join-Path $work ($VmName + '.vdi')

if (Test-Path -LiteralPath $iso) {
    $currentLength = (Get-Item -LiteralPath $iso).Length
    if ($currentLength -gt $ExpectedIsoBytes) {
        throw "ISO 文件大于预期大小：实际 $currentLength，预期 $ExpectedIsoBytes。请人工检查后再处理。"
    }
    if ($currentLength -lt $ExpectedIsoBytes) {
        Write-Host "检测到未完成的 ISO：$currentLength / $ExpectedIsoBytes 字节，将断点续传。"
    }
}

if (-not (Test-Path -LiteralPath $iso) -or (Get-Item -LiteralPath $iso).Length -lt $ExpectedIsoBytes) {
    Write-Host '正在下载 Windows 11 Enterprise Evaluation 简体中文 ISO，约 7.3GB，请保持网络连接。'
    & curl.exe -L --fail --retry 3 -C - --show-error -o $iso $IsoUrl
    if ($LASTEXITCODE -ne 0) { throw 'ISO 下载失败。' }
}

$actualIsoBytes = (Get-Item -LiteralPath $iso).Length
if ($actualIsoBytes -ne $ExpectedIsoBytes) {
    throw "ISO 校验失败：实际 $actualIsoBytes，预期 $ExpectedIsoBytes。"
}

if ($ExpectedIsoSha256) {
    $actualIsoSha256 = (Get-FileHash -LiteralPath $iso -Algorithm SHA256).Hash
    if ($actualIsoSha256 -ine $ExpectedIsoSha256) {
        throw "ISO SHA256 校验失败：实际 $actualIsoSha256。保留文件供人工检查。"
    }
} elseif (-not $AllowUnpinnedIso) {
    throw '未提供 -ExpectedIsoSha256。安全模式拒绝仅凭文件大小信任 ISO；临时测试可显式使用 -AllowUnpinnedIso。'
} else {
    Write-Warning '正在使用未固定 SHA256 的 ISO。该模式只适合临时验证，不得用于发布证据。'
}

$vmNames = @(& $vboxExe list vms | ForEach-Object {
    if ($_ -match '^"(?<name>.*)"\s+\{[0-9a-f-]+\}$') { $matches.name }
})
if ($VmName -notin $vmNames) {
    Write-Host '正在创建虚拟机...'
    & $vboxExe createvm --name $VmName --ostype 'Windows11_64' --register
    if ($LASTEXITCODE -ne 0) { throw '创建 VM 失败。' }

    & $vboxExe modifyvm $VmName --memory $VmMemoryMb --cpus $VmCpuCount --firmware efi --graphicscontroller vboxsvga --vram 128 --ioapic on --nested-hw-virt on --audio-enabled off
    if ($LASTEXITCODE -ne 0) { throw '配置 VM 失败。' }

    & $vboxExe createmedium disk --filename $vdi --size 61440 --format VDI --variant Standard
    if ($LASTEXITCODE -ne 0) { throw '创建虚拟磁盘失败。' }

    & $vboxExe storagectl $VmName --name 'SATA' --add sata --controller IntelAhci --portcount 2 --bootable on
    if ($LASTEXITCODE -ne 0) { throw '添加 SATA 控制器失败。' }

    & $vboxExe storageattach $VmName --storagectl 'SATA' --port 0 --device 0 --type hdd --medium $vdi
    if ($LASTEXITCODE -ne 0) { throw '挂载虚拟磁盘失败。' }

    & $vboxExe storageattach $VmName --storagectl 'SATA' --port 1 --device 0 --type dvddrive --medium $iso
    if ($LASTEXITCODE -ne 0) { throw '挂载 ISO 失败。' }

    & $vboxExe sharedfolder add $VmName --name csg --hostpath $ProjectRoot --readonly
    if ($LASTEXITCODE -ne 0) { Write-Host '共享文件夹添加失败，可稍后手动添加。' -ForegroundColor Yellow }

    Write-Host '正在尝试自动安装 Windows...'
    & $vboxExe unattended install $VmName --iso=$iso --user=$VmUser --password=$VmPassword --full-user-name=$VmUser --hostname='CSGVM' --install-additions --locale=zh_CN --country=CN --time-zone=Asia/Shanghai
    if ($LASTEXITCODE -ne 0) {
        Write-Host '自动安装配置失败。VM 已创建，可从 VirtualBox 管理器手动安装 ISO。' -ForegroundColor Yellow
    }
} else {
    Write-Host "虚拟机 $VmName 已存在，跳过创建。"
}

& $vboxExe modifyvm $VmName --nested-hw-virt on
if ($LASTEXITCODE -ne 0) { throw '启用嵌套虚拟化失败。请确认 VM 已关机且硬件支持该功能。' }

$stateLine = @(& $vboxExe showvminfo $VmName --machinereadable | Where-Object { $_ -like 'VMState=*' } | Select-Object -First 1)
if ($LASTEXITCODE -ne 0) { throw '读取 VM 状态失败。' }
if ($stateLine -match '^VMState="running"$') {
    Write-Host '虚拟机已经在运行。'
} else {
    & $vboxExe startvm $VmName --type gui
    if ($LASTEXITCODE -ne 0) { throw '启动 VM 失败。' }
}

Write-Host ''
Write-Host "VM：$VmName"
Write-Host "用户：$VmUser"
Write-Host "密码：$VmPassword"
Write-Host '安装完成后，在 VM 内运行 Enable-CsgSandboxInGuest.ps1。'
