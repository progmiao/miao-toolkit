# Miao 产品方向与方案（可带走续作）

> 状态：**已敲定（2026-07）**  
> 用途：换电脑 / 新开 Cursor 会话时，先读本文再继续开发。  
> 范围：产品定位、技术方向、不做清单、落地阶段；**不是**当前 CLI 工具箱的实现细节手册。

---

## 一、一句话方向

**做桌面版「个人工具百宝箱」：主柱是安装与生命周期管理（重装系统后一键装齐环境与工具），次柱是本机日常小工具；专业能力用装进来的软件本身，不自研 VS Code / 不 Fork 改 TerminalBuddy 当壳，不做 PowerShell/TUI 全屏菜单当主 UX。**

---

## 二、已敲定决策（勿反复摇摆）

| # | 决策 | 说明 |
|---|------|------|
| 1 | **主产品 = 桌面应用** | 不是 Hermes 式自有 CLI/TUI，不是继续加码当前 PS 控制台壳 |
| 2 | **产品魂 = 安装管理中心** | 管理在 Miao，使用在各工具本身（可提供「打开/启动」） |
| 3 | **愿景可放大为百宝箱** | 工具管理（P0）+ 日常小工具（P1）；先做透管理 |
| 4 | **不 Fork TerminalBuddy 当主壳** | TB 等作为**被安装对象**；复杂终端由上游维护 |
| 5 | **不自研类 VS Code / VS** | 不做编辑器/IDE 主赛道 |
| 6 | **PowerShell 退居执行器** | 内嵌跑任务、日志/进度/结果；不当 UI 框架 |
| 7 | **现有 CLI 工具箱** | **仅作功能结果参考**；不作为 Desktop 运行时后端；无「过渡调旧脚本」双轨 |
| 8 | **全新开发一步到位** | 安装器、目录、IPC 均在 `desktop/` 按最终形态实现，禁止临时胶水再重构 |

### 明确不做

- PowerShell 全屏品牌菜单 / 控制台里硬做富交互（进度易冲品牌区、易卡）
- 独立「重型 VS 式安装器」产品线（更新与勾选安装收进 Desktop 即可）
- 以长 `irm …/bootstrap.ps1 \| iex` 当唯一主安装路径（可作备选）
- 把邮件/笔记做成完整竞品级应用（日常柱只做薄工具）
- 指望 WinGet 社区源 PR 作为唯一分发（可继续跟，但不阻塞产品）
- **把 `cli/` 脚本包一层当正式安装路径**（可对照功能结果，必须重写为无交互桌面 Job）

---

## 三、为什么这样定（思路摘要）

### 3.1 当前 CLI 工具箱的问题

- 整套交互绑在 **PowerShell 控制台**（品牌区、列表、进度、日志重绘）→ 天花板低。
- Hermes 等流畅，是因为 **主程序是自有 CLI/TUI**，`install.ps1` 只是胶水；不是「PS 显示窗口、背后干活」那么简单。
- 再做自有 TUI：终端会流畅些，但**表单/鼠标/简单安装**仍弱，以后往往还要再做桌面 → 两次大改，不符合「一次到位选一个方向」。

### 3.2 桌面管理中心解决什么

- 进度、滚动日志、取消、配置表单、勾选批量安装。
- **重装系统后**：打开 Miao → 清单/预设 → 装齐工具与环境，不必挨个官网找。
- 任务引擎可 **内嵌执行 PowerShell / 进程**，收回日志与结果；安装逻辑写在 **桌面 Handler**，对照 `cli/` 的功能结果重写，**不调用**旧 TUI 脚本。

### 3.3 为何不 Fork TB / 不做成 IDE

- Fork TB：合上游、更新源、品牌分叉是长期税；与「少麻烦的管理工具」目标不符。
- IDE：与现有「管 Node/Claude/Hermes/TB」投入不一致，红海且体量过大。

---

## 四、产品形态

```text
Miao Desktop（个人工具百宝箱）
│
├─ 【P0 主柱】工具管理
│    · 组件清单（catalog）勾选 / 一键恢复 / 导出导入「我的清单」
│    · 安装 / 更新 / 卸载
│    · 配置向导（少命令、少手改文件）
│    · 任务进度 + 日志 + 结果
│    · 可选：启动已装应用
│    · 自更新（GitHub Releases）
│
└─ 【P1 次柱】日常小工具（本机、薄）
     · 例：GUID、时间戳、本地速记、本地提醒、简单定时
     · 慎做：完整邮件客户端、云同步笔记、系统级计划任务替代品
```

