# claude-code — 插件列表解析与 CLI 操作

function Get-ClaudeFeaturedPluginNameColor {
    return [System.ConsoleColor]::Yellow
}

function ConvertFrom-ClaudePluginJson {
    param([string]$JsonText)

    if ([string]::IsNullOrWhiteSpace($JsonText)) {
        return $null
    }

    return ($JsonText | ConvertFrom-Json)
}

function Invoke-ClaudePluginListJson {
    param(
        [switch]$IncludeAvailable,
        [int]$TimeoutMs = 180000
    )

    $args = @('plugin', 'list', '--json')
    if ($IncludeAvailable.IsPresent) {
        $args += '--available'
    }

    $result = Invoke-ClaudeCodeCliCommand -ArgumentList $args -TimeoutMs $TimeoutMs
    if ($result.ExitCode -ne 0) {
        throw ($result.Output.Trim())
    }

    return ConvertFrom-ClaudePluginJson -JsonText $result.Output
}

function Get-ClaudePluginInstalledEntries {
    param($JsonData)

    if ($null -eq $JsonData) { return @() }

    if ($JsonData.PSObject.Properties['installed']) {
        return @($JsonData.installed)
    }

    if ($JsonData -is [System.Collections.IEnumerable] -and $JsonData -isnot [string]) {
        return @($JsonData)
    }

    return @()
}

function Get-ClaudePluginAvailableEntries {
    param($JsonData)

    if ($null -eq $JsonData) { return @() }

    if ($JsonData.PSObject.Properties['available']) {
        return @($JsonData.available)
    }

    return @()
}

function Get-ClaudePluginDisplayId {
    param($Entry)

    if ($null -eq $Entry) { return '' }

    foreach ($key in @('id', 'pluginId')) {
        if ($Entry.PSObject.Properties[$key] -and -not [string]::IsNullOrWhiteSpace([string]$Entry.$key)) {
            return [string]$Entry.$key
        }
    }

    $name = if ($Entry.PSObject.Properties['name']) { [string]$Entry.name } else { '' }
    $marketplace = if ($Entry.PSObject.Properties['marketplaceName']) {
        [string]$Entry.marketplaceName
    }
    else { '' }

    if ($name -and $marketplace) {
        return "$name@$marketplace"
    }

    return $name
}

function Split-ClaudePluginId {
    param([string]$PluginId)

    $text = [string]$PluginId
    if ([string]::IsNullOrWhiteSpace($text)) {
        return @{ Name = ''; Marketplace = '' }
    }

    $at = $text.LastIndexOf('@')
    if ($at -lt 1) {
        return @{ Name = $text; Marketplace = '' }
    }

    return @{
        Name        = $text.Substring(0, $at)
        Marketplace = $text.Substring($at + 1)
    }
}

function Compare-ClaudeSemVersion {
    param(
        [string]$Left,
        [string]$Right
    )

    if ([string]::IsNullOrWhiteSpace($Left) -or [string]::IsNullOrWhiteSpace($Right)) {
        return 0
    }

    $leftParts = @($Left.Split('.') | ForEach-Object {
        if ($_ -match '^\d+') { [int]$Matches[0] } else { 0 }
    })
    $rightParts = @($Right.Split('.') | ForEach-Object {
        if ($_ -match '^\d+') { [int]$Matches[0] } else { 0 }
    })
    $count = [Math]::Max($leftParts.Count, $rightParts.Count)

    for ($i = 0; $i -lt $count; $i++) {
        $l = if ($i -lt $leftParts.Count) { [int]$leftParts[$i] } else { 0 }
        $r = if ($i -lt $rightParts.Count) { [int]$rightParts[$i] } else { 0 }
        if ($l -gt $r) { return 1 }
        if ($l -lt $r) { return -1 }
    }

    return 0
}

