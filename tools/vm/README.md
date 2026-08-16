# CSG Windows Sandbox 虚拟机部署说明

## 前置条件

1. 关闭占用内存较大的程序，释放至少 8GB 可用内存。
2. 确认 D 盘至少还有 30GB 空闲。
3. 确认系统盘至少有 10GB、项目盘至少有 30GB 空闲，并释放约 12GB 可用内存。
4. 准备该 Windows ISO 的可信 SHA256；发布验收不得只校验文件大小。
5. 使用管理员权限运行 `Prepare-CsgSandboxVm.ps1`。

## 运行方式

右键点击 `Prepare-CsgSandboxVm.ps1`，选择“使用 PowerShell 运行”无法获得管理员权限时，请：

```powershell
$script = Join-Path $PWD 'tools\vm\Prepare-CsgSandboxVm.ps1'
Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',$script,'-ExpectedIsoSha256','<64位SHA256>'
```

脚本会自动完成：

1. 检查管理员权限、内存和磁盘空间。
2. 通过 winget 安装 Oracle VirtualBox。
3. 下载 Windows 11 Enterprise Evaluation 简体中文 ISO。
4. 创建名为 `CSG-Win11-Sandbox` 的虚拟机。
5. 启用 EFI、8GB 内存、4 CPU、60GB 动态磁盘、嵌套虚拟化。
6. 尝试自动安装 Windows 并启动 GUI。

VM 账号：

```text
用户名：csg
密码：脚本每次创建 VM 时随机生成，并在本机终端显示一次
```

## 安装 Windows 后

把 `Enable-CsgSandboxInGuest.ps1` 复制进 VM，并以管理员身份运行。脚本会启用：

- VirtualMachinePlatform
- Containers-DisposableClientVM（Windows Sandbox）

启用后 VM 会自动重启。

## 运行 CSG

重启后把宿主机的 CSG 文件夹复制到 VM 的 `C:\CSG`，然后运行：

```powershell
cd C:\CSG
.\runtime\pwsh\pwsh.exe -File .\tests\Run-LauncherTests.ps1
.\runtime\pwsh\pwsh.exe -File .\tests\Run-StaticTests.ps1
.\runtime\pwsh\pwsh.exe -File .\tests\Run-GuiSmokeTests.ps1
.\CSG.cmd
```

在 VM 中执行 CSG 完整流程时，Windows Sandbox 应可正常使用。

## 注意

- 评估镜像 90 天后过期，只用于测试。
- `-AllowUnpinnedIso` 仅供临时实验；使用该参数产生的结果不能作为发布验收证据。
- VM 中的 Windows Sandbox 需要虚拟化软件把 AMD-V 嵌套传给客户机。
- 不要在 VM 中登录个人 Microsoft 账户或放入真实凭据。
