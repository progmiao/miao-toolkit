function Test-ToolHasExternalDeps {
    param($Tool)

    if ($Tool.requiresInstall -eq $false) { return $false }
    if (-not $Tool.dependencies) { return $false }
    return (@($Tool.dependencies).Count -gt 0)
}

function Test-ToolDeps {
    param($Tool)

    if ($Tool.requiresInstall -eq $false) { return $true }
    if (-not $Tool.dependencies) { return $true }

    foreach ($dep in @($Tool.dependencies)) {
        if (-not $dep.checkCommand) { continue }
        $parts = $dep.checkCommand -split '\s+', 2
        $exe = $parts[0]
        if (-not (Get-Command $exe -ErrorAction SilentlyContinue)) {
            return $false
        }
    }
    return $true
}

function Get-WingetPackageInstalledVersion {
    param([string]$PackageId)

    if ([string]::IsNullOrWhiteSpace($PackageId)) { return $null }
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { return $null }

    try {
        $output = & winget list --id $PackageId -e --disable-interactivity --accept-source-agreements --output json 2>&1 |
            Out-String
        if (-not $output) { return $null }

        $data = $output | ConvertFrom-Json
        if ($data.Sources) {
            foreach ($src in @($data.Sources)) {
                foreach ($pkg in @($src.Packages)) {
                    if ($pkg.Version) {
                        return [string]$pkg.Version
                    }
                }
            }
        }
    }
    catch {
        return $null
    }

    return $null
}

function Get-WingetPackageLatestVersion {
    param([string]$PackageId)

    if ([string]::IsNullOrWhiteSpace($PackageId)) { return $null }
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { return $null }

    try {
        $output = & winget show --id $PackageId -e --disable-interactivity --accept-source-agreements --output json 2>&1 |
            Out-String
        if (-not $output) { return $null }

        $data = $output | ConvertFrom-Json
        if ($data.Versions) {
            foreach ($ver in @($data.Versions)) {
                if ($ver.PackageVersion) {
                    return [string]$ver.PackageVersion
                }
            }
        }
        if ($data.Version) {
            return [string]$data.Version
        }
    }
    catch {
        return $null
    }

    return $null
}

function Test-WingetPackageUpdateAvailable {
    param(
        [string]$PackageId,
        [string]$InstalledVersion = ''
    )

    if ([string]::IsNullOrWhiteSpace($PackageId)) { return $false }
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { return $false }

    if (-not [string]::IsNullOrWhiteSpace($InstalledVersion)) {
        $latest = Get-WingetPackageLatestVersion -PackageId $PackageId
        if ($latest) {
            return (Test-VersionIsNewer -Candidate $latest -Baseline $InstalledVersion)
        }
    }

    try {
        $output = & winget upgrade --id $PackageId --disable-interactivity --accept-source-agreements 2>&1 |
            Out-String
        if ($output -match 'No applicable upgrade|No available upgrade|没有适用的升级|找不到可用的升级|没有可用的升级') {
            return $false
        }
        if ($LASTEXITCODE -eq -1978335189) { return $false }
        return ($LASTEXITCODE -eq 0)
    }
    catch {
        return $false
    }
}

function Get-ToolDependencyStatus {
    param($Tool)

    if (-not (Test-ToolHasExternalDeps $Tool)) {
        return 'installed'
    }

    if (Test-ToolDepInstalled $Tool) {
        return 'installed'
    }

    return 'notInstalled'
}

function Invoke-ToolInstall {
    param(
        $Tool,
        [switch]$Preview
    )

    if (-not (Test-ToolHasExternalDeps $Tool)) { return $true }

    $installScript = Join-Path $Tool._root $Tool.install
    if (-not (Test-Path $installScript)) {
        Write-Host (Get-I18n -Key 'error.missingInstallScript' -Vars @{ path = $Tool.install }) -ForegroundColor Red
        return $false
    }

    if ($Preview) {
        Write-Host "[预览] 将执行: $($Tool.id)/$($Tool.install)" -ForegroundColor Yellow
        return $true
    }

    $depName = if ($Tool.displayName) { [string]$Tool.displayName } else { [string]$Tool.id }
    Write-Host (Get-I18n -Key 'tool.deps.installing' -Vars @{ name = $depName }) -ForegroundColor Cyan
    & $installScript
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        return $false
    }

    $versions = Resolve-ToolDependencyVersionsAfterInstall -Tool $Tool
    if (-not $versions -or $versions.Count -eq 0) {
        return $false
    }

    Set-ToolDepInstalled -ToolId ([string]$Tool.id) -DependencyVersions $versions
    return $true
}

function Ensure-ToolDeps {
    param(
        $Tool,
        [switch]$Preview
    )

    if ($env:MIAO_SKIP_DEPS -eq '1') {
        Write-Host '[开发] 已跳过依赖检查 (MIAO_SKIP_DEPS=1)' -ForegroundColor DarkGray
        return $true
    }

    return (Test-ToolDepInstalled $Tool)
}