function Get-ClaudeMarketplaceCatalogVersionMap {
    $map = @{}
    $root = Join-Path (Join-Path $env:USERPROFILE '.claude') 'plugins\marketplaces'
    if (-not (Test-Path -LiteralPath $root)) {
        return $map
    }

    foreach ($marketDir in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
        $marketplaceName = [string]$marketDir.Name
        $catalogPath = Join-Path (Join-Path $marketDir.FullName '.claude-plugin') 'marketplace.json'
        if (-not (Test-Path -LiteralPath $catalogPath)) { continue }

        try {
            $catalog = Get-Content -Raw -LiteralPath $catalogPath -Encoding UTF8 | ConvertFrom-Json
            foreach ($entry in @($catalog.plugins)) {
                $pluginName = [string]$entry.name
                if ([string]::IsNullOrWhiteSpace($pluginName)) { continue }
                $pluginId = "$pluginName@$marketplaceName"
                $version = $null
                if ($entry.PSObject.Properties['version']) {
                    $version = [string]$entry.version
                }
                if (-not [string]::IsNullOrWhiteSpace($version)) {
                    $map[$pluginId] = $version
                }
            }
        }
        catch {
            continue
        }
    }

    return $map
}

function Test-ClaudePluginUpdateAvailable {
    param(
        $InstalledEntry,
        [hashtable]$CatalogVersionMap
    )

    $pluginId = Get-ClaudePluginDisplayId -Entry $InstalledEntry
    if ([string]::IsNullOrWhiteSpace($pluginId)) { return $false }
    if (-not $CatalogVersionMap.ContainsKey($pluginId)) { return $false }

    $installedVersion = if ($InstalledEntry.PSObject.Properties['version']) {
        [string]$InstalledEntry.version
    }
    else { '' }

    $catalogVersion = [string]$CatalogVersionMap[$pluginId]
    if ([string]::IsNullOrWhiteSpace($installedVersion) -or [string]::IsNullOrWhiteSpace($catalogVersion)) {
        return $false
    }

    return (Compare-ClaudeSemVersion -Left $catalogVersion -Right $installedVersion) -gt 0
}

function New-ClaudePluginMenuItem {
    param(
        [string]$PluginId,
        [string]$Version = '',
        [string]$Description = '',
        [string]$Tags = '',
        [bool]$Enabled = $true,
        [bool]$Featured = $false,
        $Source = $null
    )

    return [pscustomobject]@{
        PluginId    = $PluginId
        Version     = $Version
        Description = $Description
        Tags        = $Tags
        Enabled     = $Enabled
        Featured    = $Featured
        Source      = $Source
    }
}

function Sort-ClaudePluginMenuItems {
    param(
        [array]$Items,
        [hashtable]$FeaturedOrderMap = $null
    )

    if (-not $FeaturedOrderMap -or $FeaturedOrderMap.Count -le 0) {
        return @($Items | Sort-Object PluginId)
    }

    $featuredRankBase = 1000000
    return @($Items | Sort-Object @{
        Expression = {
            $id = [string]$_.PluginId
            if ($FeaturedOrderMap.ContainsKey($id)) {
                return [int]$FeaturedOrderMap[$id]
            }
            return $featuredRankBase
        }
    }, @{
        Expression = { [string]$_.PluginId }
    })
}

function Get-ClaudePluginInstallMenuItems {
    param([string]$ToolRoot = '')

    $featuredOrderMap = @{}
    if (-not [string]::IsNullOrWhiteSpace($ToolRoot)) {
        if (-not (Get-Command Get-ClaudeCodeFeaturedPluginOrderMap -ErrorAction SilentlyContinue)) {
            . (Join-Path $PSScriptRoot 'claude-code-presets.ps1')
        }
        $featuredOrderMap = Get-ClaudeCodeFeaturedPluginOrderMap -ToolRoot $ToolRoot
    }

    $json = Invoke-ClaudePluginListJson -IncludeAvailable
    $installed = @{}
    foreach ($entry in @(Get-ClaudePluginInstalledEntries -JsonData $json)) {
        $id = Get-ClaudePluginDisplayId -Entry $entry
        if ($id) { $installed[$id] = $true }
    }

    $items = @()
    foreach ($entry in @(Get-ClaudePluginAvailableEntries -JsonData $json)) {
        $pluginId = Get-ClaudePluginDisplayId -Entry $entry
        if ([string]::IsNullOrWhiteSpace($pluginId)) { continue }

        $version = if ($entry.PSObject.Properties['version']) { [string]$entry.version } else { '' }
        $description = if ($entry.PSObject.Properties['description']) { [string]$entry.description } else { '' }
        $tags = if ($installed.ContainsKey($pluginId)) {
            'installed'
        }
        else { '' }

        $featured = $featuredOrderMap.ContainsKey($pluginId)
        $items += New-ClaudePluginMenuItem -PluginId $pluginId -Version $version `
            -Description $description -Tags $tags -Featured:$featured `
            -Enabled:(-not $installed.ContainsKey($pluginId)) -Source $entry
    }

    return (Sort-ClaudePluginMenuItems -Items $items -FeaturedOrderMap $featuredOrderMap)
}