### 与外部工具的关系

```text
用户 ──管理──► Miao Desktop ──安装/配置/更新──► Hermes / TerminalBuddy / Node / …
用户 ──使用──► 各工具自身（CLI / 官方桌面）
```

### 模块化（以后扩展）

- 按「管理对象类别」或「小工具」加模块，不是按 IDE 功能长。
- 每个可装项：id、名称、runner、入口、表单、产出约定。
- 平台提供：导航、Task 引擎、日志面板、设置、更新。

---

## 五、技术与架构方案

### 5.1 推荐技术

| 层 | 建议 |
|----|------|
| 桌面壳 | **.NET 10 + WPF + WebView2（C#）** |
| UI | **Vue 3 + TypeScript + Vite** |
| 原生侧 | **C#**：起进程、杀进程树、文件、托盘/定时（后续） |
| 安装任务 | **软件 `handler` → `IToolActionHandler`**（C# + 必要子进程）；对照 `cli/` 功能结果重写 |
| 本地状态 | **SQLite**（`%LocalAppData%\Miao\miao.db`）：software / i18n / sites / tool_state / 设置 |
| 种子数据 | **`desktop/seeds/`**（software、sites、i18n、groups）；启动灌库，无第三方插件目录 |
| 打包安装 | MSIX / Inno / VS Installer 等（后续） |
| 更新 | GitHub Releases + C# 检查下载 |

> **不采用 Tauri 作主栈**（Rust 排错成本高）。工程目录：[`desktop/`](desktop/)。

### 5.2 逻辑架构

```text
Vue UI（常用网站 / 日常·开发软件 / 工具集 / 设置）
        │  WebView2 postMessage
C# HostBridge（Miao.App）
        │
   SoftwareCatalog（Miao.Software）+ SiteService + Utilities + JobRunner
        │  仓储
   AppDatabase + SeedLoader（Miao.Data）← Common DTO
        │
   Handler（generic.* / node.* / terminal-buddy.*）
```

工程：`Miao.App` · `Miao.Common` · `Miao.Data` · `Miao.Software` · `Miao.Sites` · `Miao.Utilities`；种子：[`desktop/seeds/`](desktop/seeds/)；[`cli/`](cli/) **仅功能结果参考**。

侧栏：**常用网站 → 日常工具 → 开发工具 → 工具集 → 设置**。  
软件：`generic` 壳页 + `panel` 专用面板（如 Node）。  
安装：不继承旧 CLI 途径；按软件重选（installer-launch / winget / npm / custom）。  
不做第三方插件加载。

### 5.3 安装与更新（用户侧要「简单」）

| 方式 | 定位 |
|------|------|
| **主路径** | 双击 `MiaoSetup.exe` 或便携 Desktop（固定文件名挂在 Release） |
| 备选 | `bootstrap.ps1` / 短域名（有再做）；WinGet（社区源通了再宣传） |
| 应用更新 | Desktop 内「检查更新」拉 GitHub |
| 被管工具更新 | 同一管理台批量检查 / 更新 |

**不要**把「记一长串 irm URL」当主体验。

---

## 六、落地阶段（续作按此推进）

### 阶段 0 — 决策（已完成）

- 方向锁定：桌面 + 管理中心（+ 百宝箱愿景）
- 本文档落盘
- 技术栈：**.NET 10 + Vue 3 + TS**；工程在 `desktop/`；旧 CLI 在 `cli/`

### 阶段 1 — 换壳打穿（进行中）

- [x] 新建 `desktop/`（WPF WebView2 + Vue）
- [x] Task 引擎（PowerShell JobRunner）+ 清单 UI 骨架
- [x] 工程拆分 Common / Data / Software / Sites / Utilities；种子 `seeds/`（非插件）
- [x] 样板：微信、向日葵、TerminalBuddy、Node、CC Switch、CC Connect；常用网站
- [ ] 打通 Claude Code / Hermes 等：补 `seeds/software` + Handler
- [ ] 工具集首个小工具（如 GUID）
- [ ] 发版：GitHub Release 挂 Desktop/Setup

### 阶段 2 — 管理中心成型

