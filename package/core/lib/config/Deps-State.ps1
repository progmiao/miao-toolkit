# 第三方依赖全局状态（%APPDATA%\Miao\deps-state.json）
# packages 按依赖指纹记录；工具只引用 packages，不按 toolId 分组。

$script:DepsStateCache = $null
$script:DepsStateMigrated = $false

function Get-DepsStatePath {
    Join-Path (Get-UserConfigDirectory) 'deps-state.json'
}

function Test-DepsStateLegacyToolGroupedDocument {
    param([hashtable]$Document)

    if ($null -eq $Document -or $Document.Count -eq 0) { return $false }
    if ($Document.ContainsKey('packages')) { return $false }

    foreach ($key in $Document.Keys) {
        $entry = $Document[$key]
        if ($entry -and $entry.dependencies) { return $true }
    }

    return $false
}

function ConvertTo-DepsStateHashtable {
    param($Object)

    if ($null -eq $Object) { return @{ packages = @{} } }

    if ($null -ne $Object.PSObject.Properties['packages']) {
        $pkgMap = @{}
        foreach ($prop in $Object.packages.PSObject.Properties) {
            $entry = $prop.Value
            $pkgMap[[string]$prop.Name] = @{
                name        = [string]$entry.name
                version     = [string]$entry.version
                installedAt = [string]$entry.installedAt
                backend     = if ($entry.backend) { @{
                    type      = [string]$entry.backend.type
                    packageId = [string]$entry.backend.packageId
                } } else { $null }
            }
        }
        return @{ packages = $pkgMap }
    }

    $legacy = @{}
    foreach ($prop in $Object.PSObject.Properties) {
        $toolId = [string]$prop.Name
        $entry = $prop.Value
        $depsMap = @{}
        if ($entry.dependencies) {
            foreach ($depProp in $entry.dependencies.PSObject.Properties) {
                $depEntry = $depProp.Value
                $depsMap[[string]$depProp.Name] = @{
                    version     = [string]$depEntry.version
                    installedAt = [string]$depEntry.installedAt
                }
            }
        }
        $legacy[$toolId] = @{
            installedAt  = [string]$entry.installedAt
            dependencies = $depsMap
        }
    }
    return $legacy
}

function Get-DependencyFingerprint {
    param($Dependency)

    if ($Dependency.install -and $Dependency.install.type -and $Dependency.install.packageId) {
        return '{0}:{1}' -f [string]$Dependency.install.type, [string]$Dependency.install.packageId
    }
    if ($Dependency.name) {
        return 'name:{0}' -f [string]$Dependency.name
    }
    return 'default'
}

function Get-DependencyRecordId {
    param($Dependency)

    return Get-DependencyFingerprint -Dependency $Dependency
}

