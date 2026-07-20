# One-click desktop dev: Vite (HMR) + Miao host (UI only in WebView2)
# Usage:  cd desktop; .\dev.ps1
#
# Requires: .NET 10 SDK, Volta (auto-installed by this script), WebView2 Runtime.
# Volta provides the Node version pinned in ui/package.json for local UI work.
# In-app "Dev Tools -> Volta" remains the product install path for release testing.
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

# Read pinned Node from package.json volta.node; default 22.23.1
function Get-PinnedNodeVersion {
    param([string]$PackageJsonPath)
    $raw = Get-Content -Raw -Path $PackageJsonPath
    $m = [regex]::Match($raw, '"volta"\s*:\s*\{[^}]*"node"\s*:\s*"([^"]+)"')
    if ($m.Success) {
        return $m.Groups[1].Value
    }
    return '22.23.1'
}

# Refresh session PATH and prepend common Volta install dirs
function Update-SessionPathForVolta {
    $pf86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    $extra = @(
        (Join-Path $env:USERPROFILE '.volta\bin'),
        (Join-Path $env:LOCALAPPDATA 'Volta\bin'),
        (Join-Path $env:ProgramFiles 'Volta')
    )
    if ($pf86) {
        $extra += (Join-Path $pf86 'Volta')
    }
    $extra = $extra | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $parts = @($extra) + @(($user -split ';') + ($machine -split ';') + ($env:Path -split ';')) |
        Where-Object { $_ -and $_.Trim() } |
        Select-Object -Unique
    $env:Path = ($parts -join ';')
}

# Resolve volta.exe from PATH or common install locations
function Resolve-VoltaCommand {
    Update-SessionPathForVolta
    $cmd = Get-Command volta -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd }

    $pf86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    $candidates = @(
        (Join-Path $env:USERPROFILE '.volta\bin\volta.exe'),
        (Join-Path $env:LOCALAPPDATA 'Volta\bin\volta.exe'),
        (Join-Path $env:ProgramFiles 'Volta\volta.exe')
    )
    if ($pf86) {
        $candidates += (Join-Path $pf86 'Volta\volta.exe')
    }
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) {
            $bin = Split-Path -Parent $c
            if ($env:Path -notlike "*$bin*") {
                $env:Path = "$bin;$env:Path"
            }
            return (Get-Command volta -ErrorAction SilentlyContinue)
        }
    }
    return $null
}

# Install Volta via winget when missing (local bootstrap only, not product flow)
function Install-VoltaWithWinget {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        throw 'winget not found. Install Volta from https://volta.sh then re-run .\dev.ps1'
    }
    Write-Host 'Volta not found. Installing via winget (Volta.Volta) for local UI development...'
    Write-Host 'If a UAC / install dialog appears, please allow it (cancel = exit 1602).'
    & winget install --id Volta.Volta -e `
        --accept-package-agreements `
        --accept-source-agreements `
        --disable-interactivity
    # exit 0 or -1978335189 (already installed) count as success
    $code = $LASTEXITCODE
    if ($code -ne 0 -and $code -ne -1978335189) {
        throw (
            "winget install Volta.Volta failed (exit $code).`n" +
            "Allow the installer dialog, or run: winget install Volta.Volta`n" +
            "Then re-run .\dev.ps1"
        )
    }
    Update-SessionPathForVolta
}

# Ensure Volta + package.json-pinned Node are available
function Ensure-VoltaNode {
    param([string]$Version)

    $voltaCmd = Resolve-VoltaCommand
    if (-not $voltaCmd) {
        Install-VoltaWithWinget
        $voltaCmd = Resolve-VoltaCommand
    }
    if (-not $voltaCmd) {
        throw (
            "Volta still not found after install. Open a NEW terminal and run .\dev.ps1 again.`n" +
            "Or install manually: winget install Volta.Volta / https://volta.sh"
        )
    }

    Write-Host ("Volta: " + $voltaCmd.Source)
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
    # Pin in ui dir so npm/node use Volta-managed version
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
