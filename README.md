# miao-toolkit

**程序喵 Miao 工具包** — Windows 下的统一 CLI 工具集合。

> 当前阶段：**设计文档评审中，package/ 开发预览壳已可本地运行。**

## 安装（用户）

```powershell
winget install miao              # 推荐（Moniker）
winget install ProgMiao.Miao     # 同上（Package Id）
```

## 开发预览（未 winget 发版）

在 **仓库根目录** 打开 PowerShell（含 `dev/`、`package/` 的目录）：

```powershell
.\dev\dev-miao.ps1 list
.\dev\dev-miao.ps1 -helper
.\dev\dev-miao.ps1 node -Install
```

路径由脚本内 `$PSScriptRoot` 解析，**与仓库 clone 到哪块盘无关**。

## 仓库结构

```
miao-toolkit/
├── dev/                     # 仅开发用（不进安装包）
├── docs/                    # 工具箱设计文档（平铺）
└── package/
    ├── bin/
    ├── core/
    └── tools/<id>/
```

## 设计文档

从 [`docs/README.md`](docs/README.md) 开始，按文档确认顺序评审。

## 发布

- 整体发版：`ProgMiao.Miao`（Moniker: `miao`）
- 更新：`winget upgrade miao` 或 `miao update`
- 工具依赖：`miao install`
