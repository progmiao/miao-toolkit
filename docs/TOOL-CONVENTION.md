# 工具目录约定（tools/<id>/）

> 状态：**已冻结**（第 4 步确认：2026-05-24）

每个工具是 **自包含目录**。`index.json`（配置）与 `index.ps1`（入口）同名不同扩展名，不冲突。

## 一、标准目录结构

### 内置工具（随 Miao 安装包分发）

```
package/tools/<sortOrder>-<command>/   # 例：01-node、02-pnpm；前缀仅表示排序权重
├── index.json
├── index.ps1
...
```

### 外部 / 第三方工具（用户扩展）

```
%APPDATA%\Miao\extensions\tools\<command>/   # 例：my-tool；目录名即 command，勿加数字前缀
├── index.json
├── index.ps1
...
```

**不设 `docs/` 子目录**（当前每工具仅 DESIGN + help 两个文档）。若日后文档超过 3 个，再建 `docs/` 不迟。

### 为何叫 `help.md` 而不是 `USAGE.md`

| 名称 | 说明 |
|------|------|
| **`help.md`（采用）** | 与命令 `miao help <id>` 一致，打开工具目录即知用途 |
| `USAGE.md` | 开源里常见，但与本 CLI 的 `help` 命令不对齐 |

## 二、文件职责

| 文件 | 必须 | 职责 |
|------|------|------|
| `index.json` | 是 | 注册；`dependencies` 供 **deps-state 状态** 与 **依赖管理专页** 展示/策略 |
| `index.ps1` | 是 | **唯一**对外入口；复杂逻辑放 `lib/` |
| `install.ps1` | 是 | 装/升第三方依赖；**无外部依赖时写空操作**（直接 return） |
| `uninstall.ps1` | 有 `dependencies` 时 | 卸第三方依赖；成功后由 core 删除 deps-state 条目 |
| `help.md` | 是 | 帮助文档，`miao help <id>` 输出 |
| `DESIGN.md` | 是 | 开发者设计；仅 GitHub 仓库，不进 winget 包 |
| `lib/*.ps1` | 否 | 子功能模块 |

**原则：** 对外始终 **`index.ps1`** 一个入口；内部分模块自由命名。

## 三、`index.json`：约定优于配置

### 自动推断（来自目录名）

| 字段 | 内置工具 | 外部工具 |
|------|----------|----------|
| `command` / `id` | 目录 `<sortOrder>-<command>` 中的 **command** 段 | 目录名本身 |
| `sortOrder` | 目录名数字前缀（如 `01`→1） | 不参与排序（归入外部组后按 command 排序） |
| `origin` | `bundled` | `external` |
| `no` | **不在此阶段赋值**；由 init / `Discover-Tools` 统一分配 1…N | 同上 |
| `entry` | `"index.ps1"` | 同左 |
| `help` | `"help.md"` | 同左 |
| `interactive` | `true` | 同左 |

### 必须显式填写（index.json）

| 字段 | 说明 |
|------|------|
| `name` | **i18n 全路径键**（如 `node.name`） |
| `description` | **i18n 全路径键**（如 `node.description`） |
| `dependencies` | 见下节（无外部依赖时可省略） |

**勿在 index.json 填写** `no`、`command`、`id`、`sortOrder`、`origin`（若出现会被忽略并 warning）。

### 菜单序号 `no`（运行时分配）

| 规则 | 说明 |
|------|------|
| 分配时机 | `miao init` 构建 catalog / 首页缓存时；未 init 时 `Discover-Tools` fallback |
| 顺序 | **内置工具**（按 `sortOrder`）→ **外部工具**（按 `command`） |
| 连续性 | 启用工具占号 1…N；`enabled: false` 不占号 |
| CLI 路由 | 始终用 **`command`**（`miao node`），与 `no` 无关 |
| 数字快捷键 | 以当前菜单显示的 `no` 为准；工具增删后 re-init 可能变化 |

列表三列统一为 **`command` / `name` / `description`**（设置、语言、工具内菜单等同理）。

### `dependencies` 字段

```json
"dependencies": {
  "menus": {
    "install": "node.deps.install",
    "update": "node.deps.update",
    "uninstall": "node.deps.uninstall"
  },
  "packages": [{
    "name": "volta",
    "checkCommand": "volta --version",
    "install": { "type": "winget", "packageId": "Volta.Volta" },
    "updatePolicy": "latest"
  }]
}
```

| 子字段 | 说明 |
|--------|------|
| `menus` | 可选。工具内 install/update/uninstall 菜单**介绍**的 i18n 键；缺省用 core 默认 |
| `packages` | 第三方包列表（原 `dependencies` 数组内容） |

仍支持旧版 **`dependencies` 为数组**（无 `menus`），仅声明包、介绍全用 core 默认。