- 已装状态、版本、可更新
- 配置向导（必要项表单化）
- 「我的清单」导出/导入（重装恢复）
- Miao 自身检查更新
- CLI 全屏菜单停更或仅 Advanced

**达标**：重装后靠 Miao 基本恢复环境。

### 阶段 3 — 百宝箱日常（P1）

- 侧栏「日常工具」：GUID 等薄工具逐个加
- 首页：环境健康度 + 常用小工具
- 可选「推荐预设」（开发机包 / AI 工具包）

### 阶段 4 — 按需

- 个别 Job 从 PS 迁原生（仅当脚本成瓶颈）
- WinGet 若 merge，作额外分发通道
- 代码签名减轻 SmartScreen

---

## 七、与仓库布局的关系

| 路径 | 处理 |
|------|------|
| `desktop/` | **主工程**（.NET + Vue）；目录 / 安装器 / UI 唯一正式实现 |
| `cli/` | **功能结果参考**（可读旧实现弄清「装什么」）；**禁止**作 Desktop 运行时依赖 |
| 控制台 UI（旧 core） | **不再投入** |
| `cli/release` / winget | 历史发版材料；可作分发经验参考 |
| 版本 | Desktop 独立版本号 |

---

## 八、成功标准（验收口语化）

1. **新用户**：下载一个安装包 → 打开 Miao → 勾选 → 装齐常用工具，几乎不记命令。  
2. **重装系统**：导入清单或一键预设 → 环境回来。  
3. **日常**：需要时开 Miao 看更新/小工具；写代码、SSH、Agent 仍用 TB/Hermes/编辑器本身。  
4. **扩展**：加新可管工具 = catalog + 脚本/命令，不改壳。  

---

## 九、刻意放弃的备选（归档，避免回潮）

| 备选 | 放弃原因 |
|------|----------|
| 自有 CLI/TUI 主产品 | 只解决一半痛点，易二次转型 |
| Fork TB 加 Miao 模块 | 合上游成本高；管理目标不需要改终端内核 |
| 只做 Inno、无管理 UI | 装完仍缺「清单/更新/配置」中心 |
| 对标 VS / 完整 VS Code | 体量与赛道错误 |
| 押注 WinGet 唯一安装 | 两次 Internal-Error，不可控 |

---

## 十、续作时给 Agent / 自己的提示词（可复制）

```text
请先阅读仓库根目录 PRODUCT-DIRECTION.md 与 .cursor/rules/fresh-desktop-dev.mdc。
产品方向已锁定：桌面「安装管理中心 / 个人工具百宝箱」。
全新开发：一步到位用 desktop 架构；cli/ 只作功能结果参考，禁止过渡调旧脚本。
不要提自有 TUI 主壳、不要 Fork TerminalBuddy 当主工程、不要做成 VS Code。
当前优先：Desktop ToolCatalog + ToolActionDispatcher 下真实无交互安装器。
PowerShell 仅作 runner / 子进程，不当 UI。
```

---

## 十一、相关本地文档（背景，非方向覆盖）

| 文档 | 说明 |
|------|------|
| `docs/INSTALL.md` / `docs/UPDATE.md` | 旧「winget + bootstrap」安装叙述；Desktop 为主后需日后改文档 |
| `docs/RELEASE.md` / `release/WINGET-RELEASE.md` | CLI zip / WinGet 发版；可继续作内容包与可选通道 |
| `package/core/manifest.json` | 当前工具箱版本元数据 |

---

## 十二、变更记录

| 日期 | 摘要 |
|------|------|
| 2026-07-17 | 初稿：锁定桌面管理中心 + 百宝箱愿景；否定 TUI/Fork TB/IDE 主路径 |
| 2026-07-18 | 技术栈定为 **.NET 8 + Vue**；旧实现迁入 `cli/`；新建 `desktop/`；目录由 `legacy-cli-toolkit` 更名为 `cli` |
| 2026-07-18 | 宿主升级 **.NET 10**；UI 升至 Vue / Vite / vue-router 当前最新；约定代码注释必须完善 |
| 2026-07-18 | **全新开发原则**：cli 仅参考功能结果；去掉过渡调旧脚本；ToolCatalog + ToolActionDispatcher |

---

**维护说明：** 若产品方向变更，先改本文「第二节决策表」，再改代码；避免只改代码导致换机后续作又摇摆。
