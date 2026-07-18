# Miao

**.NET 10 (C# / WPF + WebView2) + Vue 3 + TypeScript**  
个人工具百宝箱：工具管理（P0）+ 日常小工具（P1）。发布产物为 `Miao.exe`。

产品方向见根目录 [`PRODUCT-DIRECTION.md`](../PRODUCT-DIRECTION.md)。  
旧 CLI 实现在 [`cli/`](../cli/)，**仅作功能结果参考**，桌面不调用其运行时。

## 结构

```
desktop/
├── Miao.sln
├── plugins/              # 内置插件：daily/ + dev/ + _registry.json
├── src/
│   ├── Miao.App/         # 壳（输出 Miao.exe）
│   ├── Miao.Common/      # 公共 DTO / 分组常量
│   ├── Miao.Data/        # SQLite + 路径
│   └── Miao.Tools/       # PluginHost + Handlers + JobRunner
└── ui/                   # Vue 3 + Vite（侧栏：日常工具 / 开发工具）
```

用户扩展插件目录（预留）：`%LocalAppData%\Miao\plugins\{daily|dev}\`（与内置合并，同 id 覆盖）。

## 开发

需要：**.NET 10 SDK**、**Volta**（管理 Node）、已安装 WebView2 Runtime（Win10/11 通常已有）。

### Node（Volta）

前端 Node 版本写在 `ui/package.json` 的 `volta.node`（当前 **22.23.1**）。`.\dev.ps1` 会自动：

1. 检测 Volta  
2. `volta install node@<版本>`  
3. 在 `ui/` 下 `volta pin`  

本机首次若没有 Volta：

```powershell
winget install Volta.Volta
# 重开终端后
cd desktop
.\dev.ps1
```

也可手动：

```powershell
cd desktop/ui
volta install node@22.23.1
volta pin node@22.23.1
node -v   # 应显示 v22.23.1
```

### 一条命令启动

```powershell
cd desktop
.\dev.ps1
```

会：确保 Volta Node →（必要时）`npm install` → 起 Vite `:5173` → **打开浏览器**（F12 调样式）→ `dotnet run` 打开宿主窗口。改 `ui/` 即可热刷新。

| 方式 | 效果 |
|------|------|
| `.\dev.ps1` | Vite + **浏览器** + 宿主；样式用浏览器 F12，IPC 用宿主 |
| 只 `cd ui; npm run dev` | 仅前端（Vite 也会 `open` 浏览器） |
| 只 `dotnet run --project src/Miao.App` | 无 Vite 时用 `wwwroot`（无热更新） |
| `.\build.ps1` | 发布：打进 `wwwroot` 再编 `Miao.exe` |

手动分两终端也可以：

```powershell
# 终端 1
cd desktop/ui
npm install
npm run dev

# 终端 2
cd desktop
$env:MIAO_UI_DEV = '1'
dotnet run --project src/Miao.App
```

## 发布构建

```powershell
cd desktop/ui
npm install
npm run build
# 拷到宿主输出目录
New-Item -ItemType Directory -Force ..\src\Miao.App\wwwroot | Out-Null
Copy-Item -Recurse -Force dist\* ..\src\Miao.App\wwwroot\

cd ..
dotnet build src/Miao.App -c Release
```

未设置 `MIAO_UI_DEV` 时，宿主加载 `wwwroot/index.html`。

## 工具安装（桌面正式路径）

- 清单：`ToolCatalog`（C#）
- 调度：`ToolActionDispatcher` → 各 `IToolActionHandler`
- **`cli/` 仅作功能结果参考**，不作为 Job 后端

## IPC

Vue ↔ C# 通过 WebView2 `postMessage` JSON：

| type | 方向 | 含义 |
|------|------|------|
| `get-catalog` / `catalog` | 双向 | 工具清单 |
| `run-job` / `job-event` / `job-finished` | 双向 | 桌面安装器任务 |
| `cancel-job` | UI→Host | 取消 |
| `get-app-info` / `app-info` | 双向 | 应用名与版本 |
