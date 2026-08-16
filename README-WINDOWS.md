# Codex Safety Gate — Windows GUI Alpha

这版开始，**CSG 只按 Windows 设计**。

日常使用不需要记 Freeze / Inspect / Stage / Seal / Promote 命令。

## 使用方式

双击：

```text
CSG.cmd
```

Alpha 6 已自带便携 PowerShell 7.6.4，不要求用户预先安装 `pwsh` 或配置 PATH。
启动器会优先使用包内运行时；如果包内文件缺失，才尝试系统 PowerShell 7。请完整
解压 ZIP 后再双击，不要只把 `CSG.cmd` 单独拖出来运行。

然后在 GUI 里：

```text
粘贴 GitHub 仓库 / tree / blob / raw 链接
→ 检查这个
→ 阅读权限卡片
→ 安全测试并安装
→ Sandbox 完成后继续验证
→ 最终权限批准
```

Freeze、Artifact、Stage 和 Seal 仍然存在，但只属于内部安全状态机。普通
用户默认只看到“检查”和“安全测试并安装”两个动作。

PowerShell Engine 仍保留在 `csg.ps1` 和 `modules/` 中，但定位是：

- 安全内核
- 调试接口
- 自动化接口

不是普通用户界面。

## GUI 会自动做什么

### 自动审计

一次点击完成：

- GitHub tag / commit 冻结
- source tree SHA256
- static capability scan
- 风险评级
- addon 类型判断
- Windows 安装 recipe 探测

### 自动识别类型

当前初版识别：

- `skill`
- `agent-router`
- `mcp`
- `proxy-gateway`
- `unknown`

其中 `proxy-gateway` 不允许走普通快速安装。

### Agent / Token Runtime Budget

Agent Router 和 Token 工具必须提供唯一的 `csg-budget.json`，至少声明：

- 最大子 Agent 数、并发数和委派深度；
- 最大 Sol 调用数；
- 单任务最大重试数；
- 允许的模型层级；
- Token、Agent、调用、重试、成功率和延迟基准指标。

CSG 会验证声明是否超过本地策略。声明缺失时可以进 Sandbox 收集证据，但
禁止正式安装；声明超限或无效时自动流程直接阻止。

**作者声明不等于运行时执行证据。** Agent Router 即使声明合规，也只允许进入
Sandbox；在 Runtime Observer 形成完整证据前不允许 Promotion。这个限制同时存在于
GUI 和底层 Promotion 引擎，不能通过命令行绕过。

### Runtime Observer 基础

Alpha 5 已加入 CSG 控制的观察链基础：

```text
CSG 生成固定测试计划
→ 固定 Benchmark Prompt SHA256
→ codex exec --json --ephemeral
→ 保存原始 JSONL
→ 绑定 JSONL SHA256
→ CSG 独立解析 Token 快照和完成事件
→ 生成 Observer Receipt
```

测试命令默认忽略用户配置、使用 Codex `read-only` sandbox，并且不保存 session
rollout。扩展自己生成的 Token 汇总不作为可信证据。

当前证据仍标记为 `partial`：Codex JSONL 的跨调用累计语义、子 Agent 进程数量、
并发峰值和隔离认证还没有完整验证。因此 Runtime Observer Gate 继续阻止 Agent
Router Promotion。真实 `auth.json` 和操作系统凭据存储不会映射到 Sandbox。

### 自动 Windows Sandbox

普通 Skill / Agent Router 如果能生成安全安装 recipe：

- 自动检测 Windows Sandbox
- 自动准备/冻结 PowerShell 7 toolchain
- source 只读映射
- CSG control 只读映射
- output 单独可写
- 默认断网
- 不映射主 `.codex`

### 最终批准

GUI 用权限卡片显示：

- 会修改哪些 Codex 文件
- 是否启动子进程、联网或系统常驻
- 是否需要管理员权限或读取凭据
- 是否保存 Prompt/输出
- 是否可能增加 Agent/Token 成本
- Sandbox 是否发现额外行为

用户点击 Windows 确认框之后，CSG 才复制 sealed payload。

**不会在主机重新执行第三方 installer。**

## 自动安全笔记

CSG 会维护：

```text
文档\Codex Safety\扩展安全笔记.md
```

内容包括：

- 默认安全原则
- 已安装扩展
- 风险等级
- Artifact
- Payload SHA256
- capability surprises
- rollback 信息

也就是说，Registry 面向机器，笔记面向你。

## Windows-only 原则

不再为了“跨平台优雅”增加额外复杂度。

默认技术栈就是：

- Windows 11
- PowerShell 7
- Windows Sandbox
- WinForms GUI
- `.cmd` 双击入口

PowerShell 控制台会隐藏，WinForms 主窗口保持正常可见。若 GUI 初始化失败，会显示
中文错误框，并把完整错误写到：

```text
%LOCALAPPDATA%\CodexSafetyGate\logs\launcher-error.log
```

Windows Sandbox 目前要求 Windows 11 Pro、Enterprise 或 Education；Windows
Home 不受支持。CSG 在 Home 上会明确报告环境阻塞，绝不改为在主机执行第三方
installer。

未来如果做正式版，可以把 WinForms 前端换成原生 Windows `.exe`，底层安全引擎保持不变。

## 当前 Alpha 边界

这仍是 Alpha：

- GUI/PowerShell 源码已生成，但需要你的 Windows 机器做真实语法/Windows Sandbox 集成测试；
- Proxy/Gateway 专用 Profile 尚未实现；
- Agent/Token 预算声明、受控 Observer 计划、JSONL 哈希/解析和双重 Promotion
  门禁已实现；精确跨 Agent 计量与隔离认证尚未验证，因此 Agent Router 暂不允许
  正式安装；
- 完整进程/网络/注册表 telemetry 尚未实现；
- “自动安装 recipe”只对明确可安全重定向安装目标的扩展开放；
- 无法可靠自动处理的扩展会停在“需要专用 Profile/人工审核”，而不是冒险猜安装命令。

安全原则是：**宁可按钮灰掉，也不偷偷降级到不安全路径。**
