# node — 第三方依赖 Volta 安装/更新
# 由依赖管理页或工具内「安装/更新」调用；成功后由 core 写入 deps-state.json

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

function Test-WingetPackageUpgradeAvailable {
    param([string]$PackageId)

    if ([string]::IsNullOrWhiteSpace($PackageId)) { return $false }

    $output = & winget upgrade --id $PackageId -e --disable-interactivity --accept-source-agreements 2>&1 |
        Out-String
    if ($output -match 'No applicable upgrade|No available upgrade|没有适用的升级|找不到可用的升级|没有可用的升级') {
        return $false
    }
    if ($LASTEXITCODE -eq -1978335189) { return $false }
    return ($LASTEXITCODE -eq 0)
}

function Invoke-WingetInstallPackage {
    param([string]$PackageId)

    Write-Host "winget install --id $PackageId" -ForegroundColor DarkGray
    & winget install --id $PackageId -e --disable-interactivity `
        --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        throw "winget install 失败 (退出码 $LASTEXITCODE): $PackageId"
    }
}

function Invoke-WingetUpgradePackage {
    param([string]$PackageId)

    Write-Host "winget upgrade --id $PackageId" -ForegroundColor DarkGray
    & winget upgrade --id $PackageId -e --disable-interactivity `
        --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        throw "winget upgrade 失败 (退出码 $LASTEXITCODE): $PackageId"
    }
}

function Refresh-SessionPath {
    $machine = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [System.Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machine;$user"
}

$toolRoot = Split-Path $PSScriptRoot -Parent
$indexPath = Join-Path $toolRoot 'index.json'
$cfg = Get-Content -Raw -Path $indexPath -Encoding UTF8 | ConvertFrom-Json

if (-not (Test-WingetCliAvailable)) {
    Write-Host '未找到 winget，请先安装「应用安装程序」或 App Installer。' -ForegroundColor Red
    exit 1
}

foreach ($dep in @($cfg.dependencies)) {
    $policy = if ($dep.version) { [string]$dep.version } elseif ($dep.updatePolicy) { [string]$dep.updatePolicy } else { 'latest' }
    $packageId = if ($dep.install) { [string]$dep.install.packageId } else { '' }
    $checkCommand = if ($dep.checkCommand) { [string]$dep.checkCommand } else { '' }
    $depName = if ($dep.name) { [string]$dep.name } else { $packageId }

    if ([string]::IsNullOrWhiteSpace($packageId)) { continue }

    $installed = Test-DependencyCommandAvailable -CheckCommand $checkCommand

    if (-not $installed) {
        Write-Host "正在安装 $depName …" -ForegroundColor Cyan
        Invoke-WingetInstallPackage -PackageId $packageId
        Refresh-SessionPath
        if (-not (Test-DependencyCommandAvailable -CheckCommand $checkCommand)) {
            Write-Host "安装后仍无法运行: $checkCommand。请重开终端后再试。" -ForegroundColor Red
            exit 1
        }
        Write-Host "$depName 安装完成。" -ForegroundColor Green
        continue
    }

    if ($policy.Trim().ToLowerInvariant() -eq 'latest') {
        if (Test-WingetPackageUpgradeAvailable -PackageId $packageId) {
            Write-Host "正在更新 $depName …" -ForegroundColor Cyan
            Invoke-WingetUpgradePackage -PackageId $packageId
            Refresh-SessionPath
            Write-Host "$depName 已更新。" -ForegroundColor Green
        }
        else {
            Write-Host "$depName 已是最新版本。" -ForegroundColor DarkGray
        }
    }
    else {
        Write-Host "$depName 已安装（固定版本策略: $policy），跳过更新。" -ForegroundColor DarkGray
    }
}

exit 0
