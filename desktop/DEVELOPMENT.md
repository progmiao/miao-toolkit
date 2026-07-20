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
| 壳 | `ui/src/shell/`、`Miao.App` | 窗口、导航、首页、设置、Toast/Confirm |
| 内核 | `ui/src/kernel/`、`Miao.Common` / `Miao.Data` | IPC、Job、清单共用、composable |
| 常用网站 | `ui/src/sites/`、`Miao.Sites` | |
| 日常工具 | `ui/src/daily/`、`Miao.Software/Install` + Catalog | 列表卡片；Job 用 Toast，不嵌 JobConsole |
| 开发工具 | `ui/src/dev/`、`Miao.Software/Dev/*` | 列表 + 各工具独立页 |
| 工具集 | `ui/src/utilities/`、`Miao.Utilities` | 应用内小工具 |

入口页统一为分区/工具文件夹内的 **`index.vue`**（不要 `XxxView` 前缀）。

别名：`@shell` `@kernel` `@sites` `@daily` `@dev` `@utilities`。

---

## 3. 新增一个开发工具（清单）

假设工具 id 为 `foo`，专用页入口为 `foo`：

1. **种子** `seeds/dev/foo/software.json`  
   - `ui.mode`: `generic`（只在开发工具列表操作）或 `panel`（有独立页）  
   - `ui.entry`: panel 时填路由段，与前端路径一致（如 `"foo"` → `/dev/foo`）  
   - `install.update.strategy`: 不需要「有更新」时写 `"none"`  
   - `actions[].handler`: 对应 C# `IToolActionHandler.HandlerId`
2. **前端页**（仅 panel）`ui/src/dev/foo/index.vue`  
   - 自己的布局 / Tab / 文案；**不要**改成「传 props 的通用管理页」  
   - 需要 Job 输出时：挂 `JobConsole` + `useJobConsole`
3. **路由** `ui/src/router.ts`：注册 `/dev/foo`，`meta.shellTitle` 写标题  
4. **后端** `src/Miao.Software/Dev/Foo/`（Handler / Service）  
   - 通用 winget/下载安装放在 `Miao.Software/Install/`，不要塞进 `Dev/`  
5. **i18n** `seeds/shell/i18n/` 补 nameKey / descriptionKey  
6. 在 `SoftwareCatalog` 构造函数注册新 Handler（若新建）

列表跳转：**不要**再写死 `toolId → path` 表；`ui.mode === 'panel'` 且有 `uiEntry` 时跳 `/dev/{uiEntry}`。

---

## 4. 必须复用的公共能力

### 4.1 `JobConsole`（`kernel/components/JobConsole.vue`）

- **用途**：双通道——左侧状态摘要 + 右侧命令输出；有进度条。  
- **用法**：父页传 `:busy` `:progress` `:logs` `:console-lines`，建议带 `placeholder`。  
- **约定**：Handler 用 `Write-Host '##progress N'` 驱动进度；该行不进命令窗。

### 4.2 `useJobConsole`（`kernel/composables/useJobConsole.ts`）

- 维护 `logs` / `consoleLines` / `progress` / `busy` / `currentJob`。  
- 页面 `subscribe` 里先处理业务消息，再 `consumeJobMessage(msg)`。  
- `onFinished` 里刷新目录或版本列表。

### 4.3 `useVoltaVersions`（`kernel/composables/useVoltaVersions.ts`）

- 仅数据层：`volta.list` / 勾选 / 过滤。  
- Node / Pnpm / Yarn **页面模板各自独立**，只复用本 composable。

### 4.4 其它内核件

| 模块 | 用途 |
|------|------|
| `useShellTitle` | 顶栏中间标题；配合路由 `meta.shellTitle` |
| `catalog/ToolLogo` + `toolMeta` | Logo、标签过滤、安装/卸载/更新按钮可见性 |
| `catalog/statusMeta` | 列表状态文案 / class |
| `bridge/toast` + `confirm` | 全局提示与确认（壳层渲染） |
| `bridge/bus` | `post` / `subscribe` / `CatalogItem` |

### 4.5 不要做成公共页的东西

- 「Volta 包管理通用页」——已废弃；Pnpm / Yarn / Node 各写各的。  
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
- PowerShell 进度约定：`##progress 0..100`。

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
