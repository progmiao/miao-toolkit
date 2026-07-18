# 架构设计

> 状态：**已冻结**（Shell 重构 v2 + lib 分目录 R6 已落地）

## 一、工程结构

```
miao-toolkit/
├── README.md
├── docs/
├── dev/
├── test/
│   ├── dev-miao.ps1
│   └── ensure-utf8bom.ps1
├── package/
│   ├── bin/
│   │   ├── miao.ps1               # CLI 主入口 → bootstrap/Load-Core.ps1
│   │   └── miao.cmd
│   ├── core/
│   │   ├── manifest.json          # 字段说明 → docs/MANIFEST.md
│   │   ├── i18n/
│   │   └── lib/
│   │       ├── bootstrap/
│   │       │   └── Load-Core.ps1  # 唯一 dot-source 入口
│   │       ├── config/
│   │       │   ├── Paths.ps1       # Get-Manifest、分页、仓库 URL
│   │       │   ├── ListLayout.ps1  # 列表列宽、编号、CLI 前缀（非 manifest）
│   │       │   ├── UserConfig.ps1
│   │       │   └── I18n.ps1
│   │       ├── domain/
│   │       │   ├── Discover-Tools.ps1
│   │       │   ├── Mock-Tools.ps1
│   │       │   ├── Ensure-ToolDeps.ps1
│   │       │   ├── Invoke-Tool.ps1
│   │       │   ├── Invoke-ToolkitDeps.ps1
│   │       │   └── Check-Update.ps1
│   │       ├── ui/
│   │       │   ├── console/
│   │       │   │   └── Console-Menu.ps1
│   │       │   ├── shell/         # Header / Title / Footer / Exit / Session …
│   │       │   └── legacy/
│   │       │       └── Show-BrandedPage.ps1
│   │       └── pages/             # 路由页（小写文件名）
│   │           ├── home.ps1
│   │           ├── help.ps1
│   │           ├── set.ps1
│   │           ├── lang.ps1
│   │           └── update.ps1
│   ├── scripts/
│   └── tools/
└── (winget manifest 等)
```

**无 `core/registry.json`**：工具列表由运行时扫描 `tools/*/index.json` 生成。

### 用户本机目录（`winget install` 后）

```
%LOCALAPPDATA%\Miao\
├── bin\           ← PATH
├── core\          ← manifest.json + lib/（manifest 见 [MANIFEST.md](MANIFEST.md)）
└── tools\
```

### `core/manifest.json`

产品元数据与全局 `pageSize`；界面文案在 `i18n/`（结构见 **[I18N.md](I18N.md)**），列表列宽等在 `lib/config/ListLayout.ps1`。运行时由 `Get-Manifest()`（`config/Paths.ps1`）读取。字段表与维护约定见 **[MANIFEST.md](MANIFEST.md)**。

### `core/lib/` 命名约定

| 区域 | 约定 |
|------|------|
| 目录 | 小写（`config`、`domain`、`ui/shell`、`pages`） |
| Shell 模块 | PascalCase 文件名（`Layout.ps1`、`Exit.ps1`） |
| 页面路由 | 小写（`home.ps1`、`lang.ps1`） |
| 加载 | **启动** `bootstrap/Load-Core.ps1`；**按需** `Import-MiaoModule -Name Help|Lang|Set|Update|Install|Tool`（注册到 global 作用域） |

## 二、Shell 布局

> **权威标准：[LAYOUT.md](LAYOUT.md)**（已冻结，2026-05-29）  
> 六层固定顺序：**Header → Title → Catalog → Body → Message → Footer**。工具箱内所有页面须遵循；修改布局须与用户确认。

```
┌─ Header ─── 品牌顶栏（会话级）
├─ Title ──── 页面标题（1 行 cap）
├─ Catalog ── 目录/上下文（1 行）
├─ Body ───── 列表 / 滚动正文（主视口）
├─ Message ── 瞬时消息（1 行）
└─ Footer ─── 底栏（列表 2 行 / 内容页 1 行）
```

