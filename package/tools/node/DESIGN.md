# node 工具 — 设计说明

> 状态：**评审中**（第 9 步：结构已定，待最终「通过」）  
> 命令：`miao node`  
> 用户向说明见 [help.md](help.md)

## 一、工具定位

**node** 是 Miao 中 **Node.js 版本管理** 子工具，底层 [Volta](https://volta.sh/)。

**补位原则：** 把 Volta CLI「必须写 `node@版本`」的操作做成 **列表选择**；已知版本号或 npm/yarn 等 → 用户直接用 `volta` 原生命令。

| 项 | 值 |
|----|-----|
| tool-id | `node` |
| 命令 | `miao node` |
| 别名 | **无** |
| 类别 | runtime |
| 交互式 | 是（**含二级功能菜单**） |

### 与工具箱的关系（壳 vs 工具）

| 层 | 职责 |
|----|------|
| **工具箱** `miao.ps1` | 路由 `miao node` → `tools/node/index.ps1`，**参数原样透传** |
| **本工具** `index.ps1` | 解析本工具参数（`-i`/`-p`/`-d` 等）、二级菜单、调用 `lib/` |

工具箱 **不** 解析 node 专属参数；新增/修改/删除参数 **只改本工具目录**，不动外层。

### npm / yarn / pnpm

**不在本工具内实现**；后续可单独扩展工具。v1 用户用 `volta install npm@…` 等。

---

## 二、功能结构：一级菜单 → 二级操作

`miao node` **无参数** 时进入 **功能菜单**（不再直接进入安装列表）。

| # | 菜单名（采用长名） | 二级行为 | Volta 对应 | 阶段 |
|---|-------------------|----------|------------|------|
| 1 | **浏览并安装** | nodejs.org 全版本列表，Enter 安装 | `volta install node@x` | **v1** |
| 2 | **为项目指定** | 当前目录项目 pin 列表 | `volta pin node@x` | v2 |
| 3 | **设置全局默认** | 已安装 Node 单选设 default；可跳转完整列表 | `volta install node@x` | v1.1 |

**v1 实现：** 仅开放 [1]；[2][3] 在菜单中预留（灰显或「即将推出」），结构与参数先定好便于扩展。

### 快捷参数（跳过一级菜单）

由 **`index.ps1` param 块** 定义；工具箱只透传。

| 意图 | 完整参数 | 别名 | 直达 |
|------|----------|------|------|
| 浏览并安装 | `-Install` | `-i` | 二级 [1] |
| 为项目指定 | `-Pin` | `-p` | 二级 [2] |
| 设置全局默认 | `-Default` | `-d` | 二级 [3] |

- `-i` / `-p` / `-d` **互斥**；同时出现则报错。
- `-LtsOnly` 等仅对 **安装** 模式有效。

示例：

```powershell
miao node
miao node -i
miao node -Install -LtsOnly
miao node -p          # v2
miao node -d          # v1.1
```

### 二级 · 浏览并安装（v1）

- 从 nodejs.org 拉版本，**倒序**；分批加载
- 标注：`[当前]` `[已安装]` `[默认]` `[LTS:xx]`
- Enter → `volta install node@版本`
- 固定视口菜单，无整屏闪烁

### 二级 · 为项目指定（v2，结构预留）

- 需当前目录有 `package.json`
- 未装版本：**默认「安装并指定」**；可选「仅指定」（pin 后 Volta 首次使用时 fetch）
- Enter → `volta pin node@x`（+ 按需 install）

### 二级 · 设置全局默认（v1.1，结构预留）

- 主列表：**仅已安装** Node（`volta list`），单选 → `volta install node@x` 设 default
- 可选入口：跳转「浏览并安装」全列表

### 不包含

- Volta 子命令通用转发
- npm / yarn / pnpm 管理（后续独立工具）
- nvm、fnm 等非 Volta 安装方式
- v1：`volta pin` 交互、设 default 二级（仅预留菜单项）

---

## 三、外部依赖

| 依赖 | 安装方式 | 策略 |
|------|----------|------|
| Volta | winget `Volta.Volta` | 见下表 |

由 `install.ps1` 实现。

| 触发 | 行为 |
|------|------|
| **依赖管理专页 / 工具内「安装/更新」** | **安装或更新** Volta（`install.ps1` 完整流程） |
| **进入工具** | **不**自动装；菜单按 deps-state 展示 |

成功后 core 写入 `deps-state.json`；首页只读 state 显示已装/未装。

### 冲突提示

若检测到 `nvm.exe` 或 `fnm` 在 PATH，警告可能与 Volta 冲突。

---

## 四、入口与文件布局

### 固定入口：`index.ps1`

所有工具 **统一** 使用 `index.ps1` 作为唯一对外入口（[TOOL-CONVENTION](../../../docs/TOOL-CONVENTION.md)）。

| 工具类型 | `index.ps1` 行为 |
|----------|------------------|
| **无二级菜单**（多数工具） | 直接进入该工具主流程 |
| **有二级菜单**（如 node） | 无参 → 功能菜单；有 `-i`/`-p`/`-d` → 对应二级 |

工具箱 **不** 区分有无二级菜单，一律 `Invoke-Tool → index.ps1 @args`。

### 文件一览

| 文件 | 说明 |
|------|------|
| `index.json` | 注册与配置 |
| **`index.ps1`** | ★ 固定入口：参数解析、路由、调 lib |
| `install.ps1` | Volta 装/升（第三方依赖） |
| `help.md` | 用户帮助 |
| `lib/*.ps1` | 本工具内部模块（命名见下） |

### `lib/` 命名（已在 `tools/node/` 下，不加 `node-` 前缀）

| 文件 | 职责 | 阶段 |
|------|------|------|
| `lib/main.ps1` | 一级功能选择（读 `index.json` → `actions`） | v1 |
| `lib/browse-install.ps1` | 浏览并安装（版本列表 UI） | v1 |
| `lib/pin-project.ps1` | 为项目指定 | v2 |
| `lib/set-default.ps1` | 设置全局默认 | v1.1 |

功能注册在 **`index.json` → `actions`**；`index.ps1` 只负责路由。

原型迁移：`_prototype/node-menu.ps1` → **`lib/browse-install.ps1`**

### 工具参数（`index.ps1` param，透传自 `miao node`）

**模式（互斥）：**

| 参数 | 别名 | 说明 |
|------|------|------|
| `-Install` | `-i` | 直达「浏览并安装」 |
| `-Pin` | `-p` | 直达「为项目指定」（v2） |
| `-SetDefault` | `-d` | 直达「设置全局默认」（v1.1） |

**安装模式专用：**

| 参数 | 默认 | 说明 |
|------|------|------|
| `-PageSize` | 20 | 初始加载版本数 |
| `-LoadMore` | 15 | 滚底追加数量 |
| `-ViewHeight` | 15 | 菜单可见行数 |
| `-LtsOnly` | false | 仅 LTS |

---

## 五、核心流程

```
miao node [@args]
  → index.ps1 @args（无 Ensure-ToolDeps 自动装）
      无模式参数 → lib/main.ps1 → 选 1/2/3 → 对应 lib
      -i / -Install → lib/browse-install.ps1
      -p / -Pin     → lib/pin-project.ps1（v2）
      -d / -SetDefault → lib/set-default.ps1（v1.1）
  → 从 Miao 主菜单进入 → UX 询问返回/退出
  → miao node -i 等直达 → 结束后直接退出
```

---

## 六、UI 行为

继承 [UX.md](../../../docs/UX.md) 与原型：

- 固定视口头尾；列表区固定高度、原地刷新
- 禁止每次按键整屏 `Clear-Host`
- 一级、二级菜单均同一规范

原型参考：`_prototype/node-menu.ps1`（→ `lib/browse-install.ps1`）

---

## 七、数据与标注（安装列表）

| 标注 | 来源 |
|------|------|
| `[当前]` | `node -v` 与列表项匹配 |
| `[已安装]` | `volta list` 含 `node@x.y.z` |
| `[默认]` | `volta list` 中 `(default)` |
| `[LTS:xx]` | nodejs.org index.json |

---

## 八、错误处理

| 场景 | 处理 |
|------|------|
| 无网络 | 拉取失败，提示检查网络 |
| Volta 不可用 | 不进入菜单 |
| 用户 Esc | 一级 Esc → 退出工具；二级 Esc → 回一级（v1 仅一层时可退出） |
| install / pin 失败 | 显示 stderr，停留供阅读 |
| `-p` 无 package.json | 提示需在项目目录执行（v2） |

---

## 九、开发阶段

| 阶段 | 交付 |
|------|------|
| **v1** | `index.ps1` + `lib/main.ps1` + `lib/browse-install.ps1` + `-i`；菜单 [2][3] 预留 |
| **v1.1** | `lib/set-default.ps1` + `-d` |
| **v2** | `lib/pin-project.ps1` + `-p` |

---

## 十、待完善项（非阻塞 v1）

- [ ] `-LtsOnly` 写入 help.md 推荐场景（第 10 步）
- [ ] v1 菜单 [2][3] 灰显文案
- [ ] install 成功后是否询问 pin（默认否）
