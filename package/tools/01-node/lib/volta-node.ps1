# node - Volta / Node version helpers

$script:NodeVoltaToolRoot = $null

function Set-NodeVoltaToolRoot {
    param([string]$ToolRoot)

    $script:NodeVoltaToolRoot = [string]$ToolRoot
}

function Get-NodeVersionTagI18n {
    param(
        [string]$Key,
        [hashtable]$Vars = @{}
    )

    if ($script:NodeVoltaToolRoot -and (Get-Command Get-ToolI18n -ErrorAction SilentlyContinue)) {
        $text = Get-ToolI18n -ToolRoot $script:NodeVoltaToolRoot -Key "node.tags.$Key" -Vars $Vars
        if (-not [string]::IsNullOrWhiteSpace($text)) { return $text }
    }

    switch ($Key) {
        'installed' { return '已安装' }
        'default' { return '默认' }
        'current' { return '当前' }
        'pinned' { return '已指定' }
        'lts' { return "LTS:$($Vars.label)" }
        default { return $Key }
    }
}

function Assert-VoltaAvailable {
    if (Get-Command volta -ErrorAction SilentlyContinue) { return }

    Write-MessageBlock -Title '未找到 Volta' -Lines @(
        '请先安装 Volta (工具内 [安装] 或 winget install Volta.Volta).'
    ) -TitleColor Red
    exit 1
}

function Normalize-NodeVersionLabel {
    param([string]$Version)

    $v = [string]$Version.Trim()
    if ($v -match '^v(.+)$') { return $Matches[1] }
    return $v
}

function Resolve-NodeVersionFromVoltaListLine {
    param([string]$Line)

    $trimmed = [string]$Line.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) { return $null }

    $nodeAtPattern = 'node@([0-9]+(?:\.[0-9]+)*)'
    $voltaVPrefixPattern = 'v([0-9]+(?:\.[0-9]+)*)'

    if ($trimmed -match $nodeAtPattern) {
        $ver = Normalize-NodeVersionLabel -Version $Matches[1]
        if (-not [string]::IsNullOrWhiteSpace($ver)) { return $ver }
    }
    if ($trimmed -match $voltaVPrefixPattern) {
        $ver = Normalize-NodeVersionLabel -Version $Matches[1]
        if (-not [string]::IsNullOrWhiteSpace($ver)) { return $ver }
    }
    return $null
}

function Invoke-VoltaListNodeRaw {
    $raw = (& volta list node 2>&1 | Out-String)
    if ($raw -match 'Could not parse project manifest') {
        $prev = Get-Location
        try {
            Set-Location $env:USERPROFILE
            $raw = (& volta list node 2>&1 | Out-String)
        }
        finally {
            Set-Location $prev
        }
    }
    return $raw
}

function Get-VoltaNodeVersionInfo {
    if (-not (Get-Command volta -ErrorAction SilentlyContinue)) {
        return @{ Map = @{}; Default = $null }
    }

    $installed = @{}
    $defaultVer = $null
    $raw = Invoke-VoltaListNodeRaw

    foreach ($line in ($raw -split "\r?\n")) {
        $trimmed = [string]$line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }

        $ver = Resolve-NodeVersionFromVoltaListLine -Line $trimmed
        if ([string]::IsNullOrWhiteSpace($ver)) { continue }
        $installed[$ver] = $true
        if ($trimmed -match '\(default\)') { $defaultVer = $ver }
    }

    return @{ Map = $installed; Default = $defaultVer }
}

