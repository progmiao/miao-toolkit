# CLI 工具箱（脚本层）

> 原 PowerShell 控制台工具箱实现。  
> **产品主入口已转为** [`desktop/`](../desktop/)（.NET + Vue）。

本目录保留可运行的 CLI 包与安装脚本，供桌面 Job 过渡调用，以及对照/打包参考。

## 内容说明

| 路径 | 用途 |
|------|------|
| `package/` | 运行时：`bin` / `core` / `tools` |
| `dev/` | 本地调试入口 |
| `test/` | 测试脚本 |
| `docs/` | 旧设计文档 |
| `release/` | CLI zip 打包与 WinGet 发版手册 |
| `winget/` | winget manifest 草稿 |
| `dist/` | 历史打包输出（若有） |
| `package.json` | Volta 钉 Node |

## 新产品方向

见仓库根目录 [`PRODUCT-DIRECTION.md`](../PRODUCT-DIRECTION.md)。

本地预览 CLI：

```powershell
cd cli
.\dev\dev-miao.ps1 list
```
