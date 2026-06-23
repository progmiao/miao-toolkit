# pnpm - Volta / pnpm version helpers

$script:PnpmVoltaToolRoot = $null

function Set-PnpmVoltaToolRoot {
    param([string]$ToolRoot)

    $script:PnpmVoltaToolRoot = [string]$ToolRoot
}

function Get-PnpmVersionTagI18n {
    param(
        [string]$Key,
        [hashtable]$Vars = @{}
    )

    if ($script:PnpmVoltaToolRoot -and (Get-Command Get-ToolI18n -ErrorAction SilentlyContinue)) {
        $text = Get-ToolI18n -ToolRoot $script:PnpmVoltaToolRoot -Key "pnpm.tags.$Key" -Vars $Vars
        if (-not [string]::IsNullOrWhiteSpace($text)) { return $text }
    }

    return $Key
}

function Normalize-PnpmVersionLabel {
    param([string]$Version)

    $v = [string]$Version.Trim()
    if ($v -match '^v(.+)$') { return $Matches[1] }
    return $v
}

function Resolve-PnpmVersionFromVoltaListLine {
    param([string]$Line)

    $trimmed = [string]$Line.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) { return $null }

    if ($trimmed -match 'pnpm@([0-9]+(?:\.[0-9]+)*)') {
        $ver = Normalize-PnpmVersionLabel -Version $Matches[1]
        if (-not [string]::IsNullOrWhiteSpace($ver)) { return $ver }
    }
    return $null
}

function Ensure-VoltaPnpmFeatureEnabled {
    if ($env:VOLTA_FEATURE_PNPM -ne '1') {
        $env:VOLTA_FEATURE_PNPM = '1'
    }
}

function Invoke-VoltaListPnpmRaw {
    Ensure-VoltaPnpmFeatureEnabled
    $raw = (& volta list pnpm 2>&1 | Out-String)
    if ($raw -match 'Could not parse project manifest') {
        $prev = Get-Location
        try {
            Set-Location $env:USERPROFILE
            $raw = (& volta list pnpm 2>&1 | Out-String)
        }
        finally {
            Set-Location $prev
        }
    }
    return $raw
}

function Get-VoltaPnpmVersionInfo {
    if (-not (Get-Command volta -ErrorAction SilentlyContinue)) {
        return @{ Map = @{}; Default = $null }
    }

    $installed = @{}
    $defaultVer = $null
    $raw = Invoke-VoltaListPnpmRaw

    foreach ($line in ($raw -split "\r?\n")) {
        $trimmed = [string]$line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }

        $ver = Resolve-PnpmVersionFromVoltaListLine -Line $trimmed
        if ([string]::IsNullOrWhiteSpace($ver)) { continue }
        $installed[$ver] = $true
        if ($trimmed -match '\(default\)') { $defaultVer = $ver }
    }

    return @{ Map = $installed; Default = $defaultVer }
}

function Get-ActivePnpmVersion {
    param([int]$TimeoutMs = 0)

    if (-not (Get-Command pnpm -ErrorAction SilentlyContinue)) { return $null }

    try {
        if ($TimeoutMs -gt 0) {
            $pnpmCmd = (Get-Command pnpm -ErrorAction Stop).Source
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $pnpmCmd
            $psi.Arguments = '-v'
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true

            $proc = [System.Diagnostics.Process]::Start($psi)
            if (-not $proc.WaitForExit($TimeoutMs)) {
                try { $proc.Kill() } catch {}
                return $null
            }

            $v = $proc.StandardOutput.ReadToEnd().ToString().Trim()
            if ([string]::IsNullOrWhiteSpace($v)) {
                $v = $proc.StandardError.ReadToEnd().ToString().Trim()
            }
            if ($v) { return ($v -replace '^v', '') }
            return $null
        }

        $v = (& pnpm -v 2>$null).ToString().Trim()
        if ($v) { return ($v -replace '^v', '') }
    }
    catch {}
    return $null
}

