# One-click desktop dev: Vite (HMR) + Miao host (UI only in WebView2)
# Usage:  cd desktop; .\dev.ps1
#
# Requires: .NET 10 SDK, Volta (auto-installed by this script), WebView2 Runtime.
# Volta provides the Node version pinned in ui/package.json for local UI work.
# In-app "Dev Tools -> Volta" remains the product install path for release testing.
$ErrorActionPreference = 'Stop'
$ui = Join-Path $PSScriptRoot 'ui'
$proj = Join-Path $PSScriptRoot 'src\Miao.App\Miao.App.csproj'
$viteUrl = 'http://127.0.0.1:5173/'
$viteHost = '127.0.0.1'
$vitePort = 5173
$pkgJson = Join-Path $ui 'package.json'

function Test-ViteUp {
    # TCP only: HttpWebRequest probes can stall on ServicePoint/proxy and keep returning false
    # even while Vite is already listening (browser/curl still work).
    try {
        $client = [System.Net.Sockets.TcpClient]::new()
        try {
            $async = $client.BeginConnect($viteHost, $vitePort, $null, $null)
            if (-not $async.AsyncWaitHandle.WaitOne(400, $false)) {
                return $false
            }
            $client.EndConnect($async)
            return $true
        }
        finally {
            $client.Close()
        }
    }
    catch {
        return $false
    }
}

function Stop-PortListeners([int]$Port) {
    $pids = @()
    try {
        $pids += @(
            Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
                ForEach-Object { $_.OwningProcess }
        )
    }
    catch {
        # NetTCPIP module may be unavailable in some shells
    }
    if (-not $pids -or $pids.Count -eq 0) {
        foreach ($line in @(netstat -ano 2>$null | Select-String ":$Port\s+\S+\s+LISTENING")) {
            if ($line -match '(\d+)\s*$') { $pids += [int]$Matches[1] }
        }
    }
    foreach ($procId in ($pids | Where-Object { $_ -gt 0 } | Select-Object -Unique)) {
        Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
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

# Ensure Volta + package.json-pinned Node are available (and npm usable)
function Test-VoltaNpmHealthy {
    try {
        $out = & npm.cmd --version 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { return $false }
        return [regex]::IsMatch($out, '\d+\.\d+')
    }
    catch {
        return $false
    }
}

function Repair-VoltaNodeImage {
    param([string]$Version)
    $v = $Version.Trim().TrimStart('v', 'V')
    $roots = @()
    if ($env:LOCALAPPDATA) { $roots += (Join-Path $env:LOCALAPPDATA 'Volta') }
    if ($env:USERPROFILE) { $roots += (Join-Path $env:USERPROFILE '.volta') }
    if ($env:VOLTA_HOME) { $roots += $env:VOLTA_HOME.Trim() }
    $roots = $roots | Where-Object { $_ } | Select-Object -Unique

    foreach ($root in $roots) {
        $img = Join-Path $root "tools\image\node\$v"
        if (Test-Path -LiteralPath $img) {
            Write-Host "Removing broken node@$v image: $img"
            Remove-Item -LiteralPath $img -Recurse -Force -ErrorAction SilentlyContinue
        }
        $inv = Join-Path $root 'tools\inventory\node'
        if (Test-Path -LiteralPath $inv) {
            Get-ChildItem -LiteralPath $inv -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Name.StartsWith("node-v$v", [StringComparison]::OrdinalIgnoreCase) } |
                ForEach-Object {
                    Write-Host ("Removing inventory: " + $_.Name)
                    Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                }
        }
    }
}

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

    # Incomplete uninstall can leave a broken image; volta install may skip while npm is dead.
    if (-not (Test-VoltaNpmHealthy)) {
        Write-Host "npm broken for node@$Version (often after incomplete uninstall). Repairing..."
        Repair-VoltaNodeImage -Version $Version
        & volta install "node@$Version"
        if ($LASTEXITCODE -ne 0) {
            throw "volta reinstall node@$Version failed"
        }
        if (-not (Test-VoltaNpmHealthy)) {
            throw "npm still broken after reinstalling node@$Version. Try: volta install node@$Version"
        }
        Write-Host ("npm repaired: " + (& npm.cmd --version))
    }
}

if (-not (Test-Path $pkgJson)) {
    throw "UI project not found: $ui"
}

$nodeVersion = Get-PinnedNodeVersion -PackageJsonPath $pkgJson

