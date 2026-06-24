# 工具箱 Shell 布局标准

> 状态：**已冻结**（2026-05-29）  
> **权威来源**：工具箱内所有 Shell 页面必须遵循本文六层结构。  
> **变更策略**：修改本文或布局实现前，须与用户**明确确认**；未经确认不得增删层、改顺序、改行数预算或改层语义。

---

## 一、六层结构（固定）

自上而下，**顺序与命名不可变**：

```
┌─ Header ────────────────────────────────────────────────┐
├─ Title ─────────────────────────────────────────────────┤
├─ Catalog ───────────────────────────────────────────────┤
├─ Body ──────────────────────────────────────────────────┤
├─ Message ───────────────────────────────────────────────┤
└─ Footer ────────────────────────────────────────────────┘
```

| 层 | 英文名 | 行数 | 职责 |
|----|--------|------|------|
| **Header** | Header | 固定（会话级） | 品牌顶栏：Logo、产品信息；会话内只画一次，换语言时重绘 |
| **Title** | Title | **1** | 页面标题（cap 单行，如 `═ 工具列表 ═`） |
| **Catalog** | Catalog | **1** | 目录/上下文行：路径、面包屑、筛选摘要、操作上下文；可空占位 |
| **Body** | Body | 可变（主视口） | 主体：列表项、滚动正文、依赖日志等 |
| **Message** | Message | **1** | 瞬时消息：Flash 提示、Y/N 确认文案 |
| **Footer** | Footer | 1～2 | 底栏：列表页为导航行 + 操作行；内容页为系统工具栏 |

**Title 与 Catalog 各 1 行，彼此独立**——Catalog 不属于 Title 的子区域。

Header 与 Title 之间、各层之间**不得**插入未定义的额外固定行。

---

## 二、结构图（Expanded，典型首页）

行号 0 起始；BrandHeaderRows=13、`pageSize=20`、窗高 ≥ 38 时：

```
row  0–12 │ Header    品牌顶栏（ContentStartRow = 13）
row   13  │ Title     ═══ 工具列表 ═══
row   14  │ Catalog   （路径/上下文，Cyan；空则 DarkCyan 占位）
row 15–34 │ Body      列表 20 行（ListStartRow … ListEndRow）
row   35  │ Message   Flash / 确认提示（Yellow）
row   36  │ Footer    导航行（HintRow，列表页）
row   37  │ Footer    操作行（StatusRow / 系统工具栏）
```

### Compressed（窗高不足）

- **仅 Body 收缩**；Header / Title / Catalog / Message / Footer **钉在窗底**（Footer 贴底）。
- 切换视图时用当前 `Get-ConsoleLineHeight()` 重算行号（`Update-ToolkitShellViewLayout`）。

### Footer 模板

| 模板 | 用于 | Footer 行数 | Body 视口 |
|------|------|---------------|-----------|
| `ListWithToolbar` | 首页、单选/多选列表 | **2**（导航 + 操作） | `pageSize` |
| `SystemToolbarOnly` | 帮助、设置、语言等 | **1**（系统工具栏） | `pageSize + 1` |

Message 行在两种模板下**均占 1 行**，位于 Body 与 Footer 之间。

---

## 三、各层规范

### Header

- **绘制**：`Initialize-ToolkitShell` → `Write-ToolkitShellBrandArea`（`Header.ps1`）
- **不重绘**：普通翻页、进入子页；**重绘**：换语言
- **行数**：`ContentStartRow` = `Get-MenuHeaderRowCount(HideSectionTitle)`（当前 13）

### Title

- **1 行**分区 cap：`Write-BrandSectionCapLine`（`Title.ps1` → `Write-ToolkitShellSectionTitle`）
- 显示当前页面名称，不承载路径或长说明

### Catalog

- **1 行**，标题与 Body 之间
- **语义**：我在哪 / 当前上下文（如 `node > 安装`、`依赖 · 2/5`）
- **样式**：有文案 — 前导 1 空格 + Cyan；无文案 — DarkCyan 空行
- **持久文案**：`$Shell.BodyCatalogLine`（目标名；见 §五 代码别名）
- **渲染**：`Render-ToolkitShellCatalogRow`（目标名；现 `Render-ToolkitShellCatalogRow`）

### Body

- 列表：`Invoke-ShellSingleSelectList` / `Invoke-ShellMultiSelectList`
- 滚动页：`Invoke-ToolkitShellContentView` → `Draw-BrandedBodyLines`
- **批量执行**：`BatchExecution.ps1`（进度条 + 状态 + 日志；`Initialize-ToolkitBatchExecutionView`）在 `ListStartRow`～`ListEndRow` 内输出
- **横向**：正文须在 `LayoutLineMetrics.StartColumn`～`EndColumn` 内对齐（见 §四）

### Message

- **1 行**，Body 与 Footer 之间
- Flash、禁用项提示、Y/N 确认说明（确认底栏在 Footer）
- **样式**：前导 1 空格 + Yellow；空 — DarkYellow

### Footer

