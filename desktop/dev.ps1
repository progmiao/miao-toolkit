# One-command desktop development: Vite (HMR) + Miao host（UI 仅在宿主 WebView2 中打开）
# Usage:  cd desktop; .\dev.ps1
#
# 依赖：Volta 管理的 Node（见 ui/package.json → volta.node）、.NET 10 SDK
$ErrorActionPreference = 'Stop'
$ui = Join-Path $PSScriptRoot 'ui'
$proj = Join-Path $PSScriptRoot 'src\Miao.App\Miao.App.csproj'
$viteUrl = 'http://localhost:5173/'
$pkgJson = Join-Path $ui 'package.json'

function Test-ViteUp {
    try {
        $req = [System.Net.WebRequest]::Create($viteUrl)
        $req.Timeout = 400
        $resp = $req.GetResponse()
        $resp.Close()
        return $true
    }
    catch {
        return $false
    }
}

function Stop-PortListeners([int]$Port) {
    try {
        $conns = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
        foreach ($c in $conns) {
            if ($c.OwningProcess -gt 0) {
                Stop-Process -Id $c.OwningProcess -Force -ErrorAction SilentlyContinue
            }
        }
    }
    catch {
        # optional helper; ignore if cmdlet unavailable
    }
}

# 从 package.json 的 volta.node 读取期望版本；没有则默认 22.23.1
function Get-PinnedNodeVersion {
    param([string]$PackageJsonPath)
    $raw = Get-Content -Raw -Path $PackageJsonPath
    $m = [regex]::Match($raw, '"volta"\s*:\s*\{[^}]*"node"\s*:\s*"([^"]+)"')
    if ($m.Success) {
        return $m.Groups[1].Value
    }
    return '22.23.1'
}

# 确保 Volta 已安装，并安装 package.json 指定的 Node 版本
function Ensure-VoltaNode {
    param([string]$Version)

    $voltaCmd = Get-Command volta -ErrorAction SilentlyContinue
    if (-not $voltaCmd) {
        throw @"
未找到 Volta。请先安装：https://volta.sh
或：winget install Volta.Volta
安装后重新打开终端，再运行 .\dev.ps1
"@
    }

    Write-Host "Volta: ensuring node@$Version ..."
    & volta install "node@$Version"
    if ($LASTEXITCODE -ne 0) {
        throw "volta install node@$Version failed"
    }
}

if (-not (Test-Path $pkgJson)) {
    throw "UI project not found: $ui"
}

$nodeVersion = Get-PinnedNodeVersion -PackageJsonPath $pkgJson
Ensure-VoltaNode -Version $nodeVersion

Push-Location $ui
try {
    # 在 ui 目录下 pin，保证本目录 npm/node 走 Volta 版本
    & volta pin "node@$nodeVersion" | Out-Null
    Write-Host ("Node (volta): " + (& node -v))

    if (-not (Test-Path 'node_modules')) {
        Write-Host 'npm install...'
        npm.cmd install
        if ($LASTEXITCODE -ne 0) { throw 'npm install failed' }
    }
}
finally {
    Pop-Location
}

$startedVite = $false

try {
    if (-not (Test-ViteUp)) {
        Write-Host 'Starting Vite on :5173 ...'
        # WorkingDirectory=ui → Volta 按 package.json 选用 Node
        Start-Process -FilePath 'npm.cmd' -ArgumentList 'run', 'dev' `
            -WorkingDirectory $ui -WindowStyle Minimized | Out-Null
        $startedVite = $true

        $deadline = (Get-Date).AddSeconds(60)
        while (-not (Test-ViteUp)) {
            if ((Get-Date) -gt $deadline) {
                throw 'Vite did not become ready within 60s. Try: cd desktop/ui; npm run dev'
            }
            Start-Sleep -Milliseconds 300
        }
        Write-Host 'Vite ready.'
    }
    else {
        Write-Host 'Vite already running; reusing it.'
    }

    # UI 由宿主 WebView2 加载 Vite；不再额外打开系统浏览器
    $env:MIAO_UI_DEV = '1'
    Write-Host 'Starting Miao host (edit desktop/ui for HMR)...'
    Write-Host 'Close the app window or press Ctrl+C here to stop.'
    dotnet run --project $proj --no-launch-profile
}
finally {
    if ($startedVite) {
        Write-Host 'Stopping Vite...'
        Stop-PortListeners -Port 5173
    }
}