| 用途 | 谁用 |
|------|------|
| **安装记录** | core 在 `install.ps1` 成功后写入 `%APPDATA%\Miao\deps-state.json`（含版本） |
| **首页已装/未装** | 首页不展示；依赖状态在工具内菜单与 `miao install` 专页 |
| **依赖管理专页** | 展示 `[未安装]` / 版本 / 可更新；Enter 后跑 `install.ps1` |
| **工具内菜单** | 见下节「工具内依赖菜单」 |

`checkCommand` 仍写在配置中，供 **install.ps1 安装后验证** 及开发调试；**不**用于工具内菜单是否已装的判断（菜单读 deps-state）。

### 工具内依赖菜单（core 统一）

由 `Get-ToolMenuItems`（`Invoke-ToolkitDeps.ps1`）拼装，工具 **不手写** 安装/更新/卸载项。

| deps-state | 菜单顺序 |
|------------|----------|
| 无 `dependencies` 或 `requiresInstall: false` | 仅 `actions` 业务功能 |
| 未安装 | 仅 `install`（安装） |
| 已安装 | 业务 `actions` →（后台探测到可更新时）`update` → `uninstall` |

- **是否已装**：只读 `%APPDATA%\Miao\deps-state.json`（`Test-ToolDepInstalled`），进入工具时不查 winget。
- **是否可更新**：`Start-ToolDependencyUpgradeProbe` 后台 Job 调用 `Test-ToolDependencyNeedsUpgrade`，**不阻塞**首屏菜单；探测完成后下一轮菜单刷新时追加 `update`。
- **列表命令列**：`install` / `update` / `uninstall`（与 `miao install|update|uninstall <tool>` 一致；与业务子命令 `miao node install` 等同名但 `_kind` 不同）。
- **执行**：菜单 `install` / `update` → `Invoke-ToolInstall` → `install.ps1`；`uninstall` → `uninstall.ps1`。
- **名称**：固定 core `page.toolDeps.installLabel` / `updateLabel` / `uninstallLabel`（安装 / 更新 / 删除）。
- **介绍**：`dependencies.menus.install|update|uninstall` 填 i18n 全路径键；未配置或当前语种无译文时，用 core `page.toolDeps.*Summary`。

有二级菜单的工具在 `lib/main.ps1` 中：

```powershell
$dependencyUpgradeAvailable = $false
$probeChanged = Update-ToolDependencyMenuProbe -Tool $tool -Shell $ToolkitShell `
    -UpgradeAvailable ([ref]$dependencyUpgradeAvailable)
$menuItems = Get-ToolMenuItems -BusinessActions @($Config.actions) -Tool $tool `
    -DependencyUpgradeAvailable:$dependencyUpgradeAvailable
# 依赖项选中后：Reset-ToolDependencyUpgradeProbe；Clear-DepsStateCache
```

业务 `actions[].command` 勿与系统依赖菜单命令冲突：`install`、`update`、`uninstall`（后者仅 `_kind: toolDeps` 使用）。

### 可选扩展字段

| 字段 | 说明 |
|------|------|
| `entry` / `help` | 覆盖默认路径 |
| `enabled` | `false` 时扫描跳过 |
| `requiresInstall` | `false` 时 **deps-state / 依赖管理专页均跳过** 该工具（纯本地，无第三方依赖） |
| `minMiaoVersion` | 要求工具包最低版本 |

**`requiresInstall: false` vs 空 install.ps1：**

- 无依赖工具：优先 **`requiresInstall: false`**，可不提供有效 install 逻辑
- 有依赖但 install 逻辑简单：保留 `install.ps1`，检查失败时执行

### node 示例

```json
{
  "name": "node.name",
  "description": "node.description",
  "dependencies": {
    "menus": {
      "install": "node.deps.install",
      "update": "node.deps.update",
      "uninstall": "node.deps.uninstall"
    },
    "packages": [{
      "name": "volta",
      "checkCommand": "volta --version",
      "install": { "type": "winget", "packageId": "Volta.Volta" },
      "updatePolicy": "latest"
    }]
  },
  "actions": [{
    "command": "install",
    "name": "node.action.install.name",
    "description": "node.action.install.description",
    "script": "lib/browse-install.ps1",
    "enabled": true
  }]
}
```

有 `dependencies.packages` 时还需 `uninstall.ps1`；可选 `dependencies.menus` 指向工具 i18n 介绍键（见下节）。node 已实现。

## 四、工具文案（i18n）

| 位置 | 内容 |
|------|------|
| `tools/<id>/i18n/{code}.json` | 本工具文案（**扁平 JSON**，无 `locale`/`content`） |
| 工具箱 `core/i18n` | `locale` + `content`；Shell、设置、依赖专页、**公共词** |

