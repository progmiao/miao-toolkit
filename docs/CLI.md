# CLI 命令设计

> 状态：**已冻结**（第 7 步确认：2026-05-24）

## 一、命令总览

每个工具 **一个命令名**，无别名。工具列表来自 `tools/*/index.json` 自动扫描。

| 命令 | 说明 |
|------|------|
| `miao` | 交互式工具列表 |
| `miao -helper` | 工具包总帮助（简略） |
| `miao help` | **同** `-helper`（无 `<tool>` 时） |
| `miao help <tool>` | 指定工具 help.md（完整用户说明） |
| `miao list` | 非交互列出工具 |
| `miao version` | 工具包版本（core/version.json） |
| `miao install` | **交互**多选，**安装或更新**所选工具的第三方依赖 |
| `miao install all` | 对全部需依赖的工具执行 install.ps1（装 + 升） |
| `miao install <tool>` | 对单个工具执行 install.ps1（装 + 升） |
| `miao update` | 更新 **Miao 工具箱本身**（非第三方；见 UPDATE.md） |
| `miao <tool>` | 进入工具，如 `miao node` |

### 安装 Miao 本身（尚未有 miao 命令时）

```powershell
winget install miao              # 推荐（Moniker）
winget install ProgMiao.Miao     # 同上（Package Id）
```

### 入口行为（`miao.ps1`）

除下表子命令外，**每个 PowerShell 会话第一次** 执行任意 `miao …` 时，可后台检查工具箱是否有新版本；若有则 **一行提示** 后继续原命令（不阻塞、不确认）。详见 [UPDATE.md §六](UPDATE.md#六版本可用性提示后台检查)。

| 跳过版本提示 | 原因 |
|--------------|------|
| `miao update` | 避免重复 |
| `miao version` | 避免重复 |

## 二、两层更新（install vs update）

| 命令 | 对象 |
|------|------|
| `miao update` | Miao 工具箱（脚本、菜单、help） |
| `miao install` | 各工具的 **第三方依赖**（装未装 + 升可升；无单独 `update deps`） |

详见 [UPDATE.md](UPDATE.md)、[INSTALL.md](INSTALL.md)。

## 三、help 体系

| 命令 | 内容 |
|------|------|
| `miao -helper` | 命令列表 + 扫描 index.json 的 displayName / summary（**简略总览**） |
| `miao help` | **与 `-helper` 相同**（无 `<tool>` 参数时） |
| `miao help node` | 读取 `tools/node/help.md`（或 index.help 覆盖路径；**完整用户说明**） |

`DESIGN.md` 不对用户展示。

## 四、参数透传

工具名之后的参数 **原样转发** 给该工具的 `index.ps1`（`miao.ps1` 只负责路由）：

```
miao node -LtsOnly    → tools/node/index.ps1 -LtsOnly
```

## 五、错误提示

| 场景 | 提示 |
|------|------|
| 未知工具 | `未知工具: xxx。运行 miao list 查看` |
| 未安装 Miao | `未找到 miao 命令。请运行: winget install miao` |
| 缺少 help | `工具 node 暂无使用说明` |

## 六、miao.cmd

Windows 命令入口：`bin/` 加入 PATH 后，用户输入 `miao` 实际启动 `miao.cmd`，再调用同目录 `miao.ps1` 并转发参数（`%*`）。

```bat
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0miao.ps1" %*
```