Write-Host '[1/4] Volta / Node ...'
Ensure-VoltaNode -Version $nodeVersion

Push-Location $ui
try {
    # Pin in ui dir so npm/node use Volta-managed version
    & volta pin "node@$nodeVersion" | Out-Null
    Write-Host ("Node (volta): " + (& node -v))

    if (-not (Test-Path 'node_modules')) {
        Write-Host '[2/4] npm install ...'
        npm.cmd install
        if ($LASTEXITCODE -ne 0) { throw 'npm install failed' }
    }
    else {
        Write-Host '[2/4] npm install - skip (node_modules present)'
    }
}
finally {
    Pop-Location
}

$startedVite = $false
$viteOutLog = Join-Path $env:TEMP 'miao-vite-dev.out.log'
$viteErrLog = Join-Path $env:TEMP 'miao-vite-dev.err.log'

try {
    Write-Host '[3/4] Vite + host build ...'
    $viteReady = Test-ViteUp
    if (-not $viteReady) {
        Write-Host 'Starting Vite on 127.0.0.1:5173 ...'
        foreach ($f in @($viteOutLog, $viteErrLog)) {
            if (Test-Path -LiteralPath $f) {
                Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
            }
        }
        # Prefer node+vite.js (npm.cmd + redirect can drop the child on some hosts)
        $viteJs = [System.IO.Path]::Combine($ui, 'node_modules', 'vite', 'bin', 'vite.js')
        if ([string]::IsNullOrWhiteSpace($viteJs) -or -not (Test-Path -LiteralPath $viteJs)) {
            throw "Vite not found under $ui\node_modules\vite (run npm install in desktop/ui)"
        }
        $nodeCmd = (Get-Command node -ErrorAction Stop).Source
        # Use cmd redirection (Start-Process -Redirect* can block node stdio on some hosts)
        $cmdArgs = '/c ""{0}" "{1}" --host {2} --port {3} --strictPort >"{4}" 2>"{5}""' -f `
            $nodeCmd, $viteJs, $viteHost, $vitePort, $viteOutLog, $viteErrLog
        Start-Process -FilePath 'cmd.exe' `
            -ArgumentList $cmdArgs `
            -WorkingDirectory $ui `
            -WindowStyle Hidden `
            -PassThru | Out-Null
        $startedVite = $true
    }
    else {
        Write-Host 'Vite already running; reusing it.'
    }

    # Start Vite first (if needed), then build host while Vite warms up
    Write-Host 'dotnet build ...'
    & dotnet build $proj --nologo -v q
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet build failed (exit $LASTEXITCODE)"
    }
    Write-Host 'Host build ready.'

    if (-not $viteReady) {
        $deadline = (Get-Date).AddSeconds(60)
        $lastHint = (Get-Date)
        while (-not (Test-ViteUp)) {
            if ((Get-Date) -gt $deadline) {
                $chunks = @()
                foreach ($f in @($viteOutLog, $viteErrLog)) {
                    if (Test-Path -LiteralPath $f) {
                        $part = (Get-Content -LiteralPath $f -Tail 40 -ErrorAction SilentlyContinue) -join "`n"
                        if ($part) { $chunks += $part }
                    }
                }
                $tail = $chunks -join "`n"
                $msg = "Vite did not become ready within 60s.`nLogs: $viteOutLog / $viteErrLog`n"
                if ($tail) {
                    $msg += "---- vite log (tail) ----`n$tail`n-------------------------`n"
                }
                $msg += 'Manual: cd desktop/ui; npm run dev'
                throw $msg
            }
            if (((Get-Date) - $lastHint).TotalSeconds -ge 5) {
                Write-Host ("Waiting for Vite on {0}:{1} ..." -f $viteHost, $vitePort)
                $lastHint = Get-Date
            }
            Start-Sleep -Milliseconds 300
        }
        Write-Host 'Vite ready.'
    }

    $env:MIAO_UI_DEV = '1'
    Write-Host '[4/4] Starting Miao host (edit desktop/ui for HMR)...'
    Write-Host 'Close the app window or press Ctrl+C here to stop.'
    # Pre-built: --no-build starts the process faster
    dotnet run --project $proj --no-launch-profile --no-build
}
finally {
    if ($startedVite) {
        Write-Host 'Stopping Vite...'
        Stop-PortListeners -Port 5173
    }
}