| 模式 | Body 行数 | Footer |
|------|-----------|--------|
| Expanded | `pageSize`（列表页）或 `pageSize+1`（内容页） | 紧贴 Body 下方 |
| Compressed | 仅 Body 收缩 | Message + Footer 贴窗底 |

层职责、行号字段、代码对照与变更控制见 **[LAYOUT.md](LAYOUT.md)**。

**Shell 公共组件（`ui/shell/`）：**

| 组件 | API | 职责 |
|------|-----|------|
| 系统工具栏 | `New-ShellSystemToolbarConfig` | 退出/返回/系统/帮助；`-HideBack` / `-HideSystem` / `-HideHelp` |
| 列表（单选/多选） | `Invoke-ToolkitShellList` | `New-ShellListRow`（Id + Cells + Payload）+ 列布局 + 行号/选中/翻页 + 列表导航底栏行 |

**列表统一 API**（`ui/shell/ToolkitShellList.ps1`）：

```powershell
$result = Invoke-ToolkitShellList @{
    Mode = 'Single'   # 或 'Multi'
    Shell = $Shell
    SectionTitle = '...'
    CacheKey = 'Home'
    Rows = @(New-ShellListRow -Id 'x' -Cells @('a','b') -Payload $obj)
    Layout = New-ShellListLayout -Widths @(36, 0)  # 省略则默认 12,18,flex
}
# 返回 @{ _kind='shellListSelect'; Action; Ids; Payloads; Rows }
$nav = Get-ShellListSelectNavMarker $result
```

行模型与布局见 `ShellListModel.ps1`、`ShellListLayout.ps1`；绘制与缓存见 `SingleSelectList.ps1`、`MultiSelectList.ps1`（内部实现，业务层勿直接调用）。

底栏布局：`ListWithToolbar`（列表页双行）/ `SystemToolbarOnly`（内容页单行）。

**工具箱内容区宽度（全局）**：`Sync-ToolkitShellLayoutLineMetrics` 写入 `$Shell.LayoutLineMetrics` / `$Shell.Layout.LayoutLineMetrics`，各页统一使用：

| 字段 | 含义 |
|------|------|
| `StartColumn` | 内容区左缘显示列（当前为 `1`，即行首一个前导空格） |
| `InnerWidth` | 与 `BrandInnerWidth` 相同，品牌内容内宽 |
| `LineWidth` | 含分隔线字符数的行内宽（`Get-BrandSeparatorLineWidth`） |
| `EndColumn` | 内容区右缘显示列（`StartColumn + LineWidth`） |

日志换行、分隔线、`按 Enter 返回` 等正文均应在 `StartColumn`～`EndColumn` 内对齐；勿贴控制台最左列。

**底部通用工具栏（冻结）**：除非任务明确要求修改该组件，否则不要改动 `SystemToolbar.ps1`、`Exit.ps1` 中与 Esc/退出相关的语义与流程。既定行为为：**Esc 一次 → 底部退出确认栏**；在确认栏上 **Y/Esc 确认退出工具箱**、**N 取消**。各业务页（如依赖安装日志）只能在等待输入时追加参数（如 `-AllowEnter` 识别回车返回），**不得**把 Esc 改成直接返回或绕过退出确认。若确需改工具栏本身，须先与用户确认。

切换视图时用当前 `Get-ConsoleLineHeight()` 重算 layout。

## 三、Shell 模块职责

| 模块 | 路径 | 职责 |
|------|------|------|
| Nav | `ui/shell/Nav.ps1` | `Get-ShellNavMarker` / `Test-ShellNavMarker` |
| Layout | `ui/shell/Layout.ps1` | metrics、orphan 行清理 |
| Header | `ui/shell/Header.ps1` | `Initialize-ToolkitShell`、语言切换重绘 |
| Title | `ui/shell/Title.ps1` | `Write-ToolkitShellSectionTitle` |
| Draw | `ui/shell/Draw.ps1` | body 准备、`Initialize-ToolkitShellBodyView` |
| Exit | `ui/shell/Exit.ps1` | Esc → 退出栏；`Request-ShellExit` / `Read-ShellExitIfActive` |
| Footer | `ui/shell/Footer.ps1` | MenuSplit / DefaultBar 底栏 |
| Page-Host | `ui/shell/Page-Host.ps1` | `Invoke-ToolkitShellContentView`、`Invoke-StandalonePage` |
| Session | `ui/shell/Session.ps1` | `Start-ToolkitShellSession`、viewStack |

