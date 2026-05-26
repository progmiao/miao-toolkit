# node — 第三方依赖 Volta 卸载
# 由 miao uninstall node 或工具内「卸载」调用；成功后由 core 删除 deps-state 条目

$ErrorActionPreference = 'Stop'

function Test-DependencyCommandAvailable {
    param([string]$CheckCommand)

    if ([string]::IsNullOrWhiteSpace($CheckCommand)) { return $false }
    $exe = ($CheckCommand -split '\s+', 2)[0]
    return [bool](Get-Command $exe -ErrorAction SilentlyContinue)
}

function Test-WingetCliAvailable {
    return [bool](Get-Command winget -ErrorAction SilentlyContinue)
}

$toolRoot = Split-Path $PSScriptRoot -Parent
$indexPath = Join-Path $toolRoot 'index.json'
$cfg = Get-Content -Raw -Path $indexPath -Encoding UTF8 | ConvertFrom-Json

if (-not (Test-WingetCliAvailable)) {
    Write-Host '未找到 winget，无法执行卸载。' -ForegroundColor Red
    exit 1
}

foreach ($dep in @($cfg.dependencies)) {
    $packageId = if ($dep.install) { [string]$dep.install.packageId } else { '' }
    $checkCommand = if ($dep.checkCommand) { [string]$dep.checkCommand } else { '' }
    $depName = if ($dep.name) { [string]$dep.name } else { $packageId }

    if ([string]::IsNullOrWhiteSpace($packageId)) { continue }

    if (-not (Test-DependencyCommandAvailable -CheckCommand $checkCommand)) {
        Write-Host "$depName 未检测到已安装，跳过 winget 卸载。" -ForegroundColor DarkGray
        continue
    }

    Write-Host "正在卸载 $depName …" -ForegroundColor Cyan
    Write-Host "winget uninstall --id $packageId" -ForegroundColor DarkGray
    & winget uninstall --id $packageId -e --disable-interactivity `
        --accept-package-agreements --accept-source-agreements

    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        Write-Host "winget uninstall 失败 (退出码 $LASTEXITCODE): $packageId" -ForegroundColor Red
        exit 1
    }

    Write-Host "$depName 已卸载。" -ForegroundColor Green
}

exit 0