function Get-RemotePnpmVersions {
    $seen = @{}
    $items = [System.Collections.Generic.List[object]]::new()

    try {
        $pkg = Invoke-RestMethod 'https://registry.npmjs.org/pnpm'
        foreach ($ver in @($pkg.versions.PSObject.Properties.Name)) {
            $norm = Normalize-PnpmVersionLabel -Version $ver
            if ([string]::IsNullOrWhiteSpace($norm)) { continue }
            if ($norm -match '[^0-9.]') { continue }
            if ($seen[$norm]) { continue }
            $seen[$norm] = $true
            $items.Add((New-PnpmVersionMenuItem -Version $norm)) | Out-Null
        }
    }
    catch {}

    return @(Sort-PnpmVersionItems -Items $items)
}

function Get-PnpmVersionStatusTags {
    param(
        $Item,
        [hashtable]$InstalledMap,
        [string]$DefaultVersion,
        [string]$ActiveVersion = '',
        [string]$PinnedVersion = '',
        [switch]$IncludeInstalledTag
    )

    if ($null -eq $InstalledMap) { $InstalledMap = @{} }

    $version = Normalize-PnpmVersionLabel -Version ([string]$Item.Version)
    $active = Normalize-PnpmVersionLabel -Version $ActiveVersion
    $default = Normalize-PnpmVersionLabel -Version $DefaultVersion
    $pinned = Normalize-PnpmVersionLabel -Version $PinnedVersion

    $tag = ''
    if ($IncludeInstalledTag -and $version -and $InstalledMap.ContainsKey($version)) {
        $tag += ' [' + (Get-PnpmVersionTagI18n -Key 'installed') + ']'
    }
    if ($version -and $pinned -and $version -eq $pinned) {
        $tag += ' [' + (Get-PnpmVersionTagI18n -Key 'pinned') + ']'
    }
    if ($version -and $default -and $version -eq $default) {
        $tag += ' [' + (Get-PnpmVersionTagI18n -Key 'default') + ']'
    }
    if ($version -and $active -and $version -eq $active) {
        $tag += ' [' + (Get-PnpmVersionTagI18n -Key 'current') + ']'
    }
    return $tag
}

function New-PnpmVersionMenuItem {
    param([string]$Version)

    return [PSCustomObject]@{
        Version = (Normalize-PnpmVersionLabel -Version $Version)
    }
}

function Sort-PnpmVersionItems {
    param([array]$Items)

    return @($Items | Sort-Object {
        try { [version]($_.Version.Split('-')[0]) }
        catch { [version]'0.0.0' }
    } -Descending)
}

function Test-PnpmVersionInstalled {
    param(
        [string]$Version,
        [hashtable]$InstalledMap
    )

    if ($null -eq $InstalledMap) { return $false }
    $ver = Normalize-PnpmVersionLabel -Version $Version
    if ([string]::IsNullOrWhiteSpace($ver)) { return $false }
    return $InstalledMap.ContainsKey($ver)
}

function Write-PnpmProjectPackageJsonFile {
    param(
        [string]$Path,
        [hashtable]$Manifest
    )

    $json = ($Manifest | ConvertTo-Json -Depth 5) + "`n"
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Path, $json, $utf8NoBom)
}

function Repair-PnpmProjectPackageJsonEncoding {
    param([string]$PackageJsonPath)

    if ([string]::IsNullOrWhiteSpace($PackageJsonPath) -or -not (Test-Path -LiteralPath $PackageJsonPath)) {
        return $false
    }

    try {
        $bytes = [System.IO.File]::ReadAllBytes($PackageJsonPath)
        if ($bytes.Length -lt 3) { return $false }
        $hasBom = ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
        if (-not $hasBom) { return $false }

        $json = Get-Content -LiteralPath $PackageJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $manifest = [ordered]@{
            name    = [string]$json.name
            version = if ($json.version) { [string]$json.version } else { '0.0.0' }
        }
        if ($null -ne $json.private) { $manifest['private'] = [bool]$json.private }
        if ($json.volta) { $manifest['volta'] = $json.volta }
        Write-PnpmProjectPackageJsonFile -Path $PackageJsonPath -Manifest $manifest
        return $true
    }
    catch {
        return $false
    }
}

