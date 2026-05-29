# WinGet 发版手册（ProgMiao.Miao）

> 维护者手册。记录 **miao-toolkit** 从 GitHub Release 到 **winget 社区源** 的完整流程，含首版（v0.1.0）实际踩坑与处理。  
> GitHub Release 打包见 [RELEASE.md](../docs/RELEASE.md)；manifest 模板见 [../winget/](../winget/)。

## 一、总览

| 项目 | 值 |
|------|-----|
| 源码仓库 | [ProgMiao/miao-toolkit](https://github.com/ProgMiao/miao-toolkit)（**Public**） |
| winget Package Id | `ProgMiao.Miao` |
| winget Moniker | `miao` |
| 用户安装命令 | `winget install miao` |
| 社区 manifest 仓库 | [microsoft/winget-pkgs](https://github.com/microsoft/winget-pkgs)（需 **Fork** 后提 PR） |
| 本仓库 manifest 草稿 | `winget/manifests/p/ProgMiao/Miao/`（不进安装 zip） |
| 安装包类型 | `zip` + `NestedInstallerType: portable` |
| 入口文件 | `Miao\bin\miao.cmd` → 命令别名 `miao` |

```text
miao-toolkit (main)
  → pack.ps1 → GitHub Release (zip)
  → 更新 winget/manifests SHA256
  → winget-pkgs Fork → PR
  → 合并后用户 winget install miao
```

---

## 二、发版前检查清单

首版或每次新版本前，逐项确认：

| # | 检查项 | 说明 |
|---|--------|------|
| 1 | 仓库 **Public** | 私有仓 Release 无法被 winget 匿名下载 |
| 2 | 根目录 **LICENSE** | 建议 MIT；winget locale 需 `License` + `LicenseUrl` |
| 3 | **`package/bin/` 已纳入 Git** | 见 [§五.1](#51-packagebin-被-gitignore-忽略) |
| 4 | `package/core/manifest.json` | `version`、`releaseDate` 已更新 |
| 5 | `.\release\pack.ps1` 可成功 | 输出 `dist/Miao-<ver>-win.zip` + SHA256 |
| 6 | GitHub Release | tag `v<version>`，上传同名 zip |
| 7 | Release zip 与本地 pack **SHA256 一致** | 见 [§五.2](#52-release-zip-与-git-不一致) |
| 8 | zip 内含 `Miao\bin\miao.cmd` | winget portable 入口 |
| 9 | 推送权限 | 对 `ProgMiao/miao-toolkit` 有 write（或走 Fork+PR） |

---

## 三、阶段 A：GitHub Release（miao-toolkit）

### A1. 版本与合并

```powershell
git checkout main
git merge dev   # 如有 dev 分支
# 编辑 package/core/manifest.json：version、releaseDate
git add package/core/manifest.json
git commit -m "release: v0.1.0"
git push origin main
```

### A2. 打包

```powershell
cd <repo-root>
.\release\pack.ps1
# 记录输出的 SHA256
Get-FileHash .\dist\Miao-0.1.0-win.zip -Algorithm SHA256
```

zip 布局：`Miao\bin`、`Miao\core`、`Miao\tools`（已剔除 `DESIGN.md`、`_prototype`）。

### A3. 打 tag 并发布 Release

```powershell
git tag v0.1.0
git push origin v0.1.0
```

GitHub → **Releases** → 选 tag `v0.1.0` → 上传 `dist/Miao-0.1.0-win.zip` → Publish。

### A4. 校验 Release 可匿名下载

```powershell
Invoke-WebRequest -Method Head `
  -Uri "https://github.com/ProgMiao/miao-toolkit/releases/download/v0.1.0/Miao-0.1.0-win.zip"
# 应返回 StatusCode 200

Invoke-WebRequest -Uri "https://github.com/ProgMiao/miao-toolkit/releases/download/v0.1.0/Miao-0.1.0-win.zip" `
  -OutFile "$env:TEMP\check.zip"
(Get-FileHash "$env:TEMP\check.zip" -Algorithm SHA256).Hash
# 应与 pack.ps1 输出一致
```

### A5. 本地试装（可选）

解压 zip 到临时目录，将 `Miao\bin` 加入 PATH，执行 `miao -helper`、`miao list`。

---

## 四、阶段 B：WinGet 社区源（winget-pkgs）

### B1. 一次性准备

1. Fork [microsoft/winget-pkgs](https://github.com/microsoft/winget-pkgs)
2. 克隆你的 Fork：

```powershell
git clone https://github.com/<你的GitHub用户名>/winget-pkgs.git
cd winget-pkgs
```

3. 添加上游（**以后同步用**，Fork 不会自动更新）：

```powershell
git remote add upstream https://github.com/microsoft/winget-pkgs.git
```

> **说明**：Fork 与上游 **不会自动同步**。下次发新版 PR 前建议执行：  
> `git fetch upstream && git checkout master && git merge upstream/master && git push origin master`

### B2. 首版：复制 manifest

从本仓库复制到 Fork（路径保持一致）：

```text
miao-toolkit/winget/manifests/p/ProgMiao/Miao/
  → winget-pkgs/manifests/p/ProgMiao/Miao/
```

文件清单（首版 4 个）：

| 文件 | 用途 |
|------|------|
| `ProgMiao.Miao.yaml` | 版本索引 |
| `0.1.0/ProgMiao.Miao.installer.yaml` | 安装包 URL、SHA256、zip/portable |
| `0.1.0/ProgMiao.Miao.locale.en-US.yaml` | 英文元数据、Moniker、License |
| `0.1.0/ProgMiao.Miao.locale.zh-CN.yaml` | 中文元数据（可选） |

**installer 关键字段（勿抄旧 SHA256，以当前 Release 为准）：**

```yaml
InstallerType: zip
NestedInstallerType: portable
NestedInstallerFiles:
  - RelativeFilePath: Miao\bin\miao.cmd
    PortableCommandAlias: miao
Installers:
  - Architecture: x64
    InstallerUrl: https://github.com/ProgMiao/miao-toolkit/releases/download/v0.1.0/Miao-0.1.0-win.zip
    InstallerSha256: <pack.ps1 或 Release 下载后的 SHA256>
```

同步更新本仓库 `winget/manifests/...` 中的 `InstallerSha256`，便于下次对照。

### B3. 提交分支并推送

```powershell
git checkout -b new-package-ProgMiao.Miao-0.1.0   # 首版
# 或：git checkout -b ProgMiao.Miao-0.1.1          # 新版本

git add manifests/p/ProgMiao/Miao/
git commit -m "New package: ProgMiao.Miao version 0.1.0"
git push origin new-package-ProgMiao.Miao-0.1.0
```

### B4. 创建 Pull Request

1. 打开 Fork 页面 → **Compare & pull request**
2. **base**：`microsoft/winget-pkgs` → `master`
3. **标题**：`New package: ProgMiao.Miao version 0.1.0`（新版本用 `New version: ...`）
4. **正文** 建议包含：官方仓库链接、安装包 URL、本地试装说明

PR 链接形如：`https://github.com/microsoft/winget-pkgs/pull/<编号>`

### B5. 本地试装（PR 合并前）

```powershell
winget install -m "G:\miao\miao-toolkit\winget\manifests\p\ProgMiao\Miao\0.1.0" ProgMiao.Miao --force
```

新开 PowerShell：`miao -helper`

### B6. 跟踪 PR 进度

打开 PR 页，关注：

| 位置 | 含义 |
|------|------|
| 标题下 **Open / Merged** | 是否已合并 |
| **Checks** 标签页 | 自动校验 |
| 标签 | 见 [§六](#六pr-标签与处理) |
| **Conversation** | CLA 机器人、维护者评论 |

合并后等待索引更新（通常 **数小时～1 天**）：

```powershell
winget source update
winget search ProgMiao.Miao
winget install miao
```

---

## 五、首版踩坑与解决

### 5.1 `package/bin` 被 `.gitignore` 忽略

**现象**：`package/bin/miao.ps1` 本地有，但 `git add` 不上；clone 后无法 `pack.ps1` 打出完整包。

**原因**：模板 `.gitignore` 中 `[Bb]in/` 会忽略所有 `bin` 目录，包括 `package/bin/`。

**解决**：在 `[Bb]in/` 后增加例外：

```gitignore
[Bb]in/
# Miao CLI entry (must stay versioned; see package/bin/)
!package/bin/
!package/bin/**
```

确保 `package/bin/miao.ps1`、`package/bin/miao.cmd` 已提交。可从当前 Release zip 恢复：

```powershell
Expand-Archive -Path "$env:TEMP\Miao-0.1.0-win.zip" -DestinationPath "$env:TEMP\miao-src" -Force
Copy-Item "$env:TEMP\miao-src\Miao\bin\*" package\bin\
```

### 5.2 Release zip 与 Git 不一致

**现象**：GitHub 上的 zip SHA256 与本地 `pack.ps1` 不一致。

**原因**：Release 用旧环境打包（例如 bin 未进 Git、含 `.gitkeep` 等）。

**解决**：

1. 在 **main** 上重新 `.\release\pack.ps1`
2. GitHub Release **Edit** → 删除旧 zip → 上传新 zip（**不改 tag**）
3. 用新 SHA256 更新 `winget/.../ProgMiao.Miao.installer.yaml`

### 5.3 `git push` 403 Permission denied

**现象**：

```text
Permission to progmiao/miao-toolkit.git denied to program-meow
```

**原因**：当前 Git 凭据是账号 A，仓库属于组织/账号 B，A 无写权限。

**解决（择一）**：

| 方式 | 做法 |
|------|------|
| 加协作者 | 用 `ProgMiao` 管理员将 `program-meow` 加为 **Write** |
| 换凭据 | 凭据管理器删除 `git:https://github.com`，再 push 时用有权限账号登录 |
| Fork 流程 | Fork 到自己账号 → push 到 Fork → 对主仓开 PR |

公开仓库 **不等于** 任何人都能 push 到 `origin`。

### 5.4 LICENSE

**要求**：winget locale manifest 需要 `License`、`LicenseUrl`。

**做法**：仓库根目录添加无扩展名文件 **`LICENSE`**（非 `LICENSE.md`）。首版使用 **MIT**，与 `winget` locale 中一致：

```yaml
License: MIT
LicenseUrl: https://github.com/ProgMiao/miao-toolkit/blob/main/LICENSE
```

GitHub 添加：仓库 → Add file → 文件名 `LICENSE` → 选 MIT 模板 → Commit。

---

## 六、PR 标签与处理

参考 [winget-pkgs ValidationFailureGuide](https://github.com/microsoft/winget-pkgs/blob/master/doc/ValidationFailureGuide.md)。

| 标签 | 含义 | 你要做什么 |
|------|------|------------|
| **Needs-CLA** | 未签贡献者协议 | 在 PR 评论发：`@microsoft-github-policy-service agree`（**不需引用回复**） |
| **Internal-Error-PR** | 微软流水线内部错误 | **一般不改 manifest**；等待或 PR 留言请 re-run |
| **Azure-Pipeline-Passed** | 自动测试通过 | 等待维护者 merge |
| **Validation-Completed** | 校验完成 | 等待 merge |
| **Needs-Author-Feedback** | manifest/安装有问题 | 看评论与 Checks 日志，修改 yaml 后 push |
| **Merged** | 已合并 | 等索引，`winget search` 验证 |

### 6.1 签 CLA（Needs-CLA）

- 说明页 [cla.opensource.microsoft.com](https://cla.opensource.microsoft.com/microsoft/winget-pkgs) **没有登录按钮**，签字在 **PR 评论**完成。
- 个人贡献（常用）：

```text
@microsoft-github-policy-service agree
```

- 代表公司（需授权）：

```text
@microsoft-github-policy-service agree company="ProgMiao"
```

签完后等 `license/cla` 检查变绿，`Needs-CLA` 标签消失。全微软开源仓库 **只需签一次**。

### 6.2 Internal-Error-PR

**不是**你的包写错了。在 PR 留言即可（不必改文件）：

```text
Validation failed with Internal-Error-PR. Could you please re-run the pipeline? Thanks.
```

若数日无进展，可在 PR 中 @ 维护者或参考社区 [Internal-Error issues](https://github.com/microsoft/winget-pkgs/issues?q=Internal-Error)。

---

## 七、后续版本（0.1.1+）

### 7.1 miao-toolkit

1. 更新 `package/core/manifest.json`
2. `.\release\pack.ps1` → 上传新 Release（tag `v0.1.1`）
3. 记录新 SHA256

### 7.2 winget manifest

1. 在本仓库复制 `winget/manifests/p/ProgMiao/Miao/0.1.0/` → `0.1.1/`
2. 更新 `PackageVersion`、`InstallerUrl`、`InstallerSha256`、`ReleaseDate`
3. 更新 `ProgMiao.Miao.yaml` 的 `PackageVersion`

### 7.3 winget-pkgs PR

```powershell
cd winget-pkgs
git fetch upstream
git checkout master
git merge upstream/master
git checkout -b ProgMiao.Miao-0.1.1
# 复制/更新 manifests/p/ProgMiao/Miao/
git add manifests/p/ProgMiao/Miao/
git commit -m "New version: ProgMiao.Miao version 0.1.1"
git push origin ProgMiao.Miao-0.1.1
```

PR 标题：`New version: ProgMiao.Miao version 0.1.1`

---

## 八、发版后用户侧验证

```powershell
winget source update
winget search miao
winget show ProgMiao.Miao
winget install miao
```

新开终端：

```powershell
miao -helper
miao list
winget upgrade miao   # 下一版发布后
```

---

## 九、相关链接

| 资源 | URL |
|------|-----|
| 源码 Release | https://github.com/ProgMiao/miao-toolkit/releases |
| winget-pkgs | https://github.com/microsoft/winget-pkgs |
| 提交 manifest 说明 | https://learn.microsoft.com/en-us/windows/package-manager/package/repository |
| CLA 说明 | https://cla.opensource.microsoft.com/microsoft/winget-pkgs |
| 校验失败指南 | https://github.com/microsoft/winget-pkgs/blob/master/doc/ValidationFailureGuide.md |
| manifest 草稿目录 | [../winget/](../winget/) |

---

## 十、首版时间线（实录摘要）

| 步骤 | 状态 |
|------|------|
| 仓库改 Public | ✅ |
| 添加 MIT `LICENSE` | ✅ |
| 修复 `.gitignore`，提交 `package/bin/` | ✅ |
| Release `v0.1.0` + zip | ✅ |
| 替换 Release zip 与 pack SHA256 对齐 | ✅ |
| 创建 `winget/manifests` 草稿 | ✅ |
| Fork winget-pkgs，push 分支，开 PR | ✅ |
| 签 CLA（`@microsoft-github-policy-service agree`） | ✅ |
| 等待 `Internal-Error-PR` 清除 / merge | 进行中 |
| `winget install miao` 公开验证 | PR 合并 + 索引更新后 |