function Get-ActiveNodeVersion {
    param([int]$TimeoutMs = 0)

    if (-not (Get-Command node -ErrorAction SilentlyContinue)) { return $null }

    try {
        if ($TimeoutMs -gt 0) {
            $nodeCmd = (Get-Command node -ErrorAction Stop).Source
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $nodeCmd
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

        $v = (& node -v 2>$null).ToString().Trim()
        if ($v) { return ($v -replace '^v', '') }
    }
    catch {}
    return $null
}

function Get-RemoteNodeVersions {
    param([switch]$LtsOnly)

    $releases = Invoke-RestMethod 'https://nodejs.org/dist/index.json'
    if ($LtsOnly) {
        $releases = $releases | Where-Object { $_.lts -ne $false }
    }

    return @($releases | ForEach-Object {
        [PSCustomObject]@{
            Version = ($_.version -replace '^v', '')
            Lts     = $_.lts
            Date    = $_.date
        }
    })
}

function Get-NodeVersionStatusTags {
    param(
        $Item,
        [hashtable]$InstalledMap,
        [string]$DefaultVersion,
        [string]$ActiveVersion = '',
        [string]$PinnedVersion = '',
        [switch]$IncludeInstalledTag
    )

    if ($null -eq $InstalledMap) { $InstalledMap = @{} }

    $version = Normalize-NodeVersionLabel -Version ([string]$Item.Version)
    $active = Normalize-NodeVersionLabel -Version $ActiveVersion
    $default = Normalize-NodeVersionLabel -Version $DefaultVersion
    $pinned = Normalize-NodeVersionLabel -Version $PinnedVersion

    $tag = ''
    if ($IncludeInstalledTag -and $version -and $InstalledMap.ContainsKey($version)) {
        $tag += ' [' + (Get-NodeVersionTagI18n -Key 'installed') + ']'
    }
    if ($version -and $pinned -and $version -eq $pinned) {
        $tag += ' [' + (Get-NodeVersionTagI18n -Key 'pinned') + ']'
    }
    if ($version -and $default -and $version -eq $default) {
        $tag += ' [' + (Get-NodeVersionTagI18n -Key 'default') + ']'
    }
    if ($version -and $active -and $version -eq $active) {
        $tag += ' [' + (Get-NodeVersionTagI18n -Key 'current') + ']'
    }
    if ($Item.Lts -and $Item.Lts -ne $false) {
        $tag += ' [' + (Get-NodeVersionTagI18n -Key 'lts' -Vars @{ label = [string]$Item.Lts }) + ']'
    }
    return $tag
}

function Format-NodeVersionMenuLabel {
    param(
        $Item,
        [hashtable]$InstalledMap,
        [string]$DefaultVersion,
        [string]$ActiveVersion = ''
    )

    $tag = Get-NodeVersionStatusTags -Item $Item -InstalledMap $InstalledMap `
        -DefaultVersion $DefaultVersion -ActiveVersion $ActiveVersion -IncludeInstalledTag
    return "$($Item.Version)$tag"
}

function New-NodeVersionMenuItem {
    param(
        [string]$Version,
        $Lts = $false,
        [string]$Date = ''
    )

    return [PSCustomObject]@{
        Version = $Version
        Lts     = $Lts
        Date    = $Date
    }
}

function Sort-NodeVersionItems {
    param([array]$Items)

    return @($Items | Sort-Object { [version]($_.Version.Split('-')[0]) } -Descending)
}

function Get-NodeProjectPinnedVersionFromPackageJson {
    param([string]$PackageJsonPath)

    if ([string]::IsNullOrWhiteSpace($PackageJsonPath) -or -not (Test-Path -LiteralPath $PackageJsonPath)) {
        return ''
    }

    try {
        $raw = [System.IO.File]::ReadAllText($PackageJsonPath)
        if ([string]::IsNullOrWhiteSpace($raw)) { return '' }
        $json = $raw | ConvertFrom-Json
        if ($json.volta -and $null -ne $json.volta.node) {
            return (Normalize-NodeVersionLabel -Version ([string]$json.volta.node))
        }
    }
    catch { }

    return ''
}

function Resolve-NodeProjectPackageJsonRelativePath {
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

function Resolve-NodeProjectPinContext {
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
        $null = Repair-NodeProjectPackageJsonEncoding -PackageJsonPath $packageJsonPath
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
            PackageJsonRel   = (Resolve-NodeProjectPackageJsonRelativePath -FromDirectory $startDir `
                -PackageJsonPath $packageJsonPath)
            PinnedVersion    = (Get-NodeProjectPinnedVersionFromPackageJson -PackageJsonPath $packageJsonPath)
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

function Write-NodeProjectPackageJsonFile {
    param(
        [string]$Path,
        [hashtable]$Manifest
    )

    $json = ($Manifest | ConvertTo-Json -Depth 3) + "`n"
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Path, $json, $utf8NoBom)
}

function Repair-NodeProjectPackageJsonEncoding {
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
        Write-NodeProjectPackageJsonFile -Path $PackageJsonPath -Manifest $manifest
        return $true
    }
    catch {
        return $false
    }
}

