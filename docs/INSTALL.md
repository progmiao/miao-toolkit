# 安装与路径规范

> 状态：**已冻结**（第 5 步确认：2026-05-24）

## 一、两层「安装」概念

| 层级 | 含义 | 用户命令 |
|------|------|----------|
| **A. 安装 Miao 工具包** | 把 `miao` 命令和全部工具脚本装到本机 | `winget install miao` 或 `winget install ProgMiao.Miao`（同一包） |
| **B. 安装/更新工具依赖** | 某工具所需外部程序的 **安装或升级**（如 Volta） | `miao install` / `miao install all` / `miao install node` |

用户 **不应** clone 仓库或手动解压 zip；由 winget 或 bootstrap 完成 A。

## 二、安装 Miao（层级 A）

### 首选：winget（一行）

```powershell
winget install miao              # 推荐（Moniker）
winget install ProgMiao.Miao     # 同上（Package Id，manifest 官方格式）
```

| winget 字段 | 值 | 说明 |
|-------------|-----|------|
| Package Id | `ProgMiao.Miao` | 命令行安装用，格式要求 `发布者.应用名` |
| 显示名称 | `Miao` | 用户看到的名称，就是「Miao」 |
| 发布者 | `ProgMiao` / 程序喵 | manifest Publisher |
| Moniker | `miao` | 推荐，`winget install miao`；与 Package Id **同一包** |

**只有一个 winget 包**；后续新工具加入工具集内，仍随 `ProgMiao.Miao` 整体发版，不新建 winget 包。

关闭并重新打开 PowerShell 后：

```powershell
miao -helper
```

### 备选：bootstrap（一行，内部自动下载安装）

> bootstrap URL **待定**（GitHub org 确定后填入 manifest / 文档）。

```powershell
irm https://github.com/<org>/miao-toolkit/releases/latest/download/bootstrap.ps1 | iex
```

用户只执行一行；脚本负责下载 Release、解压、PATH，**无需手动操作 zip**。

## 三、安装路径

| 用途 | 路径 |
|------|------|
| 程序文件 | `%LOCALAPPDATA%\Miao\` |
| 用户配置 | `%APPDATA%\Miao\`（含 `config.json`、`deps-state.json`） |
| PATH | `%LOCALAPPDATA%\Miao\bin` |

```
C:\Users\<user>\AppData\Local\Miao\
├── bin\
├── core\
│   └── version.json
└── tools\
    └── node\
        ├── index.json
        ├── index.ps1
        ├── install.ps1
        └── help.md
```

环境变量（可选）：`MIAO_HOME`、`MIAO_CONFIG`

## 四、安装/更新工具依赖（层级 B）

> **`miao install` = 依赖管理专页**：未装的会安装，已装且策略为 `latest` 的可升级。不另设 `update deps` 命令（见 [UPDATE.md §五](UPDATE.md#五两层更新与第三方依赖强化-miao-install)）。

### 状态文件 `deps-state.json`

| 路径 | `%APPDATA%\Miao\deps-state.json` |
|------|----------------------------------|
| 写入时机 | **仅** `install.ps1` 执行成功之后（core 写入版本号） |
| 删除时机 | **仅** `uninstall.ps1` 执行成功之后（core 删除对应 `toolId`） |
| 不写入 | 未安装、`notInstalled` 等负向状态 |

示例：

```json
{
  "node": {
    "installedAt": "2026-05-24T12:00:00",
    "dependencies": {
      "volta": {
        "version": "2.0.1",
        "installedAt": "2026-05-24T12:00:00"
      }
    }
  }
}
```

版本来源：安装成功后优先 `winget list` 读取；锁定策略工具写目标版本。

### 命令与场景

| 命令 / 场景 | 行为 |
|-------------|------|
| `miao install` | 打开 **依赖管理专页**：列出需外部依赖的工具，Space 多选，Enter 确认 → 跑 `install.ps1` |
| `miao install node` | 同上专页，**定位到 node**（仍需 Enter 确认） |
| **首页工具列表** | 只读 `deps-state`：**已安装 / 未安装**（不调 winget、不用 `checkCommand`） |
| **进入工具**（`miao` 菜单或 `miao node`） | **不**检查依赖、**不**自动装；直接进入 |
| **工具内菜单** | 未装：仅「安装/更新」；已装：业务功能 + 末尾「安装/更新」「卸载」 |

设置 →「依赖安装/更新」进入同一专页。

### 依赖状态展示

| 页面 | 展示 | 检测方式 |
|------|------|----------|
| **首页** | 已安装 / 未安装 | 仅 `deps-state.json` |
| **依赖管理专页** | `[未安装]` / `[已安装 vX]` / `[可更新 vX → vY]` | 未装：读 state；已装 + 锁定版：state vs `index.json`；已装 + latest：state vs winget 最新 |
| **工具内菜单** | 无状态标签 | 按是否已写入 state 决定菜单项 |

交互示意（依赖管理专页）：

```
程序喵 Miao — 依赖安装/更新
 Space 勾选  |  Enter 确认  |  Q/Esc 返回

 [ ]  1  [ ] Node.js 版本管理  [未安装]
 [x]  2  [x] …                  [可更新 v2.0.0 → v2.0.1]
