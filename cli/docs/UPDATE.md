# 发布与更新

> 状态：**已冻结**（第 6 步确认：2026-05-24）

## 一、发布策略：整体打包，统一版本

| 原则 | 说明 |
|------|------|
| **一个版本号** | 整个 `miao-toolkit` 一个 semver（写在 `core/version.json`） |
| **一次发布** | GitHub Release 包含全部工具代码，不按工具单独发版 |
| **用户全量获得** | 安装/更新后，`tools/` 下所有工具文件都在本地 |
| **按需装依赖** | 用户通过 `miao install` **安装或更新** 各工具的 **外部依赖**（如 Volta）；**不**另设 `update deps` 类命令 |

这样维护成本低：只维护一条 Release 线，不做 per-tool 版本矩阵。

## 二、发布渠道

### 首选：winget（一行安装 / 升级）

**安装 Miao：**

```powershell
winget install miao              # 推荐（Moniker）
winget install ProgMiao.Miao     # 同上（Package Id）
```

**升级 Miao：**

```powershell
winget upgrade miao              # 推荐（Moniker）
winget upgrade ProgMiao.Miao     # 同上（Package Id）
```

用户无需手动下载 zip、解压。winget 负责下载、安装、PATH（由包 manifest 定义）。

发布流程（开发侧，后续实现）：

