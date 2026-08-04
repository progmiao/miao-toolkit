# Desktop 开发约定（定稿）

本文档与 [STRUCTURE.md](./STRUCTURE.md) 配套：目录「放哪」看 STRUCTURE；「怎么写、复用什么」看本文。
目标是：**新增工具时按此模板落地，不再做大重构。**

---

## 1. 总原则

| 原则 | 说明 |
|------|------|
| 一步到位 | 安装 / 清单 / IPC / UI 都在 `desktop/` 内实现；`cli/` 只作结果参考 |
| 工具页互不通用 | Node / Pnpm / Yarn / Claude 等**各自独立** `index.vue`，即便 UI 相似也不抽「通用工具页」 |
| 固定块可复用 | 进度条 + 状态日志 + PowerShell 命令窗 → 共用 `JobConsole`；Job 订阅逻辑 → `useJobConsole` |
| 配置优先 | 路由入口、更新策略等写在 seeds，避免前端硬编码工具 id 表 |

---

## 2. 侧栏分区与目录

| 中文 | 目录 | 角色 |
|------|------|------|
| 壳 | `ui/src/shell/`、`Miao.App` | 窗口、导航、首页、设置、启动页、Toast/Confirm |
| 内核 | `ui/src/kernel/`、`Miao.Common` / `Miao.Data` | IPC、Job、清单共用、composable |
| 常用网站 | `ui/src/sites/`、`Miao.Sites` | |
| 日常工具 | `ui/src/daily/`、`Miao.Software/Install` + Catalog | 列表卡片；Job 用 Toast，不嵌 JobConsole |
| 开发工具 | `ui/src/dev/`、`Miao.Software/Dev/*` | 列表 + 右侧工具概览 / 工作区（不再跳二级页） |
| 工具集 | `ui/src/utilities/`、`Miao.Utilities` | 应用内小工具 |

入口页统一为分区/工具文件夹内的 **`index.vue`**（不要 `XxxView` 前缀）。

别名：`@shell` `@kernel` `@sites` `@daily` `@dev` `@utilities`。

---

## 2.1 启动三态（窗内）

宿主**先出窗**，再后台初始化，避免白屏：

1. **层 A（WPF）**：`MainWindow` 覆盖层——与 Vue `/boot` **S0 同视觉**（ASCII logo + 氛围），仅填补 WebView 空白期；无进度条/日志  
2. **S0（Vue `/boot`）**：同款动态 logo；`boot.ui-ready` 后淡出宿主层（应感觉不到「换页」）  
3. **S1**：收到 `boot.progress`（phase=`progress`）后同页切换为进度条 + 日志  
4. **S2**：`boot.done` → 动画进入 `AppShell`  

协议：`boot.subscribe` / `boot.ui-ready`（UI→宿主）；`boot.progress` / `boot.log` / `boot.done` / `boot.error`（宿主→UI）。  
`dev.ps1` 窗前等待（Volta/npm/Vite/build）另用控制台 `[1/4]…[4/4]`，与窗内三态无关。

启动期只做**开库 / 种子 / 服务构造**（读已有 `tool_state` 上屏）；**安装态校准、更新探测、远端版本目录同步**进主壳后由静默任务补跑，不塞进启动页。

启动容错（系统配置 <c>%LocalAppData%\Miao\system.json</c>，开发为 <c>Miao-dev</c>；缺失时自动生成）：

```json
{
  "boot": {
    "maxRetryCount": 5,
    "taskTimeoutSeconds": 30
  }
}
```

| 字段 | 含义 | 默认 | 范围 |
|------|------|------|------|
| `boot.maxRetryCount` | 单任务最大尝试次数（含首次） | 5 | 1–20 |
| `boot.taskTimeoutSeconds` | 单任务超时（秒） | 30 | 3–600 |

- **核心任务**（开库、初始化服务）：达上限 → 关窗退出  
- **数据任务**（种子）：达上限 → 跳过该项，仍进主壳（降级）；安装探测已改后台静默  
- 进度用 `BeginInvoke` 投递，避免 UI 死锁  
手工改 JSON 后**重启应用**生效。

