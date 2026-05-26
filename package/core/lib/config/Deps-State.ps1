# 工具依赖安装状态（%APPDATA%\Miao\deps-state.json）
# 仅记录安装成功；卸载时删除 toolId 条目，不写入 notInstalled。

$script:DepsStateCache = $null

function Get-DepsStatePath {
    Join-Path (Get-UserConfigDirectory) 'deps-state.json'
}

function ConvertTo-DepsStateHashtable {
    param($Object)

    if ($null -eq $Object) { return @{} }

    $map = @{}
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
        $map[$toolId] = @{
            installedAt  = [string]$entry.installedAt
            dependencies = $depsMap
        }
    }
    return $map
}

function Get-DepsStateDocument {
    if ($null -ne $script:DepsStateCache) {
        return $script:DepsStateCache
    }

    $path = Get-DepsStatePath
    if (-not (Test-Path $path)) {
        $script:DepsStateCache = @{}
        return $script:DepsStateCache
    }

    $raw = Get-Content -Raw -Path $path -Encoding UTF8 | ConvertFrom-Json
    $script:DepsStateCache = ConvertTo-DepsStateHashtable -Object $raw
    return $script:DepsStateCache
}

function ConvertFrom-DepsStateHashtable {
    param([hashtable]$Document)

    $root = [ordered]@{}
    foreach ($toolId in ($Document.Keys | Sort-Object)) {
        $entry = $Document[$toolId]
        $deps = [ordered]@{}
        foreach ($depId in ($entry.dependencies.Keys | Sort-Object)) {
            $depEntry = $entry.dependencies[$depId]
            $deps[$depId] = [ordered]@{
                version     = $depEntry.version
                installedAt = $depEntry.installedAt
            }
        }
        $root[$toolId] = [ordered]@{
            installedAt  = $entry.installedAt
            dependencies = $deps
        }
    }
    return $root
}

function Save-DepsStateDocument {
    param([hashtable]$Document)

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

function Get-DependencyRecordId {
    param($Dependency)

    if ($Dependency.name) { return [string]$Dependency.name }
    if ($Dependency.install -and $Dependency.install.packageId) {
        return [string]$Dependency.install.packageId
    }
    return 'default'
}

function Test-ToolDepInstalled {
    param($Tool)

    if (-not (Test-ToolHasExternalDeps $Tool)) { return $true }

    $doc = Get-DepsStateDocument
    if (-not $doc.ContainsKey([string]$Tool.id)) { return $false }

    $entry = $doc[[string]$Tool.id]
    foreach ($dep in @($Tool.dependencies)) {
        $depId = Get-DependencyRecordId -Dependency $dep
        if (-not $entry.dependencies.ContainsKey($depId)) { return $false }
        if ([string]::IsNullOrWhiteSpace($entry.dependencies[$depId].version)) { return $false }
    }

    return $true
}

function Get-ToolDepRecordedVersion {
    param(
        [string]$ToolId,
        [string]$DependencyId
    )

    $doc = Get-DepsStateDocument
    if (-not $doc.ContainsKey($ToolId)) { return $null }

    $entry = $doc[$ToolId]
    if (-not $entry.dependencies.ContainsKey($DependencyId)) { return $null }
    return [string]$entry.dependencies[$DependencyId].version
}

function Set-ToolDepInstalled {
    param(
        [string]$ToolId,
        [hashtable]$DependencyVersions
    )

    if ($DependencyVersions.Count -eq 0) { return }

    $doc = Get-DepsStateDocument
    $now = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
    $depsMap = @{}

    foreach ($depId in $DependencyVersions.Keys) {
        $version = [string]$DependencyVersions[$depId]
        if ([string]::IsNullOrWhiteSpace($version)) { continue }
        $depsMap[[string]$depId] = @{
            version     = $version
            installedAt = $now
        }
    }

    if ($depsMap.Count -eq 0) { return }

    $doc[[string]$ToolId] = @{
        installedAt  = $now
        dependencies = $depsMap
    }

    Save-DepsStateDocument -Document $doc
}

function Remove-ToolDepInstalled {
    param([string]$ToolId)

    $doc = Get-DepsStateDocument
    if (-not $doc.ContainsKey([string]$ToolId)) { return }

    $doc.Remove([string]$ToolId)
    Save-DepsStateDocument -Document $doc
}

function Resolve-ToolDependencyVersionsAfterInstall {
    param($Tool)

    $result = @{}
    foreach ($dep in @($Tool.dependencies)) {
        $depId = Get-DependencyRecordId -Dependency $dep
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