function New-PnpmProjectPackageJson {
    param([string]$Directory)

    $dir = [System.IO.Path]::GetFullPath($Directory)
    $path = Join-Path $dir 'package.json'
    if (Test-Path -LiteralPath $path) {
        $null = Repair-PnpmProjectPackageJsonEncoding -PackageJsonPath $path
        return $path
    }

    $dirName = Split-Path $dir -Leaf
    $name = ($dirName -replace '[^a-zA-Z0-9._\-@/]', '-').ToLower()
    if ([string]::IsNullOrWhiteSpace($name)) { $name = 'pnpm-project' }
    if ($name -match '^[\d@]') { $name = "p-$name" }

    $manifest = [ordered]@{
        name    = $name
        version = '0.0.0'
        private = $true
    }
    Write-PnpmProjectPackageJsonFile -Path $path -Manifest $manifest
    return $path
}

function Test-PnpmProjectPackageJsonReadable {
    param([string]$PackageJsonPath)

    if ([string]::IsNullOrWhiteSpace($PackageJsonPath) -or -not (Test-Path -LiteralPath $PackageJsonPath)) {
        return $false
    }

    try {
        $null = Get-Content -LiteralPath $PackageJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
        return $true
    }
    catch {
        return $false
    }
}

function Get-PnpmProjectPinnedVersionFromPackageJson {
    param([string]$PackageJsonPath)

    if ([string]::IsNullOrWhiteSpace($PackageJsonPath) -or -not (Test-Path -LiteralPath $PackageJsonPath)) {
        return ''
    }

    try {
        $raw = [System.IO.File]::ReadAllText($PackageJsonPath)
        if ([string]::IsNullOrWhiteSpace($raw)) { return '' }
        $json = $raw | ConvertFrom-Json
        if ($json.volta -and $null -ne $json.volta.pnpm) {
            return (Normalize-PnpmVersionLabel -Version ([string]$json.volta.pnpm))
        }
    }
    catch { }

    return ''
}

