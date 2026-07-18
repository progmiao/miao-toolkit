# 工具箱运行时依赖（winget 等），非工具 packages 配置

$script:ToolkitWingetRuntimeEnsured = $false

function Get-ToolkitRuntimesConfigPath {
    return Join-Path (Get-CorePackageRoot) 'runtimes.json'
}

function Get-ToolkitRuntimeDefinitions {
    $path = Get-ToolkitRuntimesConfigPath
    if (-not (Test-Path -LiteralPath $path)) { return @() }

    try {
        $raw = Get-Content -Raw -LiteralPath $path -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        Write-Warning (Get-I18n -Key 'message.runtimeConfigInvalid')
        return @()
    }

    if (-not $raw.runtimes) { return @() }
    return @($raw.runtimes)
}

function Get-ToolkitRuntimeDefinition {
    param([string]$RuntimeId)

    return @(Get-ToolkitRuntimeDefinitions) | Where-Object { [string]$_.id -eq $RuntimeId } | Select-Object -First 1
}

function Test-ToolkitPlanNeedsWingetBackend {
    param($Plan)

    foreach ($item in @($Plan.Items)) {
        if ($item._kind -eq 'runtime') { continue }
        if (-not $item.ShouldExecute) { continue }
        $pkg = $item.Status.Package
        if ($pkg -and $pkg.install -and [string]$pkg.install.type -eq 'winget') {
            return $true
        }
    }
    return $false
}

function New-ToolkitRuntimePlanStatus {
    param(
        $Runtime,
        [ValidateSet('Install', 'Skip')]
        [string]$Action = 'Install'
    )

    $name = if ($Runtime.nameKey) { Get-I18n -Key ([string]$Runtime.nameKey) } else { [string]$Runtime.id }
    $checkCommand = if ($Runtime.checkCommand) { [string]$Runtime.checkCommand } else { '' }
    $commandAvailable = Test-ToolDepCommandAvailable -CheckCommand $checkCommand

    $resolvedAction = if ($commandAvailable) { 'Skip' } else { $Action }
    if ($script:ToolkitWingetRuntimeEnsured -and [string]$Runtime.id -eq 'winget') {
        $resolvedAction = 'Skip'
    }

    return [pscustomobject]@{
        DependencyId     = "runtime:$([string]$Runtime.id)"
        Name             = $name
        PackageId        = ''
        Action           = $resolvedAction
        RecordedVersion  = $null
        ActualVersion    = if ($commandAvailable) { Resolve-ToolDepCheckCommandVersion -CheckCommand $checkCommand } else { $null }
        EffectiveVersion = $null
        VersionDrift     = $false
        Policy           = 'latest'
        CheckCommand     = $checkCommand
        CommandAvailable = $commandAvailable
        Package          = $Runtime
    }
}

function New-ToolkitRuntimePlanItem {
    param(
        $Runtime,
        [string]$Intent = 'install'
    )

    $status = New-ToolkitRuntimePlanStatus -Runtime $Runtime
    $shouldExecute = ($status.Action -eq 'Install')

    return [pscustomobject]@{
        Status        = $status
        Intent        = $Intent
        ShouldExecute = $shouldExecute
        ExecuteAction = if ($shouldExecute) { 'Install' } else { $null }
        _kind         = 'runtime'
        _runtimeId    = [string]$Runtime.id
    }
}

function Wait-ToolkitWingetCliReady {
    param(
        [int]$TimeoutSec = 90,
        [scriptblock]$OnPulse = $null
    )

    $deadline = [Environment]::TickCount + ($TimeoutSec * 1000)
    while ([Environment]::TickCount -lt $deadline) {
        if ($OnPulse) { & $OnPulse }
        Update-ToolDepSessionPath
        if (Test-WingetCliAvailable) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

function Invoke-ToolkitRuntimeMsixInstall {
    param(
        [string]$Uri,
        [scriptblock]$OnOutputLine = $null,
        [scriptblock]$OnPulse = $null
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $tempRoot = Join-Path $env:TEMP ('MiaoRuntime_' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

    try {
        $bundlePath = Join-Path $tempRoot 'AppInstaller.msixbundle'
        if ($OnOutputLine) { & $OnOutputLine (Get-I18n -Key 'page.runtime.logDownloading') }
        Invoke-WebRequest -Uri $Uri -OutFile $bundlePath -UseBasicParsing

        if ($OnOutputLine) { & $OnOutputLine (Get-I18n -Key 'page.runtime.logInstalling') }
        Add-AppxPackage -Path $bundlePath -ForceUpdateFromAnyVersion -ErrorAction Stop | Out-Null
        Update-ToolDepSessionPath

        if (-not (Wait-ToolkitWingetCliReady -OnPulse $OnPulse)) {
            [void]$lines.Add('winget not available after msix install')
            return @{
                Success   = $false
                Cancelled = $false
                ExitCode  = 1
                Lines     = @($lines)
                Command   = "Add-AppxPackage $bundlePath"
            }
        }

        $script:ToolkitWingetRuntimeEnsured = $true
        return @{
            Success   = $true
            Cancelled = $false
            ExitCode  = 0
            Lines     = @($lines)
            Command   = "Add-AppxPackage $bundlePath"
        }
    }
    catch {
        [void]$lines.Add([string]$_.Exception.Message)
        return @{
            Success   = $false
            Cancelled = $false
            ExitCode  = 1
            Lines     = @($lines)
            Command   = "Add-AppxPackage"
        }
    }
    finally {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-ToolkitRuntimeStoreFallback {
    param([string]$ProductId)

    if ([string]::IsNullOrWhiteSpace($ProductId)) { return $false }
    try {
        Start-Process "ms-windows-store://pdp/?ProductId=$ProductId" | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

function Invoke-ToolkitRuntimeExecute {
    param(
        $Runtime,
        [ValidateSet('Install')]
        [string]$ExecuteAction = 'Install',
        [scriptblock]$OnOutputLine = $null,
        [scriptblock]$OnPulse = $null
    )

    if (-not $Runtime -or -not $Runtime.install) {
        return @{
            Success   = $false
            Cancelled = $false
            ExitCode  = 1
            Lines     = @('missing runtime install config')
            Command   = ''
        }
    }

    $install = $Runtime.install
    $type = [string]$install.type

    if ($type -eq 'msix' -and $install.uri) {
        $result = Invoke-ToolkitRuntimeMsixInstall -Uri ([string]$install.uri) `
            -OnOutputLine $OnOutputLine -OnPulse $OnPulse
        if ($result.Success) { return $result }

        if ($Runtime.fallback -and [string]$Runtime.fallback.type -eq 'store') {
            if ($OnOutputLine) {
                & $OnOutputLine (Get-I18n -Key 'page.runtime.logStoreFallback')
            }
            $null = Invoke-ToolkitRuntimeStoreFallback -ProductId ([string]$Runtime.fallback.productId)
        }
        return $result
    }

    return @{
        Success   = $false
        Cancelled = $false
        ExitCode  = 1
        Lines     = @("unsupported runtime install type: $type")
        Command   = ''
    }
}

function Reset-ToolkitRuntimeSessionState {
    $script:ToolkitWingetRuntimeEnsured = $false
}
