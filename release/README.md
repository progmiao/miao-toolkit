# 发布脚本

维护者在 **`main`** 分支打 GitHub Release 时使用。

| 文档 / 脚本 | 说明 |
|-------------|------|
| [**WINGET-RELEASE.md**](WINGET-RELEASE.md) | **WinGet 发版全流程**（Release → winget-pkgs PR → 踩坑与 CLA） |
| [docs/RELEASE.md](../docs/RELEASE.md) | GitHub Release 打包步骤 |
| [../winget/](../winget/) | winget manifest 草稿（提交 Fork 用） |
| [`pack.ps1`](pack.ps1) | 从 `package/` 打包 `Miao-<version>-win.zip` 到 `dist/` |

```powershell
# 在仓库根目录
.\release\pack.ps1
```

版本号默认读取 `package/core/manifest.json` 的 `version`；可用 `-Version`、`-OutputDir` 覆盖。
