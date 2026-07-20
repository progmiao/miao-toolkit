# Miao

**.NET 10 (C# / WPF + WebView2) + Vue 3 + TypeScript**  
个人工具百宝箱：常用网站、软件安装管理、工具集（占位）。发布产物为 `Miao.exe`。

产品方向见根目录 [`PRODUCT-DIRECTION.md`](../PRODUCT-DIRECTION.md)。  
旧 CLI 在 [`cli/`](../cli/)，**仅作功能结果参考**，桌面不调用其运行时，也不沿用其实现思路。

## 结构

按侧栏英文分区，详见 [`STRUCTURE.md`](./STRUCTURE.md)。  
开发约定（新增工具、公共子组件）见 [`DEVELOPMENT.md`](./DEVELOPMENT.md)。

| 中文 | 目录 |
|------|------|
| 常用网站 | `sites` |
| 日常工具 | `daily` |
| 开发工具 | `dev`（不用 tools） |
| 工具集 | `utilities` |

入口页均为分区内 `index.vue`。

侧栏顺序：**常用网站 → 日常工具 → 开发工具 → 工具集 → 设置**。

## 开发

需要：**.NET 10 SDK**、**Volta**（提供 UI 用 Node）、已安装 WebView2 Runtime。

`.\dev.ps1` 会检测 Volta；若本机没有则用 winget 补装，再按 `ui/package.json` 锁定 Node，然后启动 Vite + 宿主。  
（这是**本地开发引导**；应用内「开发工具 → Volta」的产品安装链路等打包发布后再测。）

若出现安装弹窗请允许；取消会导致 winget 失败（如 exit 1602）。

```powershell
cd desktop
.\dev.ps1
```

## 发布构建

```powershell
cd desktop
.\build.ps1
```

## 种子与数据

| 域 | 种子升级 | 客户端维护 |
|----|----------|------------|
| 软件 / 分组 / i18n | 全量覆盖 | 否（改 seeds 发版） |
| 网站 | 仅替换 `source=system`，保留用户项 | 用户项可增删改；系统项只读 |
| 工具集 | registry 预留 | 本期仅占位页 |

## IPC（摘要）

| type | 含义 |
|------|------|
| `get-catalog` / `catalog` | 软件清单 |
| `run-job` / `job-event` / `job-finished` | 安装任务 |
| `sites.*` | 常用网站列表/保存/打开/导入导出 |
| `utilities.list` | 工具集占位 |
| `get-i18n` / `i18n` | 集中文案 |
| `get-app-info` / `app-info` | 应用名与版本 |
