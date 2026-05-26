# 工具目录约定（tools/<id>/）

> 状态：**已冻结**（第 4 步确认：2026-05-24）

每个工具是 **自包含目录**。`index.json`（配置）与 `index.ps1`（入口）同名不同扩展名，不冲突。

## 一、标准目录结构

```
package/tools/<id>/              # <id> = 命令名，如 node → miao node
├── index.json                   # ★ 必须。注册 + 可扩展配置
├── index.ps1                    # ★ 必须。统一入口
├── install.ps1                  # ★ 必须。该工具外部依赖的安装/更新
├── help.md                      # ★ 必须。帮助文档（miao help 读取）
├── DESIGN.md                    # ★ 必须。开发者设计（不进 winget 包）
├── lib/                         # 可选。子功能脚本
└── _prototype/                  # 可选。开发前原型，不随发布
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
| `help.md` | 是 | 帮助文档，`miao help <id>` 输出 |
| `DESIGN.md` | 是 | 开发者设计；仅 GitHub 仓库，不进 winget 包 |
| `lib/*.ps1` | 否 | 子功能模块 |

**原则：** 对外始终 **`index.ps1`** 一个入口；内部分模块自由命名。

## 三、`index.json`：约定优于配置

### 自动推断

| 字段 | 默认 | 说明 |
|------|------|------|
| `id` | **文件夹名** | `tools/node/` → `miao node` |
| `entry` | `"index.ps1"` | 入口脚本 |
| `install` | `"install.ps1"` | 依赖安装脚本 |
| `help` | `"help.md"` | 帮助文件路径 |
| `interactive` | `true` | 是否交互式工具 |

### 建议显式填写

| 字段 | 说明 |
|------|------|
| `displayName` | 主菜单显示名 |
| `summary` | 一行简介，`-helper` 用 |
| `category` | 分类（如 runtime） |
| `dependencies` | 见下节 |

### `dependencies` 字段

```json
"dependencies": [{
  "name": "volta",
  "checkCommand": "volta --version",
  "install": { "type": "winget", "packageId": "Volta.Volta" },
  "updatePolicy": "latest"
}]
```

| 用途 | 谁用 |
|------|------|
| **安装记录** | core 在 `install.ps1` 成功后写入 `%APPDATA%\Miao\deps-state.json`（含版本） |
| **首页已装/未装** | 只读 deps-state，**不**调用 `checkCommand` |
| **依赖管理专页** | 展示 `[未安装]` / 版本 / 可更新；Enter 后跑 `install.ps1` |
| **工具内菜单** | 未装仅「安装/更新」；已装为业务 actions + 安装/更新/卸载 |

`checkCommand` 仍写在配置中，供 **install.ps1 安装后验证** 及开发调试；**不**用于首页或进工具时的自动检测。

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
  "displayName": "Node.js 版本管理",
  "summary": "通过 Volta 浏览、安装 Node.js 版本",
  "category": "runtime",
  "dependencies": [{
    "name": "volta",
    "checkCommand": "volta --version",
    "install": { "type": "winget", "packageId": "Volta.Volta" },
    "updatePolicy": "latest"
  }]
}
```

## 四、新建工具检查清单

```
□ package/tools/<id>/
□ index.json（displayName + summary）
□ index.ps1、install.ps1、help.md、DESIGN.md
□ miao list 自动出现
```

## 五、发布包与依赖安装

**随工具箱一起发布：** 各工具 `index.json`、脚本、**`help.md`**（不含 `DESIGN.md`、`_prototype/`）。

**第三方依赖何时装：**

| 场景 | 行为 |
|------|------|
| `miao install` / 设置 → 依赖管理 | 打开专页，多选后 **主动** 执行 `install.ps1` |
| 工具内「安装/更新」 | **主动** 执行 `install.ps1` |
| 进入工具（菜单或 `miao node`） | **不**自动装；菜单按 deps-state 展示 |

用户装完 Miao 后本地已有全部工具脚本；Volta 等第三方程序按上表策略安装，**非**装 Miao 时一并安装。