### 开发库 vs 安装库

| | 开发（`MIAO_UI_DEV=1` 或 Debug） | 安装 / Release |
|--|----------------------------------|----------------|
| 数据目录 | `%LocalAppData%\Miao-dev\` | `%LocalAppData%\Miao\` |
| 数据库 | 每次启动**删除重建** `miao.db`，完整走建表 + 种子 | 持久保留 |

两者互不影响；开发每次都能从启动页看到全流程（灌库、进度日志等）。

---

## 2.2 静默任务（进主壳后）

`SilentTaskRunner`（`Miao.Software/Jobs`）在 `boot.done` 后排队低并发后台任务；底栏右侧图标 + 角标 + 单行摘要，点击弹出进度列表。

| 方向 | 消息 |
|------|------|
| UI→宿主 | `silent.list` / `silent.cancel`（需 `id`） |
| 宿主→UI | `silent.queue` / `silent.task`；校准完成后另推 `catalog` |

约定任务 id：

| id | 含义 |
|----|------|
| `detect.install` | 校准各工具安装态/版本（`checked_at` 24h 内跳过） |
| `detect.update` | 检查已装工具是否有更新 |
| `cache.versions.node` / `pnpm` / `yarn` | 版本目录增量同步 |

完成后宿主推送 `catalog`（dev/daily），列表角标与版本自动刷新。Claude 面板 `claude.status` 首屏读库，不现场跑 `claude --version`。

三工具页默认 `volta.list` 的 `forceRemote: false`（读库）；概览「刷新清单」仍强制远端。浏览器 Mock 会模拟同一任务流。

---

## 3. 新增一个开发工具（清单）

假设工具 id 为 `foo`，专用页入口为 `foo`：

1. **种子** `seeds/dev/foo/software.json`  
   - `ui.mode`: `generic`（仅概览 + JobConsole）或 `panel`（概览下嵌入工作区）  
   - `ui.entry`: panel 时填工作区组件键（如 `"foo"` → `ui/src/dev/foo/index.vue`，由一级页动态加载）  
   - `install.update.strategy`: 不需要「有更新」时写 `"none"`  
   - `actions[].handler`: 对应 C# `IToolActionHandler.HandlerId`
2. **前端工作区**（仅 panel）`ui/src/dev/foo/index.vue`  
   - 接收 `embedded`；安装/更新/卸载放在父级 **tool-overview**，本文件只做专用正文  
   - 需要 Job 输出时：通过 `useDevPanelJob` 共用父级 `JobConsole`  
3. **路由**：不必再注册 `/dev/foo`；深链用 `/dev?tool={id}`（旧路径可 redirect）  
4. **后端** `src/Miao.Software/Dev/Foo/`（Handler / Service）  
   - 通用 winget/下载安装放在 `Miao.Software/Install/`，不要塞进 `Dev/`  
5. **i18n** `seeds/shell/i18n/` 补 nameKey / descriptionKey  
6. 在 `SoftwareCatalog` 构造函数注册新 Handler（若新建）；一级页 `panelLoaders` 登记 `ui.entry`

右侧布局命名：

| 区域 | class / 称呼 | 内容 |
|------|----------------|------|
| 工具概览 | `tool-overview` | Logo、名称、说明、安装/更新/卸载 |
| 工具工作区 | `tool-workspace` | panel 专用正文（版本管理、Claude 配置等） |
| 命令输出 | `JobConsole` | 进度 + 状态日志 + PowerShell 命令窗 |

列表选中：只切换右侧，**不要** `router.push('/dev/…')`。

---

## 4. 必须复用的公共能力

### 4.1 `JobConsole`（`kernel/components/JobConsole.vue`）

- **用途**：双通道——左侧状态摘要 + 右侧命令输出（xterm / ConPTY）；有进度条。  
- **用法**：父页传 `:busy` `:progress` `:logs` `:console-lines`，建议带 `placeholder` / `logs-placeholder`。  
- **约定**：Handler 用 `Write-Host '##progress N'`（及 `##task` / `##batch` / `##log`）驱动进度；协议行由宿主剥离，不进命令窗。  
- **执行**：宿主优先 ConPTY 跑 PowerShell，失败回退 stdout 管道；UI 用 xterm.js 实时渲染 ANSI。

