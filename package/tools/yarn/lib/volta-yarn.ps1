# yarn - Volta / Yarn version helpers

$script:YarnVoltaToolRoot = $null

function Set-YarnVoltaToolRoot {
    param([string]$ToolRoot)

    $script:YarnVoltaToolRoot = [string]$ToolRoot
}

function Get-YarnVersionTagI18n {
    param(
        [string]$Key,
        [hashtable]$Vars = @{}
    )

    if ($script:YarnVoltaToolRoot -and (Get-Command Get-ToolI18n -ErrorAction SilentlyContinue)) {
        $text = Get-ToolI18n -ToolRoot $script:YarnVoltaToolRoot -Key "yarn.tags.$Key" -Vars $Vars
        if (-not [string]::IsNullOrWhiteSpace($text)) { return $text }
    }

    return $Key
}

function Normalize-YarnVersionLabel {
    param([string]$Version)

    $v = [string]$Version.Trim()
    if ($v -match '^v(.+)$') { return $Matches[1] }
    return $v
}

function Resolve-YarnVersionFromVoltaListLine {
    param([string]$Line)

    $trimmed = [string]$Line.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) { return $null }

    if ($trimmed -match 'yarn@([0-9]+(?:\.[0-9]+)*)') {
        $ver = Normalize-YarnVersionLabel -Version $Matches[1]
        if (-not [string]::IsNullOrWhiteSpace($ver)) { return $ver }
    }
    return $null
}

function Invoke-VoltaListYarnRaw {
    $raw = (& volta list yarn 2>&1 | Out-String)
    if ($raw -match 'Could not parse project manifest') {
        $prev = Get-Location
        try {
            Set-Location $env:USERPROFILE
            $raw = (& volta list yarn 2>&1 | Out-String)
        }
        finally {
            Set-Location $prev
        }
    }
    return $raw
}

function Get-VoltaYarnVersionInfo {
    if (-not (Get-Command volta -ErrorAction SilentlyContinue)) {
        return @{ Map = @{}; Default = $null }
    }

    $installed = @{}
    $defaultVer = $null
    $raw = Invoke-VoltaListYarnRaw

    foreach ($line in ($raw -split "\r?\n")) {
        $trimmed = [string]$line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }

        $ver = Resolve-YarnVersionFromVoltaListLine -Line $trimmed
        if ([string]::IsNullOrWhiteSpace($ver)) { continue }
        $installed[$ver] = $true
        if ($trimmed -match '\(default\)') { $defaultVer = $ver }
    }

    return @{ Map = $installed; Default = $defaultVer }
}

function Get-ActiveYarnVersion {
    param([int]$TimeoutMs = 0)

    if (-not (Get-Command yarn -ErrorAction SilentlyContinue)) { return $null }

    try {
        if ($TimeoutMs -gt 0) {
            $yarnCmd = (Get-Command yarn -ErrorAction Stop).Source
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $yarnCmd
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

        $v = (& yarn -v 2>$null).ToString().Trim()
        if ($v) { return ($v -replace '^v', '') }
    }
    catch {}
    return $null
}

function Get-RemoteYarnVersions {
    $seen = @{}
    $items = [System.Collections.Generic.List[object]]::new()

    foreach ($url in @(
            'https://registry.npmjs.org/yarn'
            'https://registry.npmjs.org/@yarnpkg%2fcli-dist'
        )) {
        try {
            $pkg = Invoke-RestMethod $url
            foreach ($ver in @($pkg.versions.PSObject.Properties.Name)) {
                $norm = Normalize-YarnVersionLabel -Version $ver
                if ([string]::IsNullOrWhiteSpace($norm)) { continue }
                if ($norm -match '[^0-9.]') { continue }
                if ($seen[$norm]) { continue }
                $seen[$norm] = $true
                $items.Add((New-YarnVersionMenuItem -Version $norm)) | Out-Null
            }
        }
        catch {}
    }

    return @(Sort-YarnVersionItems -Items $items)
}

function Get-YarnVersionStatusTags {
    param(
        $Item,
        [hashtable]$InstalledMap,
        [string]$DefaultVersion,
        [string]$ActiveVersion = '',
        [string]$PinnedVersion = '',
        [switch]$IncludeInstalledTag
    )

    if ($null -eq $InstalledMap) { $InstalledMap = @{} }

    $version = Normalize-YarnVersionLabel -Version ([string]$Item.Version)
    $active = Normalize-YarnVersionLabel -Version $ActiveVersion
    $default = Normalize-YarnVersionLabel -Version $DefaultVersion
    $pinned = Normalize-YarnVersionLabel -Version $PinnedVersion

    $tag = ''
    if ($IncludeInstalledTag -and $version -and $InstalledMap.ContainsKey($version)) {
        $tag += ' [' + (Get-YarnVersionTagI18n -Key 'installed') + ']'
    }
    if ($version -and $pinned -and $version -eq $pinned) {
        $tag += ' [' + (Get-YarnVersionTagI18n -Key 'pinned') + ']'
    }
    if ($version -and $default -and $version -eq $default) {
        $tag += ' [' + (Get-YarnVersionTagI18n -Key 'default') + ']'
    }
    if ($version -and $active -and $version -eq $active) {
        $tag += ' [' + (Get-YarnVersionTagI18n -Key 'current') + ']'
    }
    return $tag
}

function New-YarnVersionMenuItem {
    param([string]$Version)

    return [PSCustomObject]@{
        Version = (Normalize-YarnVersionLabel -Version $Version)
    }
}

function Sort-YarnVersionItems {
    param([array]$Items)

    return @($Items | Sort-Object {
        try { [version]($_.Version.Split('-')[0]) }
        catch { [version]'0.0.0' }
    } -Descending)
}

function Test-YarnVersionInstalled {
    param(
        [string]$Version,
        [hashtable]$InstalledMap
    )

    if ($null -eq $InstalledMap) { return $false }
    $ver = Normalize-YarnVersionLabel -Version $Version
    if ([string]::IsNullOrWhiteSpace($ver)) { return $false }
    return $InstalledMap.ContainsKey($ver)
}

function Write-YarnProjectPackageJsonFile {
    param(
        [string]$Path,
        [hashtable]$Manifest
    )

    $json = ($Manifest | ConvertTo-Json -Depth 5) + "`n"
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Path, $json, $utf8NoBom)
}