```

### 检查 vs 升级（第三方依赖）

| 时机 | 查什么 | 会不会升级 |
|------|--------|------------|
| **首页 / 进入工具** | `deps-state` 有无记录 | **否** |
| **工具内「安装/更新」** | 跑 `install.ps1` | **是**（装 + 按策略升） |
| **依赖管理专页 Enter 确认** | 跑选中工具的 `install.ps1` | **是** |
| **依赖管理专页列表展示** | state +（latest 时）winget | **仅展示**，不自动执行 |

**原则：** 日常浏览与进工具 = **只读本地 state**；装/升 = 用户主动在专页或工具内菜单触发。

### 外部依赖 install.ps1 规范

以 Volta 为例（`tools/node/install.ps1`）：

| 触发路径 | 行为 |
|----------|------|
| **依赖管理专页 / 工具内「安装/更新」** | 完整流程（下 1–4 步） |

完整流程：

1. 检测 `volta --version`（或 `checkCommand`）
2. 未安装 → `winget install Volta.Volta`
3. 已安装且 `updatePolicy: latest` → 有新版则 `winget upgrade Volta.Volta`
4. 已安装且锁定版本 → 跳过 upgrade；刷新 PATH，验证；失败则中文说明

成功后 **core** 调用 winget 读版本并写入 `deps-state.json`（工具脚本本身不写 state）。

## 五、卸载

| 对象 | 方式 |
|------|------|
| Miao 工具包 | `winget uninstall miao` 或 `winget uninstall ProgMiao.Miao`；或删除 `%LOCALAPPDATA%\Miao\` + 移 PATH |
| 工具外部依赖 | 不随 Miao 卸载自动删除（Volta 可能仍被其他用途使用） |

## 六、开发态

未发布 winget 前，在 **仓库根目录**（含 `dev/`、`package/` 的目录）运行：

```powershell
# 推荐：开发预览入口（内部用 $PSScriptRoot 定位，不依赖盘符路径）
.\dev\dev-miao.ps1 list
.\dev\dev-miao.ps1 -helper
.\dev\dev-miao.ps1 node -Install
```

可选：将 `package/bin` 加入 **当前会话** PATH（在仓库根目录执行）：

```powershell
$bin = Join-Path (Get-Location) 'package\bin'
$env:Path = "$bin;$env:Path"
miao list
```

> 文档与示例 **不写** `F:\...` 等绝对路径；脚本用 `$PSScriptRoot` / `Join-Path` 解析位置，仓库挪动后仍可正常运行。

## 七、发布包内容

Release / winget 包包含 **整个** `package/` 下所有工具，用户本地始终有完整工具脚本。

**第三方依赖：** 装 Miao 时不一并安装；用户通过 **依赖管理专页**（`miao install`）或 **工具内菜单** 主动装/升。首页只读 `deps-state` 展示已装/未装。详见 §四。

`DESIGN.md`、`_prototype/` **不** 打入用户安装包。