function New-NodeProjectPackageJson {
    param([string]$Directory)

    $dir = [System.IO.Path]::GetFullPath($Directory)
    $path = Join-Path $dir 'package.json'
    if (Test-Path -LiteralPath $path) {
        $null = Repair-NodeProjectPackageJsonEncoding -PackageJsonPath $path
        return $path
    }

    $dirName = Split-Path $dir -Leaf
    $name = ($dirName -replace '[^a-zA-Z0-9._\-@/]', '-').ToLower()
    if ([string]::IsNullOrWhiteSpace($name)) { $name = 'node-project' }
    if ($name -match '^[\d@]') { $name = "p-$name" }

    $manifest = [ordered]@{
        name    = $name
        version = '0.0.0'
        private = $true
    }
    Write-NodeProjectPackageJsonFile -Path $path -Manifest $manifest
    return $path
}

function Test-NodeProjectPackageJsonReadable {
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

function Test-NodeVersionInstalled {
    param(
        [string]$Version,
        [hashtable]$InstalledMap
    )

    if ($null -eq $InstalledMap) { return $false }
    $ver = Normalize-NodeVersionLabel -Version $Version
    if ([string]::IsNullOrWhiteSpace($ver)) { return $false }
    return $InstalledMap.ContainsKey($ver)
}

function Test-VoltaNodeUninstallLineIgnorable {
    param([string]$Line)

    $trim = [string]$Line.Trim()
    if ([string]::IsNullOrWhiteSpace($trim)) { return $false }

    return ($trim -match '(?i)uninstalling node is not supported') `
        -or ($trim -match '(?i)no package node@.+ found to uninstall')
}

function Get-VoltaNodeCliUninstallSupported {
    if ($null -ne $script:VoltaNodeCliUninstallSupported) {
        return [bool]$script:VoltaNodeCliUninstallSupported
    }

    $script:VoltaNodeCliUninstallSupported = $true
    return $true
}

function Set-VoltaNodeCliUninstallUnsupported {
    $script:VoltaNodeCliUninstallSupported = $false
}

function Test-VoltaNodeUninstallExitIgnorable {
    param(
        [int]$ExitCode,
        [array]$OutputLines
    )

    if ($ExitCode -eq 0) { return $false }

    foreach ($line in @($OutputLines)) {
        if (Test-VoltaNodeUninstallLineIgnorable -Line $line) { return $true }
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

function Get-VoltaNodeImageRoot {
    $voltaHome = Get-VoltaHomeDirectory
    if ([string]::IsNullOrWhiteSpace($voltaHome)) { return $null }
    return (Join-Path $voltaHome 'tools\image\node')
}

function Get-VoltaNodeVersionImagePaths {
    param([string]$Version)

    $root = Get-VoltaNodeImageRoot
    if ([string]::IsNullOrWhiteSpace($root)) { return @() }

    $norm = Normalize-NodeVersionLabel -Version $Version
    if ([string]::IsNullOrWhiteSpace($norm)) { return @() }

    $paths = [System.Collections.Generic.List[string]]::new()
    $seen = @{}

    foreach ($name in @(
            "v$norm"
            $norm
            "node-v$norm"
            "node-v$norm-win-x64"
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
            if (-not (Test-VoltaNodeVersionImageDirName -DirName $entry.Name -Version $norm)) { continue }
            if ($seen[$entry.FullName]) { continue }
            $seen[$entry.FullName] = $true
            $paths.Add($entry.FullName) | Out-Null
        }
    }

    return @($paths.ToArray())
}

function Test-VoltaNodeVersionInventoryArtifactName {
    param(
        [string]$Name,
        [string]$Version
    )

    $norm = Normalize-NodeVersionLabel -Version $Version
    if ([string]::IsNullOrWhiteSpace($norm) -or [string]::IsNullOrWhiteSpace($Name)) {
        return $false
    }

    if ($Name -eq "node-v$norm-npm") { return $true }
    if ($Name -like "node-v$norm-*") { return $true }
    return $false
}

function Get-VoltaNodeVersionInventoryPaths {
    param([string]$Version)

    $dir = Get-VoltaNodeInventoryDirectory
    if ([string]::IsNullOrWhiteSpace($dir) -or -not (Test-Path -LiteralPath $dir)) {
        return @()
    }

    $norm = Normalize-NodeVersionLabel -Version $Version
    if ([string]::IsNullOrWhiteSpace($norm)) { return @() }

    $paths = [System.Collections.Generic.List[string]]::new()
    $seen = @{}

    foreach ($entry in @(Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue)) {
        if (-not (Test-VoltaNodeVersionInventoryArtifactName -Name $entry.Name -Version $norm)) { continue }
        if ($seen[$entry.FullName]) { continue }
        $seen[$entry.FullName] = $true
        $paths.Add($entry.FullName) | Out-Null
    }

    return @($paths.ToArray())
}

function Get-VoltaNodeVersionTmpArtifactPaths {
    param([string]$Version)

    $tmp = Join-Path $env:LOCALAPPDATA 'Volta\tmp'
    if (-not (Test-Path -LiteralPath $tmp)) { return @() }

    $norm = Normalize-NodeVersionLabel -Version $Version
    if ([string]::IsNullOrWhiteSpace($norm)) { return @() }

    $paths = @()
    foreach ($dir in @(Get-ChildItem -LiteralPath $tmp -Directory -ErrorAction SilentlyContinue)) {
        if (-not (Test-VoltaNodeVersionImageDirName -DirName $dir.Name -Version $norm)) { continue }
        $paths += $dir.FullName
    }
    return $paths
}

function Test-VoltaNodeVersionLocalArtifactsAbsent {
    param([string]$Version)

    if ((Get-VoltaNodeVersionImagePaths -Version $Version).Count -gt 0) { return $false }
    if ((Get-VoltaNodeVersionInventoryPaths -Version $Version).Count -gt 0) { return $false }
    if ((Get-VoltaNodeVersionTmpArtifactPaths -Version $Version).Count -gt 0) { return $false }
    return $true
}

function Remove-VoltaNodeArtifactPath {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $true }

    $item = Get-Item -LiteralPath $Path -Force
    if ($item.PSIsContainer) {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
    }
    else {
        Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
    }
    return $true
}

function Test-VoltaNodeVersionImageDirName {
    param(
        [string]$DirName,
        [string]$Version
    )

    $norm = Normalize-NodeVersionLabel -Version $Version
    if ([string]::IsNullOrWhiteSpace($norm) -or [string]::IsNullOrWhiteSpace($DirName)) {
        return $false
    }

    return @(
        $DirName -eq $norm
        $DirName -eq "v$norm"
        $DirName -eq "node-v$norm"
        $DirName -eq "node-v$norm-win-x64"
    ) -contains $true
}

function Resolve-NodeBrowseUninstallSelectionVersions {
    param([array]$Items)

    $selected = [System.Collections.Generic.List[string]]::new()
    $seen = @{}

    foreach ($item in @($Items)) {
        if ($null -eq $item) { continue }

        $ver = ''
        if ($null -ne $item.PSObject.Properties['Version'] -and $item.Version) {
            $ver = Normalize-NodeVersionLabel -Version ([string]$item.Version)
        }
        elseif ($null -ne $item.Source -and $item.Source.Version) {
            $ver = Normalize-NodeVersionLabel -Version ([string]$item.Source.Version)
        }
        elseif ($null -ne $item.PSObject.Properties['SearchKey'] -and $item.SearchKey) {
            $ver = Normalize-NodeVersionLabel -Version ([string]$item.SearchKey)
        }

        if ([string]::IsNullOrWhiteSpace($ver)) { continue }
        if ($seen[$ver]) { continue }
        $seen[$ver] = $true
        $selected.Add($ver) | Out-Null
    }

    return ,@((Ensure-StringArray -Value @($selected.ToArray())))
}

function Ensure-StringArray {
    param([object]$Value)

    if ($null -eq $Value) { return ,@() }
    if ($Value -is [string]) {
        if ([string]::IsNullOrWhiteSpace($Value)) { return ,@() }
        return ,@([string]$Value)
    }
    if ($Value -is [System.Array]) {
        $items = @($Value | ForEach-Object {
            if ($null -eq $_) { return }
            [string]$_
        } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        return ,@($items)
    }
    if ([string]::IsNullOrWhiteSpace([string]$Value)) { return ,@() }
    return ,@([string]$Value)
}

function Get-NodeBrowseUninstallPlanVersions {
    param(
        [array]$Items,
        [hashtable]$InstalledMap
    )

    if ($null -eq $InstalledMap) { $InstalledMap = @{} }

    $selected = Resolve-NodeBrowseUninstallSelectionVersions -Items $Items
    $planned = [System.Collections.Generic.List[string]]::new()
    $seen = @{}

    foreach ($ver in @((Ensure-StringArray -Value $selected))) {
        $norm = Normalize-NodeVersionLabel -Version $ver
        if ([string]::IsNullOrWhiteSpace($norm)) { continue }
        if (-not $InstalledMap.ContainsKey($norm)) { continue }
        if ($seen[$norm]) { continue }
        $seen[$norm] = $true
        [void]$planned.Add($norm)
    }

    return ,@($planned.ToArray())
}

function Order-NodeVersionsForUninstall {
    param(
        [array]$VersionsToUninstall,
        [string]$DefaultVersion
    )

    $defaultNorm = Normalize-NodeVersionLabel -Version $DefaultVersion
    $inputVersions = @((Ensure-StringArray -Value @($VersionsToUninstall)))
    if ($inputVersions.Count -le 0) { return ,@() }

    $sorted = @($inputVersions | Sort-Object @{
            Expression = {
                $v = Normalize-NodeVersionLabel -Version $_
                if ($defaultNorm -and $v -eq $defaultNorm) { 1 } else { 0 }
            }
        }, @{
            Expression = { [version]($_.Split('-')[0]) }
            Descending = $true
        })
    return ,@((Ensure-StringArray -Value $sorted))
}

function Get-NodeDefaultReplacementVersion {
    param(
        [hashtable]$InstalledMap,
        [string]$ExcludeVersion
    )

    if ($null -eq $InstalledMap) { return $null }

    $exclude = Normalize-NodeVersionLabel -Version $ExcludeVersion
    $candidates = @($InstalledMap.Keys | Where-Object {
        $v = Normalize-NodeVersionLabel -Version $_
        $v -and $v -ne $exclude
    })
    if ($candidates.Count -eq 0) { return $null }

    return @($candidates | Sort-Object { [version]($_.Split('-')[0]) } -Descending | Select-Object -First 1)
}

function Remove-VoltaNodeVersionImageDirs {
    param([string]$Version)

    $root = Get-VoltaNodeImageRoot
    $result = @{
        Root    = $root
        Paths   = @()
        Removed = @()
        Failed  = @()
    }

    if ([string]::IsNullOrWhiteSpace($root)) {
        return $result
    }

    $paths = Get-VoltaNodeVersionImagePaths -Version $Version
    $result.Paths = @($paths)

    foreach ($path in $paths) {
        try {
            Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
            $result.Removed += $path
        }
        catch {
            $result.Failed += [pscustomobject]@{
                Path  = $path
                Error = $_.Exception.Message
            }
        }
    }
    return $result
}

function Get-VoltaNodeInventoryDirectory {
    $voltaHome = Get-VoltaHomeDirectory
    if ([string]::IsNullOrWhiteSpace($voltaHome)) { return $null }
    return (Join-Path $voltaHome 'tools\inventory\node')
}

function Remove-VoltaNodeVersionInventoryFiles {
    param([string]$Version)

    $result = @{
        Paths   = @()
        Removed = @()
        Failed  = @()
    }

    $paths = Get-VoltaNodeVersionInventoryPaths -Version $Version
    $result.Paths = @($paths)

    foreach ($path in @($paths)) {
        try {
            $null = Remove-VoltaNodeArtifactPath -Path $path
            $result.Removed += $path
        }
        catch {
            $result.Failed += [pscustomobject]@{
                Path  = $path
                Error = $_.Exception.Message
            }
        }
    }

    return $result
}

function Remove-VoltaNodeVersionTmpArtifacts {
    param([string]$Version)

    $result = @{
        Paths   = @()
        Removed = @()
        Failed  = @()
    }

    $paths = Get-VoltaNodeVersionTmpArtifactPaths -Version $Version
    $result.Paths = @($paths)

    foreach ($path in @($paths)) {
        try {
            $null = Remove-VoltaNodeArtifactPath -Path $path
            $result.Removed += $path
        }
        catch {
            $result.Failed += [pscustomobject]@{
                Path  = $path
                Error = $_.Exception.Message
            }
        }
    }

    return $result
}

function Get-VoltaNodeDefaultRestoreCandidate {
    param([hashtable]$InstalledMap)

    if ($null -eq $InstalledMap -or $InstalledMap.Count -le 0) { return $null }
    return (Get-NodeDefaultReplacementVersion -InstalledMap $InstalledMap -ExcludeVersion '')
}

function Get-NodeBrowseUninstallSimulatedRemainingMap {
    param(
        [hashtable]$InstalledMap,
        [array]$VersionsToRemove
    )

    if ($null -eq $InstalledMap) { $InstalledMap = @{} }

    $remaining = @{}
    foreach ($key in @($InstalledMap.Keys)) {
        $remaining[[string]$key] = $true
    }
    foreach ($ver in @($VersionsToRemove)) {
        $norm = Normalize-NodeVersionLabel -Version $ver
        if ($norm) {
            $remaining.Remove($norm) | Out-Null
        }
    }
    return $remaining
}

function Test-NodeBrowseUninstallDefaultRestorePlanned {
    param(
        [string]$InitialDefault,
        [hashtable]$InstalledMap,
        [array]$OrderedVersions
    )

    if (-not (Test-VoltaDefaultVersionWasUninstalled -InitialDefault $InitialDefault `
            -SuccessfullyUninstalledVersions $OrderedVersions)) {
        return $false
    }

    $remaining = Get-NodeBrowseUninstallSimulatedRemainingMap -InstalledMap $InstalledMap `
        -VersionsToRemove $OrderedVersions
    if ($remaining.Count -le 0) { return $false }

    $replacement = Get-VoltaNodeDefaultRestoreCandidate -InstalledMap $remaining
    return [bool]$replacement
}

function Get-NodeBrowseUninstallOperationPlan {
    param(
        [string]$InitialDefault,
        [hashtable]$InstalledMap,
        [array]$OrderedVersions
    )

    $ordered = @($OrderedVersions)
    $uninstallCount = $ordered.Count
    $defaultPlanned = $false
    $replacement = $null

    if ($uninstallCount -gt 0 -and (Test-NodeBrowseUninstallDefaultRestorePlanned -InitialDefault $InitialDefault `
            -InstalledMap $InstalledMap -OrderedVersions $ordered)) {
        $remaining = Get-NodeBrowseUninstallSimulatedRemainingMap -InstalledMap $InstalledMap `
            -VersionsToRemove $ordered
        $replacement = Get-VoltaNodeDefaultRestoreCandidate -InstalledMap $remaining
        $defaultPlanned = [bool]$replacement
    }

    return @{
        UninstallCount            = $uninstallCount
        DefaultRestorePlanned     = $defaultPlanned
        DefaultRestoreReplacement = $replacement
        TotalSteps                = $uninstallCount + $(if ($defaultPlanned) { 1 } else { 0 })
    }
}

function Test-VoltaDefaultVersionWasUninstalled {
    param(
        [string]$InitialDefault,
        [array]$SuccessfullyUninstalledVersions
    )

    $initial = Normalize-NodeVersionLabel -Version $InitialDefault
    if (-not $initial) { return $false }

    foreach ($ver in @($SuccessfullyUninstalledVersions)) {
        $norm = Normalize-NodeVersionLabel -Version $ver
        if ($norm -and $norm -eq $initial) { return $true }
    }
    return $false
}

function Test-VoltaNodeDefaultNeedsIntervention {
    param(
        [hashtable]$InstalledMap,
        [string]$CurrentDefault
    )

    if ($null -eq $InstalledMap -or $InstalledMap.Count -le 0) { return $false }

    $expected = Get-VoltaNodeDefaultRestoreCandidate -InstalledMap $InstalledMap
    if (-not $expected) { return $false }

    $current = Normalize-NodeVersionLabel -Version $CurrentDefault
    $expectedNorm = Normalize-NodeVersionLabel -Version $expected

    # Volta already set the highest remaining installed version as default.
    if ($current -and $InstalledMap.ContainsKey($current) -and $current -eq $expectedNorm) {
        return $false
    }

    return $true
}

function Test-VoltaNodeVersionAbsent {
    param([string]$Version)

    $norm = Normalize-NodeVersionLabel -Version $Version
    if ([string]::IsNullOrWhiteSpace($norm)) { return $false }

    $info = Get-VoltaNodeVersionInfo
    return -not $info.Map.ContainsKey($norm)
}
