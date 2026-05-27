# 设计文档体系

> 状态：**已冻结**（第 1 步确认：2026-05-24）

## 一、文档分层

| 层级 | 路径 | 内容 |
|------|------|------|
| **工具箱** | `docs/` | CLI、安装、发布、更新、UX、工具目录约定（**单层平铺**） |
| **单工具** | `package/tools/<id>/` | 与实现同目录：`DESIGN.md`、`help.md`、`index.json`、脚本 |

```
miao-toolkit/
├── docs/                      ← 工具箱设计（平铺 *.md，不进安装包）
│   ├── README.md              ← 本文件
│   └── OVERVIEW.md …
│
├── dev/                       ← 仅仓库开发用（不进安装包）
│   ├── dev-miao.ps1           ← 本地预览 miao
│   └── ensure-utf8bom.ps1     ← 维护 package/dev 下 ps1 的 UTF-8 BOM
│
└── package/                   ← ★ 安装包源码（winget 发布此目录内容）
    ├── bin/                   ← 命令入口，唯一加入 PATH 的目录
    ├── core/                  ← 工具箱内核：版本号 + 公共脚本
    ├── scripts/               ← 装/卸 Miao 本身（开发、bootstrap 用）
    └── tools/<id>/            ← 各子工具（见 TOOL-CONVENTION.md）
        ├── index.json
        ├── index.ps1
        └── …
```

### `package/` 各目录职责

| 目录 | 装到本机后路径 | 做什么 |
|------|----------------|--------|
| **`bin/`** | `%LOCALAPPDATA%\Miao\bin\` | **`miao` 命令入口**。含 `miao.ps1` + `miao.cmd`；**仅此目录加入 PATH** |
| **`core/`** | `%LOCALAPPDATA%\Miao\core\` | **工具箱内核**。[`manifest.json`](../package/core/manifest.json)（[MANIFEST.md](MANIFEST.md)）；`lib/`（`bootstrap/Load-Core.ps1`、`config/`、`domain/`、`pages/`、`ui/`） |
| **`scripts/`** | 一般**不**装到用户机 | **仓库/发布用**。`install.ps1` / `uninstall.ps1` / `bootstrap.ps1`：开发本地安装、或 winget/bootstrap 安装 Miao 时调用；**不是** `miao install` 那个命令 |
| **`tools/`** | `%LOCALAPPDATA%\Miao\tools\` | **各子工具**。每个 `<id>/` 自包含：`index.json` 注册、`index.ps1` 入口、`install.ps1` 装外部依赖（如 Volta） |

用户安装后本机大致为：

```
%LOCALAPPDATA%\Miao\
├── bin\          ← miao 命令
├── core\         ← 版本 + 公共库
└── tools\
    └── node\     ← node 工具全部文件
