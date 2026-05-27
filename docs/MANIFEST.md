# core/manifest.json 配置说明

> 状态：**草案**（与当前实现一致：2026-05）

## 一、文件位置与职责

| 项 | 说明 |
|----|------|
| **源码路径** | `package/core/manifest.json` |
| **安装后路径** | `%LOCALAPPDATA%\Miao\core\manifest.json` |
| **读取入口** | `Get-Manifest()`（`package/core/lib/config/Paths.ps1`） |
| **职责** | 工具箱**产品元数据**、**发版信息**、**全局列表分页**；**不含**界面文案、列表列宽等 |

随 winget 包发布；用户本机由 `miao` 启动时加载并缓存。

### 与其它配置的分工

| 配置 | 路径 | 内容 |
|------|------|------|
| **manifest** | `core/manifest.json` | 版本、仓库、UA、`pageSize`、logo、邮箱等 |
| **i18n** | `core/i18n/*.json` | 界面文案（`common.*` 公共层 + `page.*` 页面层，见 [I18N.md](I18N.md)） |
| **列表布局常量** | `core/lib/config/ListLayout.ps1` | 列宽、列间距、CLI 前缀、编号规则、品牌分隔线加宽 |
| **工具注册** | `tools/<id>/index.json` | 各子工具 |
| **工具文案** | `tools/<id>/i18n/*.json` | 各工具展示名等（约定，按需添加） |

**原则：** 能翻译的、少改的 UI 常量不进 manifest；manifest 只保留发版与跨工具箱一致的少数项。

---

## 二、字段说明

当前 `manifest.json` 建议按以下逻辑分组理解（JSON 本身为平铺键，顺序仅便于阅读）。

### 品牌与联系（极少修改）

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `shortName` | string | 建议 | 产品短名，用于 i18n 模板 `{shortName}`（如退出提示、logo 占位）。缺省时代码回退为 `Miao`。 |
| `logo` | string | 建议 | 相对 `core/` 的 ASCII 顶栏文件名，默认 `ascii-logo.txt`。 |
| `email` | string | 否 | 顶栏联系邮箱；空则不显示邮箱行。旧包 `contact.email` 仍可读（兼容）。 |

**不在 manifest 的展示名：**

- 完整标题、描述、作者名 → `core/i18n/zh.json` / `en.json` 的 `brand.title`、`brand.description`、`brand.author`（中文「程序喵」/ 英文 `ProgMiao`）。

### 发版（每次发布由脚本或人工维护）

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `version` | string | 是 | 工具箱 semver，**唯一版本真相源**。用于 `miao version`、顶栏、设置页、更新对比。开发可用 `0.1.0-dev` 后缀。 |
| `releaseDate` | string | 否 | **本机安装包**的发布日期（`yyyy-MM-dd`）。空则界面显示 `-`。远程最新版日期来自 GitHub API，不读此字段。建议正式发布由发版脚本写入；开发源仓库可留空。 |

Git tag、winget `PackageVersion` 应与 `version` 对齐，但不在本文件内重复维护其它名称。

### 更新与网络（极少修改）

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `repository` | string | 建议 | GitHub `owner/repo`，用于会话内更新提示、`releases/latest` 检查。空则跳过远程版本检查。 |
| `userAgent` | string | 否 | 访问 GitHub API 的 HTTP User-Agent。缺省为 `Miao-Toolkit`。 |

### 列表（全局唯一可调分页粒度）

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `pageSize` | number | 建议 | **所有** `Show-PaginatedMenu` 列表的每页行数（←→ 翻页）；Shell 列表视口行数亦参考此值。默认 `10`。 |

- **翻页**与**滚底再加载一批**在「每批条数」上共用此值；当前实现以翻页为主，不再单独配置 `loadMore`。
- 编号显示（补零、位数）、列宽、是否表头等 → 见 `ListLayout.ps1` 与 [UX.md](UX.md)，**不在 manifest 配置**。

---

## 三、示例

```json
{
  "shortName": "Miao",
  "logo": "ascii-logo.txt",
  "email": "455855199@qq.com",

  "version": "0.1.0-dev",
  "releaseDate": "2026-05-24",

  "repository": "ProgMiao/miao-toolkit",
  "userAgent": "Miao-Toolkit",

  "pageSize": 20
}
```

---

## 四、代码读取与兼容

| 能力 | 函数 / 模块 |
|------|-------------|
| 读取 manifest | `Get-Manifest` |
| 模板变量（版本、日期、shortName 等） | `Get-ManifestTemplateVars` |
| 列表每页行数 | `Get-PagingPageSize` / `Get-MenuPageSize` |
| 工具列表命令列 `miao node` | `Get-ToolMenuCommand`（前缀来自 `ListLayout.ps1` 常量） |
| 首页多列宽 | `Get-ToolListColumnWidths`（`ListLayout.ps1`） |

**旧字段兼容（读取回退，新包不必再写）：**

| 已废弃写法 | 回退行为 |
|------------|----------|
| `paging.pageSize` | 若无顶层 `pageSize` 则读此项 |
| `menu.pageSize` | 更旧安装包 |
| `contact.email` | 若无顶层 `email` |
| `packageName`、`author`、`menu.*` | 已移除，不再使用 |

---

## 五、维护约定

| 场景 | 做法 |
|------|------|
| 改界面中英文 | 改 `core/i18n/`，不改 manifest |
| 改首页列宽、列间距 | 改 `ListLayout.ps1` |
| 发新版本 | 更新 `version`（+ `releaseDate`），打 tag，同步 winget |
| 调列表每页条数 | 只改 `pageSize` |
| 新工具展示名 | `tools/<id>/i18n/`，不写进工具箱 manifest |

---

## 六、相关文档

- [ARCHITECTURE.md](ARCHITECTURE.md) — `core/` 目录职责  
- [UPDATE.md](UPDATE.md) — 版本与发布  
- [UX.md](UX.md) — 列表交互（无表头、编号、翻页）  
- [TOOL-CONVENTION.md](TOOL-CONVENTION.md) — 工具 `index.json` 约定  
