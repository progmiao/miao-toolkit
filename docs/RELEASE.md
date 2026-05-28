# 发布流程（GitHub Release）

> 维护者手册。用户安装见 [INSTALL.md](INSTALL.md)；winget 与更新策略见 [UPDATE.md](UPDATE.md)。

## 版本来源

| 字段 | 文件 |
|------|------|
| `version` | `package/core/manifest.json` |
| `releaseDate` | 同上（发版日，ISO 8601） |

发版前在 **`main`** 上更新 manifest，并确保 `dev` 已合并进 `main`。

## 目录

| 路径 | 用途 |
|------|------|
| `release/pack.ps1` | 打 zip（不进安装包） |
| `dist/` | 本地输出目录（gitignore） |
| `package/scripts/` | 未来用户侧 bootstrap / install（非打包脚本） |
| `dev/` | 仅本地开发（预览、UTF-8 BOM 维护） |

## 步骤

### 1. 合并与版本

```powershell
git checkout main
git merge dev
# 编辑 package/core/manifest.json：version、releaseDate
git add package/core/manifest.json
git commit -m "release: v0.1.0"
git push origin main
```

### 2. 打包

```powershell
.\release\pack.ps1
# 输出：dist/Miao-<version>-win.zip 与 SHA256
```

zip 内布局：`Miao\bin`、`Miao\core`、`Miao\tools`（已剔除 `DESIGN.md`、`_prototype`）。

### 3. 打 tag

```powershell
git tag v0.1.0
git push origin v0.1.0
```

tag 名与 manifest `version` 一致，前缀 `v`。

### 4. GitHub Release

1. 仓库 → Releases → Draft a new release
2. Choose tag：`v0.1.0`，Target：`main`
3. 上传 `dist/Miao-0.1.0-win.zip`
4. 首版可勾选 **Pre-release**
5. Publish

### 5. 本机验证（可选）

解压到 `%LOCALAPPDATA%\Miao\`，将 `%LOCALAPPDATA%\Miao\bin` 加入 PATH，运行 `miao`。

首版无 winget 时用户需手动加 PATH；后续 winget 包会处理。

## 后续

- winget-pkgs PR（`ProgMiao.Miao`）
- `package/scripts/bootstrap.ps1`（无 winget 安装）
- 文档中仍引用 `core/version.json` 的段落改为 `manifest.json`
