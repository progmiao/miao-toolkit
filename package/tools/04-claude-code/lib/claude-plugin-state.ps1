# claude-code — 插件安装记录（Miao 侧）与 Claude 本地 registry 合并

if (-not (Get-Command Get-UserConfigDirectory -ErrorAction SilentlyContinue)) {
    $claudePluginStateCoreLib = Join-Path $PSScriptRoot '..\..\..\core\lib'
    . (Join-Path $claudePluginStateCoreLib 'config\UserConfig.ps1')
}

function Get-ClaudePluginInstallStatePath {
    Join-Path (Get-UserConfigDirectory) 'claude-code-plugins.json'
}

function Get-ClaudePluginRegistryPath {
    Join-Path (Join-Path (Join-Path $env:USERPROFILE '.claude') 'plugins') 'installed_plugins.json'
}

function Read-ClaudePluginInstallStateDocument {
    $path = Get-ClaudePluginInstallStatePath
    if (-not (Test-Path -LiteralPath $path)) {
        return @{ plugins = @{} }
    }

    try {
        $raw = Get-Content -Raw -LiteralPath $path -Encoding UTF8 | ConvertFrom-Json
        $map = @{}
        if ($raw -and $raw.PSObject.Properties['plugins']) {
            foreach ($prop in $raw.plugins.PSObject.Properties) {
                $entry = $prop.Value
                $map[[string]$prop.Name] = @{
                    pluginId    = [string]$prop.Name
                    version     = if ($entry.PSObject.Properties['version']) { [string]$entry.version } else { '' }
                    installedAt = if ($entry.PSObject.Properties['installedAt']) { [string]$entry.installedAt } else { '' }
                }
            }
        }
        return @{ plugins = $map }
    }
    catch {
        return @{ plugins = @{} }
    }
}

function Save-ClaudePluginInstallStateDocument {
    param([hashtable]$Document)

    $dir = Get-UserConfigDirectory
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $payload = @{ plugins = @{} }
    foreach ($key in @($Document.plugins.Keys)) {
        $entry = $Document.plugins[$key]
        $payload.plugins[[string]$key] = @{
            pluginId    = [string]$entry.pluginId
            version     = [string]$entry.version
            installedAt = [string]$entry.installedAt
        }
    }

    $json = ($payload | ConvertTo-Json -Depth 4)
    [IO.File]::WriteAllText((Get-ClaudePluginInstallStatePath), $json, [Text.UTF8Encoding]::new($true))
}

function Get-ClaudePluginInstallRecords {
    $doc = Read-ClaudePluginInstallStateDocument
    return @($doc.plugins.Values | Sort-Object { [string]$_.pluginId })
}

function Get-ClaudePluginInstallRecordMap {
    $doc = Read-ClaudePluginInstallStateDocument
    return $doc.plugins
}

function Set-ClaudePluginInstallRecord {
    param(
        [string]$PluginId,
        [string]$Version = ''
    )

    if ([string]::IsNullOrWhiteSpace($PluginId)) { return }

    $doc = Read-ClaudePluginInstallStateDocument
    $doc.plugins[[string]$PluginId] = @{
        pluginId    = [string]$PluginId
        version     = [string]$Version
        installedAt = (Get-Date).ToString('o')
    }
    Save-ClaudePluginInstallStateDocument -Document $doc
}

function Remove-ClaudePluginInstallRecord {
    param([string]$PluginId)

    if ([string]::IsNullOrWhiteSpace($PluginId)) { return }

    $doc = Read-ClaudePluginInstallStateDocument
    if ($doc.plugins.ContainsKey([string]$PluginId)) {
        $doc.plugins.Remove([string]$PluginId)
        Save-ClaudePluginInstallStateDocument -Document $doc
    }
}