function Resolve-PnpmProjectPackageJsonRelativePath {
    param(
        [string]$FromDirectory,
        [string]$PackageJsonPath
    )

    if ([string]::IsNullOrWhiteSpace($FromDirectory) -or [string]::IsNullOrWhiteSpace($PackageJsonPath)) {
        return 'package.json'
    }

    $from = [System.IO.Path]::GetFullPath($FromDirectory).TrimEnd('\', '/')
    $pkg = [System.IO.Path]::GetFullPath($PackageJsonPath)
    $pkgDir = [System.IO.Path]::GetDirectoryName($pkg)
    if ($pkgDir -eq $from) {
        return 'package.json'
    }

    try {
        $fromUri = New-Object System.Uri ($from + [System.IO.Path]::DirectorySeparatorChar)
        $pkgUri = New-Object System.Uri $pkg
        $rel = [Uri]::UnescapeDataString($fromUri.MakeRelativeUri($pkgUri).ToString())
        return ($rel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    }
    catch {
        return (Split-Path $pkg -Leaf)
    }
}

function Resolve-PnpmProjectPinContext {
    param([string]$WorkingDirectory = '')

    if ([string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        $WorkingDirectory = (Get-Location).Path
    }

    $startDir = [System.IO.Path]::GetFullPath($WorkingDirectory)
    $walkDir = $startDir
    $packageJsonPath = $null

    while ($true) {
        $candidate = Join-Path $walkDir 'package.json'
        if (Test-Path -LiteralPath $candidate) {
            $packageJsonPath = $candidate
            break
        }

        $parent = [System.IO.Path]::GetDirectoryName($walkDir)
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $walkDir) { break }
        $walkDir = $parent
    }

    if ($packageJsonPath) {
        $null = Repair-PnpmProjectPackageJsonEncoding -PackageJsonPath $packageJsonPath
        $projectDir = [System.IO.Path]::GetDirectoryName($packageJsonPath)
        $projectName = Split-Path $projectDir -Leaf
        try {
            $json = Get-Content -LiteralPath $packageJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($json.name) {
                $name = [string]$json.name
                if (-not [string]::IsNullOrWhiteSpace($name)) {
                    $projectName = $name
                }
            }
        }
        catch { }

        return @{
            HasProject       = $true
            PackageJsonPath  = $packageJsonPath
            ProjectDirectory = $projectDir
            WorkingDirectory = $startDir
            ProjectName      = $projectName
            PackageJsonRel   = (Resolve-PnpmProjectPackageJsonRelativePath -FromDirectory $startDir `
                -PackageJsonPath $packageJsonPath)
            PinnedVersion    = (Get-PnpmProjectPinnedVersionFromPackageJson -PackageJsonPath $packageJsonPath)
            CreateDirectory  = $null
            PackageJsonValid = $true
        }
    }

    return @{
        HasProject       = $false
        PackageJsonPath  = $null
        ProjectDirectory = $null
        WorkingDirectory = $startDir
        ProjectName      = (Split-Path $startDir -Leaf)
        PackageJsonRel   = ''
        PinnedVersion    = ''
        CreateDirectory  = $startDir
        PackageJsonValid = $true
    }
}

function Test-VoltaPnpmUninstallLineIgnorable {
    param([string]$Line)

    $trim = [string]$Line.Trim()
    if ([string]::IsNullOrWhiteSpace($trim)) { return $false }

    return ($trim -match '(?i)uninstalling pnpm is not supported') `
        -or ($trim -match '(?i)no package pnpm@.+ found to uninstall')
}

function Test-VoltaPnpmUninstallExitIgnorable {
    param(
        [int]$ExitCode,
        [array]$OutputLines
    )

    if ($ExitCode -eq 0) { return $false }

    foreach ($line in @($OutputLines)) {
        if (Test-VoltaPnpmUninstallLineIgnorable -Line $line) { return $true }
    }
    return $false
}

function Get-VoltaHomeDirectory {
    if (-not [string]::IsNullOrWhiteSpace($env:VOLTA_HOME)) {
        return [string]$env:VOLTA_HOME.TrimEnd('\', '/')
    }

    if ($IsWindows -or ($env:OS -match 'Windows')) {
        $localAppData = $env:LOCALAPPDATA
        if (-not [string]::IsNullOrWhiteSpace($localAppData)) {
            return (Join-Path $localAppData 'Volta')
        }
    }

    $home = $env:USERPROFILE
    if ([string]::IsNullOrWhiteSpace($home)) { $home = $env:HOME }
    if (-not [string]::IsNullOrWhiteSpace($home)) {
        return (Join-Path $home '.volta')
    }
    return $null
}

function Get-VoltaPnpmImageRoot {
    $voltaHome = Get-VoltaHomeDirectory
    if ([string]::IsNullOrWhiteSpace($voltaHome)) { return $null }
    return (Join-Path $voltaHome 'tools\image\pnpm')
}

function Get-VoltaPnpmVersionImagePaths {
    param([string]$Version)

    $root = Get-VoltaPnpmImageRoot
    if ([string]::IsNullOrWhiteSpace($root)) { return @() }

    $norm = Normalize-PnpmVersionLabel -Version $Version
    if ([string]::IsNullOrWhiteSpace($norm)) { return @() }

    $paths = [System.Collections.Generic.List[string]]::new()
    $seen = @{}

    foreach ($name in @(
            "v$norm"
            $norm
            "pnpm-v$norm"
        )) {
        $path = Join-Path $root $name
        if ($seen[$path]) { continue }
        $seen[$path] = $true
        if (Test-Path -LiteralPath $path) {
            $paths.Add($path) | Out-Null
        }
    }

    if (Test-Path -LiteralPath $root) {
        foreach ($entry in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
            if ($entry.Name -notmatch [regex]::Escape($norm)) { continue }
            if ($seen[$entry.FullName]) { continue }
            $seen[$entry.FullName] = $true
            $paths.Add($entry.FullName) | Out-Null
        }
    }

    return @($paths.ToArray())
}

function Remove-VoltaPnpmVersionImagePaths {
    param([string]$Version)

    $removed = 0
    foreach ($path in @(Get-VoltaPnpmVersionImagePaths -Version $Version)) {
        try {
            Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
            $removed++
        }
        catch {}
    }
    return $removed
}

function Test-PnpmVersionStillListed {
    param([string]$Version)

    $info = Get-VoltaPnpmVersionInfo
    $norm = Normalize-PnpmVersionLabel -Version $Version
    return ($info.Map.ContainsKey($norm))
}

function Ensure-StringArray {
    param($Value)

    if ($null -eq $Value) { return @() }
    return @($Value)
}