工具语种文件示例（`node` 已试点；`{code}` 须与工具箱语种一致，如 `zh`、`en`）：

```json
{
  "node": {
    "name": "Node.js 版本管理",
    "description": "基于 Volta 的 Node.js 版本浏览与安装",
    "deps": {
      "install": "安装 Volta，用于管理 Node.js 版本",
      "update": "将 Volta 更新到最新版本",
      "uninstall": "删除 Volta"
    },
    "action": {
      "install": {
        "name": "浏览并安装",
        "description": "从版本列表安装 Node 到本机"
      }
    }
  }
}
```

`i18n/{code}.json`：`action` 以业务 **`command` 嵌套**；`deps.*` 为 `dependencies.menus.*` 指向键的译文。`index.json` 的 `name` / `description` / `dependencies.menus.*` 填**全路径 i18n 键**。无 `menus` 或某条未配时，依赖菜单介绍用 core 默认。各工具 i18n 按 `ToolRoot` 隔离加载、会话内缓存。

`actions` 同样用 `command` + `name` / `description`（值为全路径 i18n 键）。

工具脚本需要与工具箱一致的底栏/确认文案时，在已 `Load-Core` 的前提下使用：

```powershell
Get-ToolkitI18n -Key 'common.confirm'
Get-ToolkitI18nKeyHint -Key 'Y' -LabelKey 'common.confirm'
Format-I18nLabelLine -LabelKey 'common.author' -Value '...'
Format-I18nPressEnterBack
```

详见 [I18N.md](I18N.md)。**不要**把 `common.*` 复制进工具 json。

## 五、新建工具检查清单

```
□ package/tools/<id>/
□ index.json（name、description 及 actions；勿写 no/command）
□ i18n/zh.json、en.json（name/description 键对应的真实文案）
□ index.ps1、install.ps1、help.md、DESIGN.md
□ 有 dependencies 时：uninstall.ps1；lib/main.ps1 接 Get-ToolMenuItems + Update-ToolDependencyMenuProbe
□ miao list 自动出现
```

## 六、发布包与依赖安装

**随工具箱一起发布：** 各工具 `index.json`、脚本、**`help.md`**（不含 `DESIGN.md`、`_prototype/`）。

**第三方依赖何时装：**

| 场景 | 行为 |
|------|------|
| `miao install` / 设置 → 依赖管理 | 打开专页，多选后 **主动** 执行 `install.ps1` |
| 工具内「安装」/「更新」 | **主动** 执行 `install.ps1` |
| 工具内「卸载」 | **主动** 执行 `uninstall.ps1` |
| 进入工具（菜单或 `miao node`） | **不**自动装；菜单按 deps-state 展示 |

用户装完 Miao 后本地已有全部工具脚本；Volta 等第三方程序按上表策略安装，**非**装 Miao 时一并安装。

## 七、批量执行（Shell 公共组件）

多步或多项连续执行、并展示进度与日志时，使用 core **批量执行** 组件（`package/core/lib/ui/shell/BatchExecution.ps1`）。

| 项 | 说明 |
|----|------|
| **叫什么** | 对话与文档中统一称 **批量执行**；勿用「进度条+日志公共组件」等口语代称 |
| **适用** | 初始化 batch、WinGet/插件多选后 Enter 执行、依赖批量安装等 |
| **不适用** | 单选列表页、纯 Message 提示页、表单输入页 |
| **入口 API** | `Initialize-ToolkitBatchExecutionView` → 执行 → `Invoke-ToolkitBatchExecutionWaitLoop` |
| **辅助** | `Start-ToolkitBatchExecution`、`Set-ToolkitBatchExecutionCompleteUi`、`Clear-ToolkitBatchExecutionView` |
| **日志** | 工具内自建 `Write-*LogLine` 写入 `$ctx.Log`，或复用 `Add-ToolkitDepLogLine` |
| **兼容** | 旧名 `*DepBatchOperation*` / `*DepOperationView*` 仍可用；新工具优先 `*BatchExecution*` |

典型用法（工具 `lib/*-run.ps1` 或 `init.ps1`）：

```powershell
. (Join-Path $coreLib 'ui\shell\BatchExecution.ps1')
$ctx = Initialize-ToolkitBatchExecutionView -Shell $Shell -SectionTitle $title `
    -ProgressTotal $total -ReadyStatusText $ready
Start-ToolkitBatchExecution -Ui $ctx.Ui
# …循环执行，更新 $ctx.Ui.ProgressCurrent，写日志…
Set-ToolkitBatchExecutionCompleteUi -Ui $ctx.Ui -Intent install ...
Invoke-ToolkitBatchExecutionWaitLoop -Context $ctx
Clear-ToolkitBatchExecutionView -Context $ctx
```