function Register-ClaudePluginInstallSuccess {
    param([string]$PluginId)

    if ([string]::IsNullOrWhiteSpace($PluginId)) { return }

    $version = ''
    foreach ($entry in @(Get-ClaudePluginRegistryEntries)) {
        if ([string]$entry.PluginId -ne [string]$PluginId) { continue }
        $version = [string]$entry.version
        break
    }

    if ([string]::IsNullOrWhiteSpace($version)) {
        $catalogMap = Get-ClaudeMarketplaceCatalogVersionMap
        if ($catalogMap.ContainsKey($PluginId)) {
            $version = [string]$catalogMap[$PluginId]
        }
    }

    Set-ClaudePluginInstallRecord -PluginId $PluginId -Version $version
}

function Register-ClaudePluginUpdateSuccess {
    param([string]$PluginId)

    Register-ClaudePluginInstallSuccess -PluginId $PluginId
}

function Get-ClaudePluginRegistryEntries {
    $path = Get-ClaudePluginRegistryPath
    if (-not (Test-Path -LiteralPath $path)) {
        return @()
    }

    try {
        $raw = Get-Content -Raw -LiteralPath $path -Encoding UTF8 | ConvertFrom-Json
        if (-not $raw -or -not $raw.PSObject.Properties['plugins']) {
            return @()
        }

        $entries = @()
        foreach ($prop in $raw.plugins.PSObject.Properties) {
            $pluginId = [string]$prop.Name
            if ([string]::IsNullOrWhiteSpace($pluginId)) { continue }

            $installs = @($prop.Value)
            if ($installs.Count -le 0) { continue }

            $picked = @($installs | Where-Object {
                $_.PSObject.Properties['scope'] -and [string]$_.scope -eq 'user'
            } | Select-Object -First 1)
            if ($picked.Count -le 0) {
                $picked = @($installs | Select-Object -First 1)
            }

            $inst = $picked[0]
            $version = if ($inst.PSObject.Properties['version']) { [string]$inst.version } else { '' }
            $split = Split-ClaudePluginId -PluginId $pluginId

            $entries += [pscustomobject]@{
                PluginId        = $pluginId
                name            = $split.Name
                marketplaceName = $split.Marketplace
                version         = $version
            }
        }

        return @($entries | Sort-Object PluginId)
    }
    catch {
        return @()
    }
}

function Get-ClaudePluginInstalledEntryMap {
    $map = @{}

    try {
        $json = Invoke-ClaudePluginListJson
        foreach ($entry in @(Get-ClaudePluginInstalledEntries -JsonData $json)) {
            $pluginId = Get-ClaudePluginDisplayId -Entry $entry
            if (-not [string]::IsNullOrWhiteSpace($pluginId)) {
                $map[$pluginId] = $entry
            }
        }
    }
    catch {
        # CLI 列表不可用时继续合并本地来源
    }

    foreach ($entry in @(Get-ClaudePluginRegistryEntries)) {
        $pluginId = [string]$entry.PluginId
        if ([string]::IsNullOrWhiteSpace($pluginId)) { continue }
        if (-not $map.ContainsKey($pluginId)) {
            $map[$pluginId] = $entry
        }
    }

    $recordMap = Get-ClaudePluginInstallRecordMap
    foreach ($pluginId in @($recordMap.Keys)) {
        if ($map.ContainsKey($pluginId)) { continue }
        $record = $recordMap[$pluginId]
        $map[$pluginId] = [pscustomobject]@{
            PluginId = [string]$pluginId
            version  = [string]$record.version
        }
    }

    return $map
}

function Resolve-ClaudePluginInstalledVersion {
    param(
        $Entry,
        [string]$PluginId,
        [hashtable]$RecordMap = $null
    )

    if ($Entry -and $Entry.PSObject.Properties['version'] -and -not [string]::IsNullOrWhiteSpace([string]$Entry.version)) {
        return [string]$Entry.version
    }

    if ($RecordMap -and $RecordMap.ContainsKey($PluginId)) {
        $recordVersion = [string]$RecordMap[$PluginId].version
        if (-not [string]::IsNullOrWhiteSpace($recordVersion)) {
            return $recordVersion
        }
    }

    return ''
}