1. 打 Git tag（如 `v0.1.0`）
2. GitHub Actions 构建发布包
3. 提交/更新 [winget-pkgs](https://github.com/microsoft/winget-pkgs) manifest
4. 用户 `winget upgrade` 即可获得新版本

### 备选：bootstrap 一行命令

> bootstrap URL **待定**（GitHub org 确定后填入 manifest / 文档）。

无 winget 或 manifest 未收录时：

```powershell
irm https://github.com/<org>/miao-toolkit/releases/latest/download/bootstrap.ps1 | iex
```

bootstrap 内部仍从 Release 拉包，但 **用户只执行一行**，不手动解压。

## 三、`miao update` 与 winget 的关系

| 方式 | 适用 | 行为 |
|------|------|------|
| `winget upgrade miao` / `winget upgrade ProgMiao.Miao` | 通过 winget 安装的用户 | 推荐，两者同一包 |
| `miao update` | 已安装 Miao 的用户 | 检测安装来源：若 winget 可用且为 winget 安装 → 提示或直接调用 upgrade；否则从 GitHub Release 拉 zip 覆盖 |

**v1 简化：** `miao update` 优先尝试 `winget upgrade`；失败则走 GitHub Release 自更新。

**不单独更新某个工具脚本** — 工具脚本随工具包版本整体替换。

## 四、`miao update` 流程（自更新路径）

```
1. 读本地 core/version.json
2. 对比 GitHub Releases 最新 tag
3. 无新版本 → 提示已是最新
4. 有新版本 → 下载 Release 资产 → 解压到临时目录
5. 覆盖 %LOCALAPPDATA%\Miao\（保留 %APPDATA%\Miao\ 用户配置）
6. 提示：可选运行 `miao install all` 同步升级第三方依赖
7. 显示 Release Notes 摘要
```

## 五、两层更新与第三方依赖（强化 `miao install`）

Miao 有 **两层** 可更新对象，对应 **两个命令**，不新增第三方专用 update 子命令：

| 层 | 更新对象 | 命令 | 说明 |
|----|----------|------|------|
| **工具箱** | Miao 本体 + 全部 `tools/` 脚本 | `miao update` / `winget upgrade miao` | 见 §三、§四 |
| **第三方依赖** | 各工具所需外部程序（Volta 等） | **`miao install`** / `all` / `<tool>` | **安装或更新**合一；见 [INSTALL.md §四](INSTALL.md#四安装更新工具依赖层级-b) |

### 为何强化 `miao install` 而非单独 `update deps`

| 决策 | 说明 |
|------|------|
| **采用** | `miao install` = 为所选工具 **装未装 + 升可升**；交互多选 / `all` / `<tool>` 均支持 |
| **不采用** | 单独的 `miao update deps` 等命令（避免双入口、双 UI、与 `install.ps1` 重复） |
| **用户场景** | 工具脚本已在本地；Volta 有新版 → `miao install node` 或 `miao install all` 即可 |

### 与日常使用、Miao 更新的关系

| 场景 | 行为 |
|------|------|
| **进入工具**（`miao node`） | 只查依赖 **有没有**；不查最新、不自动 upgrade |
| **`miao install` 主动执行** | 跑完整 `install.ps1`：未装 → install；已装可升 → upgrade；已最新 → 提示即可 |
| **`miao update` 之后** | 工具箱脚本已更新；**不会**自动升 Volta；可选 `miao install all` |

更新工具包 **不会** 自动升级第三方依赖。

第三方依赖的「检查 vs 升级」边界见 [INSTALL.md §四「检查 vs 升级」](INSTALL.md#检查-vs-升级第三方依赖)。

## 六、版本可用性提示（后台检查）

用户在终端使用 Miao 时，**可选地**得知工具箱是否有新版本；**不阻塞**当前操作，**不要求确认**。

### 触发时机

| 规则 | 说明 |
|------|------|
| **每个 PowerShell 会话仅一次** | 该终端里 **第一次** 执行任意 `miao …` 子命令时检查（含 `miao`、`miao node`、`miao help` 等） |
| **同会话后续命令不重复** | 第二次及以后的 `miao` **不再**查版本、不再重复提示 |
| **新开会话再查一次** | 新开 PowerShell 窗口视为新会话 |
| **跳过** | `miao update`、`miao version` 不触发此检查（避免递归或重复） |

实现建议：在 `miao.ps1` 用 **会话级标记**（如 `$script:MiaoUpdateHintShown`），不用写磁盘。

### 检查与提示内容

1. 读本地 `core/version.json`
2. 对比远程最新版（GitHub Releases 最新 tag；v1 可与 `miao update` 同源）
3. **已是最新** → 静默，无任何输出
4. **落后** → 输出 **一行** 提示，然后 **立即继续** 用户原本要执行的命令

示例（警告色，非错误）：

```
[!] Miao 有新版本 v0.2.0（当前 v0.1.0）。运行 miao update 或 winget upgrade miao 更新。
```

### 提示方式：一次行内提示（采用），非全局横幅

| 方案 | 说明 | 结论 |
|------|------|------|
| **一次行内提示（采用）** | 仅在 **本会话第一次** `miao` 时，在菜单/输出 **上方** 打印一行，随后正常进入 | ✅ 不打扰、实现简单 |
| 全局 persistent 提示 | 主菜单每屏、或每次子命令都显示「有新版本」 | ❌ 易烦；CLI 无「全局 UI」 |

**原则：**

- **仅提示**，不 `Read-Host`、不暂停、不挡菜单
- 网络超时或检查失败 → **静默跳过**，不影响使用
- 检查宜设短超时（如 2–3 秒），避免拖慢第一次 `miao`

### 与 `miao update` 的分工

| 能力 | 版本可用性提示 | `miao update` |
|------|----------------|---------------|
| 目的 | 告知「可以更新了」 | **执行**更新 |
| 频率 | 每会话最多一次 | 用户主动 |
| 阻塞 | 否 | 是（更新过程本身） |

## 七、版本号规范

- 格式：semver `MAJOR.MINOR.PATCH`
- 位置：`package/core/version.json`
- Git tag：`v0.1.0` 与 version.json 一致
- CHANGELOG：仓库根 `CHANGELOG.md`（后续添加）

## 八、与 GitHub 仓库

| 项 | 说明 |
|----|------|
| 仓库名 | `miao-toolkit` |
| Release | 每个版本一个 Release，附 zip（供 bootstrap / 自更新） |
| 源码 | 开发在 main，tag 触发发布 |

用户 **不需要** clone 仓库；面向用户的安装只有 winget 或 bootstrap。