function Repair-YarnProjectPackageJsonEncoding {
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
        Write-YarnProjectPackageJsonFile -Path $PackageJsonPath -Manifest $manifest
        return $true
    }
    catch {
        return $false
    }
}

function New-YarnProjectPackageJson {
    param([string]$Directory)

    $dir = [System.IO.Path]::GetFullPath($Directory)
    $path = Join-Path $dir 'package.json'
    if (Test-Path -LiteralPath $path) {
        $null = Repair-YarnProjectPackageJsonEncoding -PackageJsonPath $path
        return $path
    }

    $dirName = Split-Path $dir -Leaf
    $name = ($dirName -replace '[^a-zA-Z0-9._\-@/]', '-').ToLower()
    if ([string]::IsNullOrWhiteSpace($name)) { $name = 'yarn-project' }
    if ($name -match '^[\d@]') { $name = "p-$name" }

    $manifest = [ordered]@{
        name    = $name
        version = '0.0.0'
        private = $true
    }
    Write-YarnProjectPackageJsonFile -Path $path -Manifest $manifest
    return $path
}

function Test-YarnProjectPackageJsonReadable {
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

function Get-YarnProjectPinnedVersionFromPackageJson {
    param([string]$PackageJsonPath)

    if ([string]::IsNullOrWhiteSpace($PackageJsonPath) -or -not (Test-Path -LiteralPath $PackageJsonPath)) {
        return ''
    }

    try {
        $raw = [System.IO.File]::ReadAllText($PackageJsonPath)
        if ([string]::IsNullOrWhiteSpace($raw)) { return '' }
        $json = $raw | ConvertFrom-Json
        if ($json.volta -and $null -ne $json.volta.yarn) {
            return (Normalize-YarnVersionLabel -Version ([string]$json.volta.yarn))
        }
    }
    catch { }

    return ''
}

function Resolve-YarnProjectPackageJsonRelativePath {
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

function Resolve-YarnProjectPinContext {
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
        $null = Repair-YarnProjectPackageJsonEncoding -PackageJsonPath $packageJsonPath
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
            PackageJsonRel   = (Resolve-YarnProjectPackageJsonRelativePath -FromDirectory $startDir `
                -PackageJsonPath $packageJsonPath)
            PinnedVersion    = (Get-YarnProjectPinnedVersionFromPackageJson -PackageJsonPath $packageJsonPath)
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

function Test-VoltaYarnUninstallLineIgnorable {
    param([string]$Line)

    $trim = [string]$Line.Trim()
    if ([string]::IsNullOrWhiteSpace($trim)) { return $false }

    return ($trim -match '(?i)uninstalling yarn is not supported') `
        -or ($trim -match '(?i)no package yarn@.+ found to uninstall')
}

function Test-VoltaYarnUninstallExitIgnorable {
    param(
        [int]$ExitCode,
        [array]$OutputLines
    )

    if ($ExitCode -eq 0) { return $false }

    foreach ($line in @($OutputLines)) {
        if (Test-VoltaYarnUninstallLineIgnorable -Line $line) { return $true }
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

function Get-VoltaYarnImageRoot {
    $voltaHome = Get-VoltaHomeDirectory
    if ([string]::IsNullOrWhiteSpace($voltaHome)) { return $null }
    return (Join-Path $voltaHome 'tools\image\yarn')
}

function Get-VoltaYarnVersionImagePaths {
    param([string]$Version)

    $root = Get-VoltaYarnImageRoot
    if ([string]::IsNullOrWhiteSpace($root)) { return @() }

    $norm = Normalize-YarnVersionLabel -Version $Version
    if ([string]::IsNullOrWhiteSpace($norm)) { return @() }

    $paths = [System.Collections.Generic.List[string]]::new()
    $seen = @{}

    foreach ($name in @(
            "v$norm"
            $norm
            "yarn-v$norm"
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

function Remove-VoltaYarnVersionImagePaths {
    param([string]$Version)

    $removed = 0
    foreach ($path in @(Get-VoltaYarnVersionImagePaths -Version $Version)) {
        try {
            Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
            $removed++
        }
        catch {}
    }
    return $removed
}

function Test-YarnVersionStillListed {
    param([string]$Version)

    $info = Get-VoltaYarnVersionInfo
    $norm = Normalize-YarnVersionLabel -Version $Version
    return ($info.Map.ContainsKey($norm))
}

function Ensure-StringArray {
    param($Value)

    if ($null -eq $Value) { return @() }
    return @($Value)
}
