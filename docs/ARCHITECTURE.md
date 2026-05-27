# 架构设计

> 状态：**已冻结**（Shell 重构 v2 + lib 分目录 R6 已落地）

## 一、工程结构

```
miao-toolkit/
├── README.md
├── docs/
├── dev/
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
│   │           ├── settings.ps1
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
| 加载 | **仅** `bootstrap/Load-Core.ps1`；`lib/` 根无散落 `.ps1` |

## 二、Shell 四区布局

```
┌─ Header（品牌顶栏，会话内只画一次；换语言时重绘）────────┐
├─ Title（2 行居中 cap + gap）───────────────────────────┤
├─ Content（页面负责：列表 / 滚动文本）───────────────────┤
├─ Footer gap（1 行）──────────────────────────────────┤
└─ Footer toolbar（Home=MenuSplit D=3；Sub=DefaultBar D=2）┘
```

| 模式 | Content 行数 | Footer |
|------|-------------|--------|
| Expanded | `pageSize`（home）或 `pageSize+1`（sub） | D 紧贴 Content |
| Compressed | 仅 C 收缩 | D 贴窗底 |

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
| 设置 | `pages/settings.ps1` | `Invoke-SettingsPage` | `miao settings` |
| 语言 | `pages/lang.ps1` | `Invoke-LangPage` | `miao lang` |
| 更新 | `pages/update.ps1` | `Invoke-UpdatePage` | `miao update` |

Session `viewStack`：`ToolList` → `Help` / `Settings` / `Lang` / `Update`。

## 五、模块职责（业务）

| 模块 | 路径 | 职责 |
|------|------|------|
| CLI 入口 | `bin/miao.ps1` | 解析参数，路由 |
| 加载 | `bootstrap/Load-Core.ps1` | 按序 dot-source |
| 路径/配置 | `config/Paths.ps1`、`ListLayout.ps1`、`Deps-State.ps1` 等 | 安装根、`manifest.json`（[MANIFEST.md](MANIFEST.md)）、i18n、列表布局常量、deps-state |
| 发现 | `domain/Discover-Tools.ps1` | 扫描 index.json |
| 工具启动 | `domain/Invoke-Tool.ps1` | 执行 `index.ps1` |
| 依赖状态 | `config/Deps-State.ps1`、`domain/Ensure-ToolDeps.ps1` | deps-state 读写；install/uninstall 后写版本 |
| 依赖管理 | `domain/Invoke-ToolkitDeps.ps1`、`pages/install-deps.ps1` | 专页多选、工具内菜单 |
| 控制台菜单 | `ui/console/Console-Menu.ps1` | 分页引擎、`Write-FixedLine` |

子工具若需复用 core 模块，应引用 `config/`、`domain/`、`ui/console/` 下的完整路径（见 `tools/node/`）。

## 六、依赖安装策略

| 场景 | 行为 |
|------|------|
| **首页** | 只读 `deps-state.json`：已安装 / 未安装 |
| **`miao install`** | 依赖管理专页：Space 多选，Enter 跑 `install.ps1` |
| **进入工具** | 不检查、不自动装 |
| **工具内菜单** | 未装仅「安装/更新」；已装有业务项 + 装/卸 |

## 七、调用链

```
miao → Load-Core → Start-ToolkitSession → Start-ToolkitShellSession
     → viewStack[home|help|settings|lang|update|install]
     → Invoke-Tool（无 Ensure-ToolDeps 自动装）
```

## 八、编码与兼容

- Windows PowerShell 5.1+
- `.ps1`：UTF-8 BOM（`dev/ensure-utf8bom.ps1`）
- 交互 UI：固定视口、原地刷新；`GetNewClosure` 场景须捕获 `function:` 对象

## 九、legacy

`ui/legacy/Show-BrandedPage.ps1`：旧 standalone 品牌页（`Show-BrandedContentPage`），部分设置子操作仍使用；Shell 内视图已迁移至 Page-Host。
