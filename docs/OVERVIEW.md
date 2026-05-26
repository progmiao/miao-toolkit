# 工具包总览

> 状态：**已冻结**（第 2 步确认）

## 项目定位

**程序喵 Miao 工具包**（`miao-toolkit`）是面向 **Windows** 的 CLI 工具集合。用户在 PowerShell 输入 `miao` 进入统一入口，按需使用各子工具。

首个子工具：**node** — 通过 Volta 管理 Node.js 版本（原型见 `package/tools/node/_prototype/`）。

## 命名规范

| 项 | 值 | 说明 |
|----|-----|------|
| 仓库名 | **`miao-toolkit`** | Git / 文件夹名 |
| 品牌 | 程序喵 | 开发者中文名 |
| CLI 入口 | **`miao`** | 用户日常使用的命令 |
| 工具命令 | **`miao <tool-id>`** | 每个工具 **一个** 命令，不设别名 |
| winget 包 ID | **`ProgMiao.Miao`** | manifest 官方标识；`winget install ProgMiao.Miao` |
| winget Moniker | **`miao`** | 短命令；`winget install miao`（与上一行**同一包**，manifest 配置 Moniker 后两种均可） |
| winget 显示名 | **Miao** | 商店里看到的名称 |
| 工具入口文件 | **`index.ps1`** | 与 `index.json` 配对，扩展名不同不冲突 |

示例：

```powershell
winget install miao              # 推荐：Moniker，最短
winget install ProgMiao.Miao     # 同上，Package Id（winget 官方格式）
miao                             # 打开工具列表
miao node                        # 进入 node 工具
miao install node                # 安装/更新 node 所需依赖（如 Volta）
```

### 命名分工

| 名称 | 用途 |
|------|------|
| `miao-toolkit` | GitHub 仓库名 → 源码工程 |
| `ProgMiao.Miao` | winget Package Id（manifest 必填，官方格式） |
| `miao` | winget Moniker + CLI 命令；`winget install miao` 与 `ProgMiao.Miao` **同一包** |
| `Miao` | winget 显示名 |

### 发布策略

- **只有一套 winget 包**，包含全部工具脚本
- **不按工具单独发版**；任何改动都发工具箱新版本（维护成本可控）
- 用户 `winget install miao` 后，本地已有全部工具文件；第三方依赖的 **安装/更新** 由 `miao install` 负责

## 目标

| 能力 | 说明 |
|------|------|
| 统一入口 | 一个 `miao` 命令管理所有工具 |
| 工具隔离 | 每工具独立目录、独立文档、独立 `install.ps1` |
| 依赖由各工具自理 | 工具箱**不**替工具装第三方程序；用户 `miao install node` 时，才执行 `tools/node/install.ps1`（如装/升 Volta） |
| 可发现 | `-helper` / `help` 在终端查看用法 |
| 可扩展 | 新工具 = 新目录 + `index.json`，不改工具箱核心路由 |

**工具箱 vs 工具的职责：**

| 谁 | 管什么 |
|----|--------|
| **工具箱** | `miao` 命令、工具列表、路由、help、`miao install` 调度 |
| **各工具** | 自身功能 + `install.ps1` 里声明并安装所需的第三方工具 |

## 首个工具：node

| 项 | 值 |
|----|-----|
| 命令 | `miao node` |
| 功能 | 浏览 Node 版本、标注已安装/当前、通过 Volta 安装 |
| 第三方依赖 | Volta（由 `tools/node/install.ps1` 在用户 `miao install node` 时装/升） |
| 详细设计 | [../package/tools/node/DESIGN.md](../package/tools/node/DESIGN.md) |
| 使用说明 | [../package/tools/node/help.md](../package/tools/node/help.md) |

## 相关文档

- [ARCHITECTURE.md](ARCHITECTURE.md) — 工程结构
- [CLI.md](CLI.md) — 命令与 help
- [INSTALL.md](INSTALL.md) — 安装路径
- [UPDATE.md](UPDATE.md) — 发布与更新
- [UX.md](UX.md) — 交互与返回行为
