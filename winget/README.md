# WinGet manifest（提交到 winget-pkgs 用）

本目录 **不进** `pack.ps1` 安装包，仅供维护者复制到 [microsoft/winget-pkgs](https://github.com/microsoft/winget-pkgs) Fork 后提 PR。

完整发版流程与踩坑见 **[release/WINGET-RELEASE.md](../release/WINGET-RELEASE.md)**。

## 目录结构

```text
winget/manifests/p/ProgMiao/Miao/
├── ProgMiao.Miao.yaml
└── 0.1.0/
    ├── ProgMiao.Miao.installer.yaml
    ├── ProgMiao.Miao.locale.en-US.yaml
    └── ProgMiao.Miao.locale.zh-CN.yaml
```

复制到 winget-pkgs 时，将 `manifests/p/ProgMiao/` 放到 Fork 仓库的 `manifests/p/` 下（路径一致）。

## 本地试装

在 winget-pkgs Fork 根目录，或指定 manifest 目录：

```powershell
winget install -m ".\manifests\p\ProgMiao\Miao\0.1.0" ProgMiao.Miao --force
```

在本仓库中（路径按实际调整）：

```powershell
winget install -m ".\winget\manifests\p\ProgMiao\Miao\0.1.0" ProgMiao.Miao --force
```

## 发新版本

1. 更新 `0.x.y/` 下三份 yaml 的 `PackageVersion`、`InstallerUrl`、`InstallerSha256`、`ReleaseDate`
2. 更新 `ProgMiao.Miao.yaml` 的 `PackageVersion`
3. 向 winget-pkgs 提 PR：`New version: ProgMiao.Miao version 0.x.y`