```

**原则：**

- 工具箱 `docs/` **保持单层平铺**；某类主题超过 5 篇再考虑分子目录
- 工具箱文档不写某个工具的业务细节 → 见 `package/tools/<id>/DESIGN.md`
- 单工具文档不写 CLI 路由、发布流程 → 见 `docs/`
- 单工具 **不设 `docs/` 子目录**（仅 DESIGN + help 时放工具根目录）
- 新增工具 = 新建 `package/tools/<id>/` + `index.json` → **自动注册**

## 二、DESIGN.md vs help.md

| 文件 | 读者 | 终端展示 |
|------|------|----------|
| `DESIGN.md` | 开发者 | 否 |
| `help.md` | 用户 | 是，`miao help <id>` 读取 |

help 来源：`package/tools/<id>/help.md`。

**help 分工：** `miao -helper` 简略总览；`miao help <id>` 输出完整 help.md。详见 [CLI.md](CLI.md)。

## 三、工具注册：`index.json`

- 扫描 `tools/*/index.json` 自动发现工具
- **`id` 默认 = 文件夹名**
- 字段可省略，按 [TOOL-CONVENTION.md](TOOL-CONVENTION.md) 取默认值

## 四、安装与更新（用户视角）

| 操作 | 命令 | 说明 |
|------|------|------|
| 安装 Miao 本身 | `winget install miao` 或 `ProgMiao.Miao`（同一包） | **首选** |
| 安装 Miao（备选） | `irm .../bootstrap.ps1 \| iex` | 无 winget 时（GitHub 地址确定后更新 URL） |
| 安装/更新工具依赖 | `miao install` | 交互多选；**装未装 + 升可升** |
| 全部第三方依赖 | `miao install all` | 非交互 |
| 单个工具依赖 | `miao install node` | 非交互 |
| 更新工具包 | `miao update` 或 `winget upgrade miao` / `ProgMiao.Miao` | **仅 Miao 本体**，不含 Volta 等 |

详见 [INSTALL.md](INSTALL.md)、[UPDATE.md](UPDATE.md)。

## 五、工作流程

```
① 固定工程结构              ← 已完成
② 完善 docs/ 设计文档        ← 进行中
③ 完善 package/tools/<id>/DESIGN.md
④ 完善 help.md
⑤ 设计冻结 → 开发 package/
⑥ 开发中：先改设计文档，再改代码
```

## 六、文档确认顺序

每步评审按统一格式逐项排查：

```markdown
## 第 N 步：<步骤名>

**文档：** [<相对路径>](<相对路径>)

**状态：** 草案 / 评审中 / 已冻结

### 需要确认的点
1. …
2. …

### 优化点
- **已采纳：** …
- **待你决定：** …（如有）

---
确认：回复「第 N 步：通过」或「需修改 — …」
```

| 步 | 文档 | 步骤名 |
|----|------|--------|
| 1 | [README.md](README.md) | 设计文档体系 | ✅ 已冻结 |
| 2 | [OVERVIEW.md](OVERVIEW.md) | 目标与范围 | ✅ 已冻结 |
| 3 | [ARCHITECTURE.md](ARCHITECTURE.md) | 工程结构与自动注册 | ✅ 已冻结 |
| 4 | [TOOL-CONVENTION.md](TOOL-CONVENTION.md) | 工具目录约定 | ✅ 已冻结 |
| 5 | [INSTALL.md](INSTALL.md) | 安装与 winget | ✅ 已冻结 |
| 6 | [UPDATE.md](UPDATE.md) | 发布与更新 | ✅ 已冻结 |
| 7 | [CLI.md](CLI.md) | 命令与 help | ✅ 已冻结 |
| 8 | [UX.md](UX.md) | 交互规范 | ✅ 已冻结 |
| 9 | [../package/tools/node/DESIGN.md](../package/tools/node/DESIGN.md) | node 工具设计 | 🔄 评审中（**暂停**，待恢复） |
| 10 | [../package/tools/node/help.md](../package/tools/node/help.md) | node 用户帮助 | 待确认 |
| 11 | [../package/tools/node/index.json](../package/tools/node/index.json) | node 注册配置 | 待确认 |

> **文档确认已暂停**（2026-05-24）  
> - **已完成冻结：** 第 1–8 步（工具箱级 `docs/`）  
> - **当前停在：** 第 9 步 `node/DESIGN.md`（结构已定，未最终「通过」）  
> - **待恢复：** 第 9–11 步  
> - **现阶段：** 本地实现与调试（`dev/dev-miao.ps1`），设计文档随实现必要时小改，恢复评审后再冻结

## 七、文档索引

| 文档 | 说明 |
|------|------|
| [OVERVIEW.md](OVERVIEW.md) | 目标、命名、范围 |
| [ARCHITECTURE.md](ARCHITECTURE.md) | 工程结构、自动注册 |
| [TOOL-CONVENTION.md](TOOL-CONVENTION.md) | 工具目录约定 |
| [INSTALL.md](INSTALL.md) | 安装、winget |
| [UPDATE.md](UPDATE.md) | 发布与更新 |
| [CLI.md](CLI.md) | 命令、help |
| [UX.md](UX.md) | 交互 |
| [MANIFEST.md](MANIFEST.md) | `core/manifest.json` 字段说明 |
| [I18N.md](I18N.md) | `core/i18n` 分区与 `Get-ToolkitI18n` |

| 工具 | 设计 | 使用 |
|------|------|------|
| node | [../package/tools/node/DESIGN.md](../package/tools/node/DESIGN.md) | [../package/tools/node/help.md](../package/tools/node/help.md) |

## 八、编写规范

- 语言：中文；格式：Markdown
- 状态：`草案` / `评审中` / `已冻结`
- 每工具：`index.json` + `index.ps1` + `install.ps1` + `DESIGN.md` + `help.md`
- **`DESIGN.md` 不打进 winget 安装包**；用户包含 `help.md`、脚本、`index.json`
- **路径表述**：文档/示例不写 `F:\...` 等盘符绝对路径；开发命令用仓库根相对路径（如 `.\dev\dev-miao.ps1`）；脚本用 `$PSScriptRoot` / `Join-Path`（见 [INSTALL.md §六](INSTALL.md#六开发态)）