**退出约定**：页面只调用 `Request-ShellExit` / `Read-ShellExitIfActive`，不自行绘制退出 UI。

## 四、页面与 Host

| 页面 | 文件 | Shell 内入口 | 独立 CLI |
|------|------|-------------|----------|
| 首页 | `pages/home.ps1` | `Invoke-HomePage` | `miao` |
| 帮助 | `pages/help.ps1` | `Invoke-HelpPage` | `miao help` |
| 设置 | `pages/set.ps1` | `Invoke-SetPage` | `miao set` |
| 语言 | `pages/lang.ps1` | `Invoke-LangPage` | `miao lang` |
| 更新 | `pages/update.ps1` | `Invoke-UpdatePage` | `miao update` |

Session `viewStack`：`ToolList` → `Help` / `Set` / `Lang` / `Update` / `Install`。

## 五、模块职责（业务）

| 模块 | 路径 | 职责 |
|------|------|------|
| CLI 入口 | `bin/miao.ps1` | 解析参数，路由 |
| 加载 | `bootstrap/Load-Core.ps1`（启动层）+ `Import-MiaoModule.ps1`（页面按需） | 按序 dot-source |
| 路径/配置 | `config/Paths.ps1`、`ListLayout.ps1`、`Deps-State.ps1` 等 | 安装根、`manifest.json`（[MANIFEST.md](MANIFEST.md)）、i18n、列表布局常量、deps-state |
| 发现 | `domain/Discover-Tools.ps1` | 扫描 index.json |
| 工具启动 | `domain/Invoke-Tool.ps1` | 执行 `index.ps1` |
| 依赖状态 | `config/Deps-State.ps1`、`domain/Ensure-ToolDeps.ps1` | deps-state 读写；install/uninstall 后写版本 |
| 依赖管理 | `domain/Invoke-ToolkitDeps.ps1`、`pages/install.ps1` | 专页多选、工具内菜单 |
| 控制台菜单 | `ui/console/Console-Menu.ps1` | 分页引擎、`Write-FixedLine` |

子工具若需复用 core 模块，应引用 `config/`、`domain/`、`ui/console/` 下的完整路径（见 `tools/node/`）。

## 六、依赖安装策略

| 场景 | 行为 |
|------|------|
| **首页** | 不展示依赖状态；进入工具或 `miao install` 时再读 `deps-state` |
| **`miao install`** | 依赖管理专页：Space 多选，Enter 跑 `install.ps1` |
| **进入工具** | 不检查、不自动装 |
| **工具内菜单** | 未装仅「安装/更新」；已装有业务项 + 装/卸 |

## 七、调用链

```
miao → Load-Core（启动层）→ Start-ToolkitSession → Start-ToolkitShellSession
     → Ensure-MiaoShellViewModule（进入视图时按需加载）
     → viewStack[home|help|set|lang|update|install]
     → Import-MiaoModule Tool → Invoke-Tool（无 Ensure-ToolDeps 自动装）
```

## 八、编码与兼容

- Windows PowerShell 5.1+
- `.ps1`：UTF-8 BOM（`dev/ensure-utf8bom.ps1`）
- 交互 UI：固定视口、原地刷新；`GetNewClosure` 场景须捕获 `function:` 对象

## 九、legacy

`ui/legacy/Show-BrandedPage.ps1`：旧 standalone 品牌页（`Show-BrandedContentPage`），部分设置子操作仍使用；Shell 内视图已迁移至 Page-Host。
