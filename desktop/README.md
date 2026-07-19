# Miao

**.NET 10 (C# / WPF + WebView2) + Vue 3 + TypeScript**  
个人工具百宝箱：常用网站、软件安装管理、工具集（占位）。发布产物为 `Miao.exe`。

产品方向见根目录 [`PRODUCT-DIRECTION.md`](../PRODUCT-DIRECTION.md)。  
旧 CLI 在 [`cli/`](../cli/)，**仅作功能结果参考**，桌面不调用其运行时，也不沿用其实现思路。

## 结构

```
desktop/
├── Miao.sln
├── seeds/                # 种子数据（打包进输出目录，启动灌库）
│   ├── groups.json
│   ├── software/         # daily.json / dev.json
│   ├── sites/seed.json
│   ├── utilities/registry.json
│   └── i18n/             # 集中多语言
├── src/
│   ├── Miao.App/         # 壳（输出 Miao.exe）
│   ├── Miao.Common/      # DTO / 分组常量
│   ├── Miao.Data/        # SQLite + 路径 + SeedLoader
│   ├── Miao.Software/    # 软件目录 + Handlers + JobRunner
│   ├── Miao.Sites/       # 常用网站
│   └── Miao.Utilities/   # 工具集（占位）
└── ui/                   # Vue 3 + Vite
```

侧栏顺序：**常用网站 → 日常工具 → 开发工具 → 工具集 → 设置（最后）**。

## 开发

需要：**.NET 10 SDK**、**Volta**（管理 Node）、已安装 WebView2 Runtime。

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
