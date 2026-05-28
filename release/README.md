# 发布脚本

维护者在 **`main`** 分支打 GitHub Release 时使用。

| 脚本 | 说明 |
|------|------|
| [`pack.ps1`](pack.ps1) | 从 `package/` 打包 `Miao-<version>-win.zip` 到仓库根 `dist/` |

```powershell
# 在仓库根目录
.\release\pack.ps1
```

版本号默认读取 `package/core/manifest.json` 的 `version`；可用 `-Version`、`-OutputDir` 覆盖。

完整流程见 [docs/RELEASE.md](../docs/RELEASE.md)。
