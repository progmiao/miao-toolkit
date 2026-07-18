# test-claude-plugin-state.ps1 — 插件安装记录与 registry 合并

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$lib = Join-Path $root 'package\core\lib'
. (Join-Path $lib 'bootstrap\Load-Core.ps1') -LibDirectory $lib
Initialize-Paths -BinDirectory (Join-Path $root 'package\bin')

$toolRoot = Join-Path $root 'package\tools\05-claude-code'
Initialize-PathsFromToolRoot -ToolRoot $toolRoot

# Isolated load (simulates Start-Job scriptblock before core is imported)
Remove-Item Function:Get-UserConfigDirectory -ErrorAction SilentlyContinue
. (Join-Path $toolRoot 'lib\claude-plugin-state.ps1')
$isolatedPath = Get-ClaudePluginInstallStatePath
if ($isolatedPath -notmatch 'claude-code-plugins\.json$') {
    throw "isolated load path unexpected: $isolatedPath"
}

. (Join-Path $toolRoot 'lib\claude-code-core.ps1')
. (Join-Path $toolRoot 'lib\claude-plugin.ps1')
. (Join-Path $toolRoot 'lib\claude-plugin-state.ps1')

$tmpdir = Join-Path ([IO.Path]::GetTempPath()) ("miao-cc-plugin-" + [Guid]::NewGuid().ToString('n'))
$prevHome = $env:USERPROFILE
$prevAppData = $env:APPDATA
$statePath = $null
try {
    $fakeHome = Join-Path $tmpdir 'home'
    $fakeAppData = Join-Path $tmpdir 'appdata'
    $pluginsDir = Join-Path (Join-Path $fakeHome '.claude') 'plugins'
    New-Item -ItemType Directory -Path $pluginsDir -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $fakeAppData 'Miao') -Force | Out-Null
    $env:USERPROFILE = $fakeHome
    $env:APPDATA = $fakeAppData
    Set-Item -Path Env:HOME -Value $fakeHome

    $registryPath = Join-Path $pluginsDir 'installed_plugins.json'
    @{
        version = 2
        plugins = @{
            'superpowers@superpowers-marketplace' = @(
                @{
                    scope       = 'user'
                    version     = '1.0.0'
                    installPath = 'C:\fake\cache\superpowers\1.0.0'
                }
            )
        }
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $registryPath -Encoding UTF8

    $registryEntries = @(Get-ClaudePluginRegistryEntries)
    if ($registryEntries.Count -ne 1) {
        throw "expected 1 registry entry, got $($registryEntries.Count)"
    }
    if ([string]$registryEntries[0].PluginId -ne 'superpowers@superpowers-marketplace') {
        throw "unexpected registry plugin id: $($registryEntries[0].PluginId)"
    }

    Set-ClaudePluginInstallRecord -PluginId 'alpha@test' -Version '2.0.0'
    $statePath = Get-ClaudePluginInstallStatePath
    if (-not (Test-Path -LiteralPath $statePath)) {
        throw 'install state file not written'
    }

    $entryMap = Get-ClaudePluginInstalledEntryMap
    if ($entryMap.Count -lt 2) {
        throw "expected at least 2 merged entries, got $($entryMap.Count)"
    }
    if (-not $entryMap.ContainsKey('superpowers@superpowers-marketplace')) {
        throw 'registry plugin missing from merged map'
    }
    if (-not $entryMap.ContainsKey('alpha@test')) {
        throw 'miao record missing from merged map'
    }

    $catalogMap = @{
        'superpowers@superpowers-marketplace' = '1.1.0'
        'alpha@test'                          = '2.1.0'
    }
    $installedEntry = [pscustomobject]@{
        PluginId = 'superpowers@superpowers-marketplace'
        version  = '1.0.0'
    }
    if (-not (Test-ClaudePluginUpdateAvailable -InstalledEntry $installedEntry -CatalogVersionMap $catalogMap)) {
        throw 'superpowers should be updatable'
    }

    $staleCatalog = @{ 'beta@test' = '6.0.3' }
    $newerAvailable = [pscustomobject]@{ PluginId = 'beta@test'; version = '6.1.0' }
    if (-not (Test-ClaudePluginUpdateAvailable -InstalledEntry $newerAvailable -CatalogVersionMap $staleCatalog `
            -AvailableVersion '6.2.0')) {
        throw 'update check should use CLI available version when catalog is stale'
    }
    if ((Resolve-ClaudePluginLatestVersion -PluginId 'beta@test' -AvailableVersion '6.1.1' `
            -CatalogVersionMap @{ 'beta@test' = '6.0.3' }) -ne '6.1.1') {
        throw 'latest version should take max of catalog and available'
    }

    Remove-ClaudePluginInstallRecord -PluginId 'alpha@test'
    $records = @(Get-ClaudePluginInstallRecords)
    if ($records.Count -ne 0) {
        throw 'record should be removed'
    }
}
finally {
    $env:USERPROFILE = $prevHome
    $env:APPDATA = $prevAppData
    Remove-Item -LiteralPath $tmpdir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'test-claude-plugin-state: OK'
