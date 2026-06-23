# node — Node.js 版本管理

> 本文件为用户向使用说明，安装后可通过 `miao help node` 在 PowerShell 中查看。

## 功能

通过 **Volta** 浏览、安装 Node.js 版本：

- 版本列表按**从新到旧**排列
- 显示 `[当前]`、`[已安装]`、`[默认]`、`[LTS]` 等标记
- 上下键选择，Enter 安装所选版本
- 首次使用会自动安装或更新 Volta 到最新版

## 使用方法

### 从工具列表进入

```powershell
miao
# 选择 node，按 Enter
```

### 直接进入

```powershell
miao node
```

### 仅查看 LTS 版本

```powershell
miao node -LtsOnly
```

## 菜单操作

| 按键 | 作用 |
|------|------|
| ↑ / ↓ | 选择版本 |
| Enter | 安装所选版本 |
| Esc | 取消 |

列表默认显示最新一批版本；继续向下可加载更多。

## 安装完成后

- 执行 `volta install node@<版本>`
- 显示当前 `node -v`

若从 `miao` 主菜单进入，结束后可选择：

- **Enter** — 返回工具列表
- **Q** — 退出 Miao

若使用 `miao node` 直接进入，完成后自动回到 PowerShell。

## 前置条件

- Windows 10 / 11
- PowerShell 5.1+
- 网络（拉取版本列表）
- winget（用于自动安装 Volta；若无，请手动安装 https://volta.sh/）

## 注意

- `miao node` 是 Miao 工具包的子命令，**不是**系统自带的 `node.exe`
- 请勿与 nvm-windows 同时使用，避免 PATH 冲突
- 安装 Volta 后若 `volta` 找不到，请**新开** PowerShell 窗口

## 常见问题

**Q: 提示未找到 Volta？**  
A: 运行 `miao install node` 或手动 `winget install Volta.Volta`，然后重开终端。

**Q: node -v 和预期不一致？**  
A: 确认是否在已 `volta pin` 的项目目录；本工具只负责 install，不自动 pin 项目。

**Q: 如何查看更多命令？**  
A: 运行 `miao -helper`