- 列表页：`Write-ToolkitShellFooter -Template ListWithToolbar` + `Update-PaginatedMenuFooter -FooterLayout Split`
- 内容页：`SystemToolbarOnly` + `New-ShellSystemToolbarConfig`
- **Esc 退出语义**（冻结）：Esc 一次 → 退出确认栏；Y/Esc 确认退出，N 取消。详见 [ARCHITECTURE.md §二](ARCHITECTURE.md#二shell-布局) 与 `.cursor/rules/shell-toolbar.mdc`

---

## 四、横向对齐（全局）

`Sync-ToolkitShellLayoutLineMetrics` → `$Shell.LayoutLineMetrics`：

| 字段 | 含义 |
|------|------|
| `StartColumn` | 内容左缘（当前 **1**，行首一个前导空格） |
| `InnerWidth` | 品牌内容内宽（`BrandInnerWidth`） |
| `LineWidth` | 含分隔符的行宽 |
| `EndColumn` | 内容右缘（`StartColumn + LineWidth`） |

**所有层**（Title cap、Catalog、Body 行、Message、Footer 栏）均在此宽度内对齐；勿贴控制台 column 0。

---

## 五、Layout 字段对照（代码 ↔ 标准层）

实现位于 `package/core/lib/ui/shell/Layout.ps1`。行号字段与标准层对应关系：

| 标准层 | Layout 字段 | Shell 状态字段 |
|--------|-------------|----------------|
| Header | `ContentStartRow` 以上 | — |
| Title | `TitleRow` | — |
| Catalog | `CatalogRow` | `BodyCatalogLine` |
| Body | `ListStartRow` … `ListEndRow` | `ListViewportHeight` |
| Message | `MessageRow` | — |
| Footer | `HintRow`、`StatusRow`、`ToolbarRow`、`BottomRow` | — |

**行数预算常量**（`Get-ShellLayoutConstants`）：

| 常量 | 值 | 对应 |
|------|-----|------|
| `TitleCatalogRows` | 2 | Title(1) + Catalog(1) |
| `MessageRows` | 1 | Message |
| `HomeDRows` | 3 | Message + Footer×2（列表页） |
| `SubDRows` | 2 | Message + Footer×1（内容页） |
| `ListSlotRows` | `pageSize` | Body 自然高度（manifest） |

**Catalog 层 API**（`CatalogRow.ps1`）：

| 函数 | 用途 |
|------|------|
| `Get-ToolkitShellCatalogRow` | 读取 Catalog 行号 |
| `Write-ToolkitShellCatalogRow` | 绘制 Catalog 行 |
| `Set-ToolkitShellBodyCatalogLine` / `Get-ToolkitShellBodyCatalogLine` | 持久 Catalog 文案 |
| `Render-ToolkitShellCatalogRow` | 按 `BodyCatalogLine` 重绘 |

列表页传入 `-InitialCatalogLine`（`Invoke-ShellSingleSelectList`）。

**横向对齐字段**（`Layout.ps1`）：`LayoutLineMetrics`、`LayoutStartColumn`、`LayoutLineWidth`。

---

## 六、模块与入口

| 层 | 主要模块 | 入口 API |
|----|----------|----------|
| Header | `Header.ps1` | `Initialize-ToolkitShell` |
| Title | `Title.ps1` | `Write-ToolkitShellSectionTitle` |
| Catalog | `CatalogRow.ps1` | `Set-ToolkitShellBodyCatalogLine`、`Render-ToolkitShellCatalogRow` |
| Body | `SingleSelectList.ps1`、`MultiSelectList.ps1`、`Page-Host.ps1` | `Invoke-ShellSingleSelectList`、`Invoke-ToolkitShellContentView` |
| Message | `Footer.ps1` | `Write-ToolkitShellMessageRow` |
| Footer | `Footer.ps1`、`SystemToolbar.ps1`、`Console-Menu.ps1` | `Write-ToolkitShellFooter`、`Update-PaginatedMenuFooter` |
| 行号 | `Layout.ps1` | `Get-ShellLayoutMetrics`、`Update-ToolkitShellViewLayout` |
| Body 初始化 | `Draw.ps1` | `Initialize-ToolkitShellBodyView` |

**页面约定**：`pages/*.ps1` 及工具内菜单不得自行 `Write-FixedLine` 占用 Header/Title/Catalog/Message 行；应通过 Shell API 写入对应层。

---

## 七、适用页面

以下视图**均须**符合六层标准（行号可因 `FooterTemplate` / Compressed 不同，层序不变）：

| 视图 | Body 内容 | Footer 模板 |
|------|-----------|-------------|
| 工具列表（home） | 工具单选列表 | `ListWithToolbar` |
| 依赖多选（install） | 依赖多选列表 | `ListWithToolbar` |
| 帮助 / 设置 / 语言 / 更新 | 滚动正文 | `SystemToolbarOnly` |
| 工具内菜单 | 工具项列表 | `ListWithToolbar` |
| 依赖安装/卸载日志 | 滚动/流式输出 | `SystemToolbarOnly`（+ 业务 Flash → Message） |
| Init / 确认覆盖 | 同左 | 退出/Y-N 覆盖 Footer，**不删除 Message 层语义** |

---

## 八、变更控制

1. **冻结对象**：六层名称与顺序、Title/Catalog/Message 各 1 行、`TitleCatalogRows=2`、横向 `LayoutLineMetrics` 规则、Footer 模板二分法。
2. **允许在不改布局标准下的实现**：Bug 修复、颜色/文案 i18n、Catalog/Message 内容填充、Body 内列表列宽（`ListLayout.ps1`）。
3. **须用户明确确认方可修改**：
   - 本文 `docs/LAYOUT.md`
   - `Layout.ps1` 中行号公式、`Get-ShellLayoutConstants` 返回值
   - 增删层、合并 Title+Catalog、取消 Message 行
   - Header 行数或 `ContentStartRow` 算法
   - 各层职责表（§一、§三）
4. **Agent / 维护者流程**：收到改布局类任务时，先说明影响面并请求确认；确认前不改上述文件。
5. **关联规则**：`.cursor/rules/shell-layout.mdc`（布局冻结）、`.cursor/rules/shell-toolbar.mdc`（Footer Esc 语义）。

---

## 九、相关文档

- [ARCHITECTURE.md](ARCHITECTURE.md) — 工程结构与 Shell 模块索引  
- [UX.md](UX.md) — 交互与原地刷新  
- [MANIFEST.md](MANIFEST.md) — `pageSize` 等全局配置  
