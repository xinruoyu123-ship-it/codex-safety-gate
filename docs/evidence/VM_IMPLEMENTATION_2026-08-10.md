# 实施记录

## 2026-08-10

### 主机前置检查

- CPU：AMD Ryzen 7 H 260，16 逻辑处理器
- CPU 虚拟化：已启用
- 内存：约 16GB，检查时可用约 1GB
- C 盘剩余：约 18GB
- D 盘剩余：约 58GB
- 当前会话：非管理员
- 已安装虚拟机软件：无
- WSL：未安装
- Windows 家庭版：Windows Sandbox 不支持
- HypervisorPresent：False

### CSG 本机验证

- `CSG.cmd --smoke`：通过
- `Run-LauncherTests.ps1`：1/1 通过
- `Run-StaticTests.ps1`：32/32 通过
- `Run-GuiSmokeTests.ps1`：6/6 通过
- `csg.ps1 doctor`：Windows Sandbox 不可用

### 方案选择

选用 VirtualBox + Windows 11 Enterprise Evaluation 虚拟机。

- ISO 官方下载地址：`https://go.microsoft.com/fwlink/p/?linkid=2334169&clcid=0x409&culture=en-us&country=us`
- ISO 预计大小：7,371,034,624 字节
- 语言：简体中文
- VM 配置：8GB 内存、4 CPU、60GB 动态磁盘、EFI、嵌套虚拟化