### 4.2 `useJobConsole`（`kernel/composables/useJobConsole.ts`）

- 维护 `logs` / `consoleLines`（流式块）/ `progress` / `statusText` / `busy` / `currentJob`。  
- 页面 `subscribe` 里先处理业务消息，再 `consumeJobMessage(msg)`。  
- `onFinished` 里刷新目录或版本列表。

### 4.3 Volta 包工具（node / pnpm / yarn）

- 各自入口：`dev/{node,pnpm,yarn}/index.vue`（独立文案与模板）。  
- 共用层：`dev/voltaShared/`（`useVoltaPackagePage`、进度解析、版本列表辅助、工作区 CSS）。  
- 勿抽成单一「Volta 通用页」组件；工具页可单独演进。  
- 旧 `useVoltaVersions` 仍为轻量数据层，当前三页已改用 `useVoltaPackagePage`。

### 4.4 其它内核件

| 模块 | 用途 |
|------|------|
| `useShellTitle` | 顶栏中间标题；配合路由 `meta.shellTitle` |
| `catalog/ToolLogo` + `toolMeta` | Logo、标签过滤、安装/卸载/更新按钮可见性 |
| `catalog/statusMeta` | 列表状态文案 / class |
| `bridge/toast` + `confirm` | 全局提示与确认（壳层渲染） |
| `bridge/silentTasks` | 静默队列状态；底栏 `SilentTasksPanel` |
| `bridge/bus` | `post` / `subscribe` / `CatalogItem` |

### 4.5 不要做成公共页的东西

- 「Volta 包管理通用页」——不要做；Pnpm / Yarn / Node 各有入口页，仅共享 `voltaShared` 逻辑/样式。  
- 「带 Tab 的通用 CLI 配置页」——Claude 保持独立。  
- 把日常工具卡片与开发工具列表合成一个「CatalogPage」。

---

## 5. 布局习惯（开发工具 panel）

推荐结构（可按工具微调，但通道约定一致）：

```text
header（面包屑 + 主操作）
前置条件横幅（如未装 Volta）
主区 grid：
  左：业务面板（版本列表 / Tab / 表单）
  右：aside → JobConsole
```

日常工具：网格卡片 + Toast；**不**嵌 JobConsole（火即忘）。

---

## 6. 后端分层

```text
Miao.Software/
  Catalog/          目录组装与调度
  Jobs/ · Detect/   任务与探测
  Install/          通用 Handler（winget、下载拉起、注册表卸载…）
  Dev/
    Volta/ · Claude/ · Hermes/ · TerminalBuddy/
```

- Handler 通过 `actions[].handler` 字符串注册，勿在 UI 写死 Handler 类名。  
- PowerShell 进度约定：`##progress 0..100`（另有 `##task` / `##batch` / `##log`）；JobRunner 优先 ConPTY。

---

## 7. Seeds

优先：

```text
seeds/shell/groups.json · i18n/
seeds/daily/<id>/software.json
seeds/dev/<id>/software.json
seeds/sites/ · utilities/
```

旧路径 `seeds/software/*.json`、`seeds/tools/**` 仅兼容；**新改动只写分区路径**。

壁纸静态资源：`ui/public/wallpapers/`（Vite public），不进 seeds。

---

## 8. 注释

- C# public/internal：`///` 简体中文（参数、返回、副作用）。  
- TS/Vue：文件头职责 + 公共函数 JSDoc。  
- 改签名必改注释。

---

## 9. 自检（提 PR 前）

- [ ] 新工具是否独立页（panel）或明确只走列表（generic）？  
- [ ] `ui.entry` 与 router / 文件夹名是否一致？  
- [ ] 是否误抽了「通用工具页」？固定块是否用了 JobConsole / useJobConsole？  
- [ ] 是否仍依赖 `cli/` 运行时路径？  
- [ ] 通用安装逻辑是否放在 `Install/` 而非某个 Dev 工具目录？