function Get-ClaudePluginInstalledMenuItems {
    param([switch]$ForUpdate)

    $json = Invoke-ClaudePluginListJson
    $catalogMap = if ($ForUpdate.IsPresent) {
        Get-ClaudeMarketplaceCatalogVersionMap
    }
    else {
        @{}
    }

    $items = @()
    foreach ($entry in @(Get-ClaudePluginInstalledEntries -JsonData $json)) {
        $pluginId = Get-ClaudePluginDisplayId -Entry $entry
        if ([string]::IsNullOrWhiteSpace($pluginId)) { continue }

        $version = if ($entry.PSObject.Properties['version']) { [string]$entry.version } else { '' }
        $tags = @()
        if ($version) { $tags += "v$version" }

        if ($ForUpdate.IsPresent -and (Test-ClaudePluginUpdateAvailable -InstalledEntry $entry `
                -CatalogVersionMap $catalogMap)) {
            $catalogVersion = [string]$catalogMap[$pluginId]
            $tags += "update:$catalogVersion"
        }

        $items += New-ClaudePluginMenuItem -PluginId $pluginId -Version $version `
            -Description '' -Tags (($tags -join ' ') -replace '^\s+|\s+$', '') -Enabled $true `
            -Source $entry
    }

    return @($items | Sort-Object PluginId)
}

function Get-ClaudeCodeCliFailureDetail {
    param($Result)

    if ($Result -is [string]) {
        return ([string]$Result).Trim()
    }

    $output = [string]$Result.Output
    if ([string]::IsNullOrWhiteSpace($output)) {
        if ($null -ne $Result -and $Result.PSObject.Properties['ExitCode']) {
            return "exit $($Result.ExitCode)"
        }
        return 'unknown error'
    }

    $lines = @($output -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    foreach ($pattern in @('(?i)Failed to', 'fatal:', 'error:', '×')) {
        $match = @($lines | Where-Object { $_ -match $pattern } | Select-Object -Last 1)
        if ($match) {
            return ($match[0] -replace '\s+', ' ')
        }
    }

    $substantive = @($lines | Where-Object { $_ -notmatch '^(?i)Installing ' })
    if ($substantive.Count -gt 0) {
        return ($substantive[-1] -replace '\s+', ' ')
    }

    return ($lines[-1] -replace '\s+', ' ')
}

function Invoke-ClaudePluginInstall {
    param(
        [string]$PluginId,
        [scriptblock]$OnUiPoll = $null,
        [scriptblock]$OnChromePulse = $null
    )

    return Invoke-ClaudeCodeCliCommand -ArgumentList @(
        'plugin', 'install', $PluginId, '--scope', 'user'
    ) -OnUiPoll $OnUiPoll -OnChromePulse $OnChromePulse
}

function Invoke-ClaudePluginUninstall {
    param(
        [string]$PluginId,
        [scriptblock]$OnUiPoll = $null,
        [scriptblock]$OnChromePulse = $null
    )

    return Invoke-ClaudeCodeCliCommand -ArgumentList @(
        'plugin', 'uninstall', $PluginId, '--scope', 'user'
    ) -OnUiPoll $OnUiPoll -OnChromePulse $OnChromePulse
}

function Invoke-ClaudePluginUpdate {
    param(
        [string]$PluginId,
        [scriptblock]$OnUiPoll = $null,
        [scriptblock]$OnChromePulse = $null
    )

    return Invoke-ClaudeCodeCliCommand -ArgumentList @(
        'plugin', 'update', $PluginId, '--scope', 'user'
    ) -TimeoutMs 300000 -OnUiPoll $OnUiPoll -OnChromePulse $OnChromePulse
}

function Invoke-ClaudePluginMarketplaceAdd {
    param(
        [string]$Source,
        [scriptblock]$OnUiPoll = $null,
        [scriptblock]$OnChromePulse = $null
    )

    return Invoke-ClaudeCodeCliCommand -ArgumentList @(
        'plugin', 'marketplace', 'add', $Source
    ) -OnUiPoll $OnUiPoll -OnChromePulse $OnChromePulse
}

function New-ClaudePluginListLayout {
    # pluginId | detail — 各约半宽；详情列焦点时横向滚动
    return @{
        Widths           = @(0, 0)
        Preset           = 'HalfSplit'
        ScrollColumn     = 1
        ScrollIntervalMs = 300
    }
}

function Build-ClaudePluginRows {
    param(
        [array]$Items,
        [string]$TagsLabelKey,
        [string]$ToolRoot,
        [scriptblock]$GetTagsLabel = $null
    )

    return @($Items | ForEach-Object {
        $item = $_
        $tags = if ($GetTagsLabel) {
            & $GetTagsLabel $item
        }
        else {
            [string]$item.Tags
        }

        $detailParts = @()
        if ($item.Version) {
            $detailParts += [string]$item.Version
        }
        $description = [string]$item.Description
        if (-not [string]::IsNullOrWhiteSpace($description)) {
            $detailParts += $description
        }
        if (-not [string]::IsNullOrWhiteSpace($tags)) {
            $detailParts += $tags
        }

        $cellColors = $null
        if ($item.PSObject.Properties['Featured'] -and [bool]$item.Featured) {
            $cellColors = @(
                (Get-ClaudeFeaturedPluginNameColor)
                [System.ConsoleColor]::Gray
            )
        }

        New-ShellListRow -Id ([string]$item.PluginId) -Cells @(
            [string]$item.PluginId
            ([string]($detailParts -join '  '))
        ) -Payload $item -SearchKey ([string]$item.PluginId) -Enabled ([bool]$item.Enabled) `
            -CellColors $cellColors
    })
}

function Resolve-ClaudePluginPick {
    param($Picked)

    if ($null -eq $Picked) { return @() }

    return @($Picked | ForEach-Object {
        if ($_.Source -and $_.Source.PluginId) {
            return [string]$_.Source.PluginId
        }
        if ($_.PluginId) {
            return [string]$_.PluginId
        }
        if ($_.Source) {
            return (Get-ClaudePluginDisplayId -Entry $_.Source)
        }
        if ($_.SearchKey) {
            return [string]$_.SearchKey
        }
        return $null
    } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Get-ClaudePluginTagsLabel {
    param(
        $Item,
        [string]$ToolRoot,
        [string]$InstalledTagKey = 'claude-code.plugin.tagInstalled',
        [string]$UpdateTagKey = 'claude-code.plugin.tagUpdate'
    )

    $parts = @()
    $rawTags = [string]$Item.Tags
    if ($rawTags -match '(?i)installed') {
        $parts += (Get-ClaudeCodeI18n -ToolRoot $ToolRoot -Key $InstalledTagKey)
    }
    if ($rawTags -match 'update:([^\s]+)') {
        $parts += (Get-ClaudeCodeI18n -ToolRoot $ToolRoot -Key $UpdateTagKey -Vars @{
            version = $Matches[1]
        })
    }
    elseif ($rawTags -match '(?i)^v?\d') {
        $parts += $rawTags
    }

    return ($parts -join ' ')
}