function Migrate-LegacyDepsStateToGlobal {
    param(
        [hashtable]$Document,
        [array]$Tools = $null
    )

    if (-not (Test-DepsStateLegacyToolGroupedDocument -Document $Document)) {
        if (-not $Document.ContainsKey('packages')) {
            $Document['packages'] = @{}
        }
        return $Document
    }

    if ($null -eq $Tools) {
        if (Get-Command Get-ToolkitTools -ErrorAction SilentlyContinue) {
            $Tools = @(Get-ToolkitTools)
        }
        else {
            $Tools = @(Discover-Tools)
        }
    }

    $packages = @{}
    foreach ($tool in @($Tools)) {
        if (-not (Test-ToolHasExternalDeps $tool)) { continue }

        $toolKey = [string]$tool.id
        if (-not $Document.ContainsKey($toolKey)) { continue }

        $entry = $Document[$toolKey]
        if (-not $entry.dependencies) { continue }

        foreach ($pkg in @(Get-ToolDependencyPackages -Tool $tool)) {
            $legacyId = if ($pkg.name) { [string]$pkg.name } else { Get-DependencyFingerprint -Dependency $pkg }
            if (-not $entry.dependencies.ContainsKey($legacyId)) { continue }

            $legacyDep = $entry.dependencies[$legacyId]
            $fp = Get-DependencyFingerprint -Dependency $pkg
            if ([string]::IsNullOrWhiteSpace([string]$legacyDep.version)) { continue }

            $existing = if ($packages.ContainsKey($fp)) { $packages[$fp] } else { $null }
            if ($existing -and -not [string]::IsNullOrWhiteSpace([string]$existing.version)) { continue }

            $backend = $null
            if ($pkg.install -and $pkg.install.type) {
                $backend = @{
                    type      = [string]$pkg.install.type
                    packageId = if ($pkg.install.packageId) { [string]$pkg.install.packageId } else { '' }
                }
            }

            $packages[$fp] = @{
                name        = if ($pkg.name) { [string]$pkg.name } else { $fp }
                version     = [string]$legacyDep.version
                installedAt = if ($legacyDep.installedAt) { [string]$legacyDep.installedAt } else { (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss') }
                backend     = $backend
            }
        }
    }

    $path = Get-DepsStatePath
    if (Test-Path $path) {
        $bak = "$path.bak"
        Copy-Item -LiteralPath $path -Destination $bak -Force
    }

    return @{ packages = $packages }
}

function Get-DepsStateDocument {
    if ($null -ne $script:DepsStateCache) {
        return $script:DepsStateCache
    }

    $path = Get-DepsStatePath
    if (-not (Test-Path $path)) {
        $script:DepsStateCache = @{ packages = @{} }
        return $script:DepsStateCache
    }

    $raw = Get-Content -Raw -Path $path -Encoding UTF8 | ConvertFrom-Json
    $doc = ConvertTo-DepsStateHashtable -Object $raw

    if (Test-DepsStateLegacyToolGroupedDocument -Document $doc) {
        $doc = Migrate-LegacyDepsStateToGlobal -Document $doc
        Save-DepsStateDocument -Document $doc
        $script:DepsStateMigrated = $true
    }
    elseif (-not $doc.ContainsKey('packages')) {
        $doc['packages'] = @{}
    }

    $script:DepsStateCache = $doc
    return $script:DepsStateCache
}

function Get-GlobalDepPackagesMap {
    $doc = Get-DepsStateDocument
    if (-not $doc.packages) {
        $doc['packages'] = @{}
    }
    return $doc.packages
}

function ConvertFrom-DepsStateHashtable {
    param([hashtable]$Document)

    $root = [ordered]@{}
    $packages = [ordered]@{}
    $pkgMap = if ($Document.packages) { $Document.packages } else { @{} }

    foreach ($fp in ($pkgMap.Keys | Sort-Object)) {
        $entry = $pkgMap[$fp]
        $item = [ordered]@{
            name        = [string]$entry.name
            version     = [string]$entry.version
            installedAt = [string]$entry.installedAt
        }
        if ($entry.backend) {
            $item['backend'] = [ordered]@{
                type      = [string]$entry.backend.type
                packageId = [string]$entry.backend.packageId
            }
        }
        $packages[$fp] = $item
    }

    $root['packages'] = $packages
    return $root
}

function Save-DepsStateDocument {
    param([hashtable]$Document)

    if (-not $Document.ContainsKey('packages')) {
        $Document['packages'] = @{}
    }

    $dir = Get-UserConfigDirectory
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $path = Get-DepsStatePath
    $ordered = ConvertFrom-DepsStateHashtable -Document $Document
    $json = ($ordered | ConvertTo-Json -Depth 6)
    [IO.File]::WriteAllText($path, $json, [Text.UTF8Encoding]::new($true))
    $script:DepsStateCache = $Document
    Clear-ToolkitHomeStatusCache
}

function Clear-DepsStateCache {
    $script:DepsStateCache = $null
}

function Clear-ToolkitHomeStatusCache {
    if ($script:ToolkitShell) {
        $script:ToolkitShell.Remove('HomeToolStatusMap')
        $script:ToolkitShell.Remove('HomeToolStatusKey')
    }
}

function Get-GlobalDepRecordedVersion {
    param([string]$Fingerprint)

    if ([string]::IsNullOrWhiteSpace($Fingerprint)) { return $null }

    $packages = Get-GlobalDepPackagesMap
    if (-not $packages.ContainsKey($Fingerprint)) { return $null }
    return [string]$packages[$Fingerprint].version
}

function Get-ToolDepRecordedVersion {
    param(
        [string]$ToolId = '',
        [string]$DependencyId
    )

    return Get-GlobalDepRecordedVersion -Fingerprint $DependencyId
}

function Set-GlobalDepPackageVersion {
    param(
        [string]$Fingerprint,
        [string]$Name,
        [string]$Version,
        $Package = $null
    )

    if ([string]::IsNullOrWhiteSpace($Fingerprint)) { return }
    if ([string]::IsNullOrWhiteSpace($Version)) { return }

    $doc = Get-DepsStateDocument
    $packages = Get-GlobalDepPackagesMap
    $now = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')

    $backend = $null
    if ($Package -and $Package.install -and $Package.install.type) {
        $backend = @{
            type      = [string]$Package.install.type
            packageId = if ($Package.install.packageId) { [string]$Package.install.packageId } else { '' }
        }
    }

    $displayName = if (-not [string]::IsNullOrWhiteSpace($Name)) { [string]$Name } else { $Fingerprint }
    $packages[$Fingerprint] = @{
        name        = $displayName
        version     = [string]$Version
        installedAt = $now
        backend     = $backend
    }

    Save-DepsStateDocument -Document $doc
}

function Set-ToolDepPackageVersion {
    param(
        [string]$ToolId,
        [string]$DependencyId,
        [string]$Version,
        $Package = $null
    )

    $name = $DependencyId
    if ($Package -and $Package.name) { $name = [string]$Package.name }
    Set-GlobalDepPackageVersion -Fingerprint $DependencyId -Name $name -Version $Version -Package $Package
}

function Set-ToolDepInstalled {
    param(
        [string]$ToolId,
        [hashtable]$DependencyVersions,
        [array]$Packages = $null
    )

    if ($DependencyVersions.Count -eq 0) { return }

    $pkgById = @{}
    if ($Packages) {
        foreach ($pkg in @($Packages)) {
            $pkgById[(Get-DependencyFingerprint -Dependency $pkg)] = $pkg
        }
    }

    foreach ($depId in $DependencyVersions.Keys) {
        $version = [string]$DependencyVersions[$depId]
        if ([string]::IsNullOrWhiteSpace($version)) { continue }
        $pkg = if ($pkgById.ContainsKey($depId)) { $pkgById[$depId] } else { $null }
        Set-GlobalDepPackageVersion -Fingerprint ([string]$depId) -Name $depId -Version $version -Package $pkg
    }
}

function Remove-GlobalDepPackage {
    param([string]$Fingerprint)

    if ([string]::IsNullOrWhiteSpace($Fingerprint)) { return $false }

    $doc = Get-DepsStateDocument
    $packages = Get-GlobalDepPackagesMap
    if (-not $packages.ContainsKey($Fingerprint)) { return $false }

    $packages.Remove($Fingerprint)
    Save-DepsStateDocument -Document $doc
    return $true
}

function Remove-ToolDepInstalled {
    param([string]$ToolId)

    # 兼容旧调用：全局模型下不再按 toolId 删除；保留空操作避免破坏 CLI 测试。
}

function Test-GlobalDepSatisfied {
    param($Package)

    $fp = Get-DependencyFingerprint -Dependency $Package
    $recorded = Get-GlobalDepRecordedVersion -Fingerprint $fp
    $checkCommand = if ($Package.checkCommand) { [string]$Package.checkCommand } else { '' }
    $commandAvailable = Test-ToolDepCommandAvailable -CheckCommand $checkCommand

    $packageId = if ($Package.install -and $Package.install.packageId) { [string]$Package.install.packageId } else { '' }
    $wingetInstalled = $false
    if ($packageId -and (Get-Command winget -ErrorAction SilentlyContinue)) {
        $wingetVer = Get-WingetPackageInstalledVersion -PackageId $packageId
        $wingetInstalled = -not [string]::IsNullOrWhiteSpace($wingetVer)
    }

    if ($commandAvailable -or $wingetInstalled) {
        if (-not [string]::IsNullOrWhiteSpace($recorded)) { return $true }
        return $true
    }

    return -not [string]::IsNullOrWhiteSpace($recorded)
}

function Test-ToolDepInstalled {
    param($Tool)

    if (-not (Test-ToolHasExternalDeps $Tool)) { return $true }

    foreach ($dep in @(Get-ToolDependencyPackages -Tool $Tool)) {
        if (-not (Test-GlobalDepSatisfied -Package $dep)) {
            return $false
        }
    }

    return $true
}

function Resolve-ToolDependencyVersionsAfterInstall {
    param($Tool)

    $result = @{}
    foreach ($dep in @(Get-ToolDependencyPackages -Tool $Tool)) {
        $depId = Get-DependencyFingerprint -Dependency $dep
        $version = $null

        if ($dep.install -and $dep.install.packageId) {
            $version = Get-WingetPackageInstalledVersion -PackageId ([string]$dep.install.packageId)
        }

        if ([string]::IsNullOrWhiteSpace($version)) {
            $policy = (Get-DependencyVersionPolicy -Dependency $dep).Trim()
            if ($policy -and ($policy.ToLowerInvariant() -ne 'latest')) {
                $version = $policy
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($version)) {
            $result[$depId] = $version
        }
    }

    return $result
}

function Test-ToolDepUninstallBlockedByOtherTools {
    param(
        $Package,
        [array]$Tools,
        [string]$ExcludeToolId
    )

    $fp = Get-DependencyFingerprint -Dependency $Package
    $others = @(Get-ToolsReferencingDependency -Fingerprint $fp -Tools $Tools -ExcludeToolId $ExcludeToolId)
    return ($others.Count -gt 0)
}

