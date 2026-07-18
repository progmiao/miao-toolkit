# miao-toolkit

**程序喵 Miao** — Windows 个人工具百宝箱（桌面版）。

> 产品方向与方案：见 [PRODUCT-DIRECTION.md](PRODUCT-DIRECTION.md)。  
> 技术栈：**.NET 10 + Vue 3 + TypeScript**（WPF WebView2 宿主）。

## 当前工程

| 路径 | 说明 |
|------|------|
| [`desktop/`](desktop/) | **新主工程**（请在此继续开发） |
| [`cli/`](cli/) | 旧 PowerShell CLI（**仅功能参考**，非运行时） |
| [`PRODUCT-DIRECTION.md`](PRODUCT-DIRECTION.md) | 已敲定方向（换机续作必读） |

## 快速开始

```powershell
cd desktop
.\dev.ps1
```

一条命令同时起 Vue（Vite 热更新）和 `Miao` 宿主。细节见 [desktop/README.md](desktop/README.md)。

## 旧 CLI（仅备份）

```powershell
cd cli
.\dev\dev-miao.ps1 list
```
