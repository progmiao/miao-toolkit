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

function Get-ClaudePluginHigherSemVersion {
    param([string[]]$Candidates)

    $best = ''
    foreach ($candidate in @($Candidates)) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        if ([string]::IsNullOrWhiteSpace($best)) {
            $best = [string]$candidate
            continue
        }
        if ((Compare-ClaudeSemVersion -Left ([string]$candidate) -Right $best) -gt 0) {
            $best = [string]$candidate
        }
    }

    return $best
}

function Resolve-ClaudePluginLatestVersion {
    param(
        [string]$PluginId,
        [string]$AvailableVersion = '',
        [hashtable]$CatalogVersionMap = $null
    )

    $catalogVersion = ''
    if ($CatalogVersionMap -and -not [string]::IsNullOrWhiteSpace($PluginId) `
        -and $CatalogVersionMap.ContainsKey($PluginId)) {
        $catalogVersion = [string]$CatalogVersionMap[$PluginId]
    }

    return (Get-ClaudePluginHigherSemVersion -Candidates @($AvailableVersion, $catalogVersion))
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
        [hashtable]$CatalogVersionMap,
        [string]$AvailableVersion = ''
    )

    $pluginId = Get-ClaudePluginDisplayId -Entry $InstalledEntry
    if ([string]::IsNullOrWhiteSpace($pluginId)) { return $false }

    $installedVersion = if ($InstalledEntry.PSObject.Properties['version']) {
        [string]$InstalledEntry.version
    }
    else { '' }

    $latestVersion = Resolve-ClaudePluginLatestVersion -PluginId $pluginId `
        -AvailableVersion $AvailableVersion -CatalogVersionMap $CatalogVersionMap
    if ([string]::IsNullOrWhiteSpace($installedVersion) -or [string]::IsNullOrWhiteSpace($latestVersion)) {
        return $false
    }

    return (Compare-ClaudeSemVersion -Left $latestVersion -Right $installedVersion) -gt 0
}

function New-ClaudePluginMenuItem {
    param(
        [string]$PluginId,
        [string]$Version = '',
        [string]$InstalledVersion = '',
        [string]$UpdateVersion = '',
        [string]$Description = '',
        [string]$Tags = '',
        [bool]$Enabled = $true,
        [bool]$Featured = $false,
        [bool]$HasUpdate = $false,
        $Source = $null
    )

    return [pscustomobject]@{
        PluginId         = $PluginId
        Version          = $Version
        InstalledVersion = $InstalledVersion
        UpdateVersion    = $UpdateVersion
        Description      = $Description
        Tags             = $Tags
        Enabled          = $Enabled
        Featured         = $Featured
        HasUpdate        = $HasUpdate
        Source           = $Source
    }
}

function Test-ClaudePluginMenuItemInstalled {
    param(
        $Item,
        [hashtable]$InstalledMap = $null
    )

    $pluginId = [string]$Item.PluginId
    if ($InstalledMap -and $InstalledMap.ContainsKey($pluginId)) {
        return $true
    }
    if ($Item.PSObject.Properties['Installed'] -and [bool]$Item.Installed) {
        return $true
    }
    if ($Item.PSObject.Properties['HasUpdate'] -and [bool]$Item.HasUpdate) {
        return $true
    }
    if ($Item.PSObject.Properties['InstalledVersion'] -and `
        -not [string]::IsNullOrWhiteSpace([string]$Item.InstalledVersion)) {
        return $true
    }

    $tags = [string]$Item.Tags
    if ($tags -match '(?i)\binstalled\b') {
        return $true
    }

    return $false
}

function Sort-ClaudePluginMenuItems {
    param(
        [array]$Items,
        [hashtable]$FeaturedOrderMap = $null,
        [hashtable]$InstalledMap = $null
    )

    $featuredRankBase = 1000000
    return @($Items | Sort-Object @{
        Expression = {
            if (Test-ClaudePluginMenuItemInstalled -Item $_ -InstalledMap $InstalledMap) { 0 } else { 1 }
        }
    }, @{
        Expression = {
            $id = [string]$_.PluginId
            if ($FeaturedOrderMap -and $FeaturedOrderMap.ContainsKey($id)) {
                return [int]$FeaturedOrderMap[$id]
            }
            if ($_.PSObject.Properties['Featured'] -and [bool]$_.Featured) {
                return 0
            }
            return $featuredRankBase
        }
    }, @{
        Expression = { [string]$_.PluginId }
    })
}

function Get-ClaudePluginManageMenuItems {
    param([string]$ToolRoot = '')

    if (-not (Get-Command Get-ClaudePluginInstalledEntryMap -ErrorAction SilentlyContinue)) {
        . (Join-Path $PSScriptRoot 'claude-plugin-state.ps1')
    }

    $featuredOrderMap = @{}
    if (-not [string]::IsNullOrWhiteSpace($ToolRoot)) {
        if (-not (Get-Command Get-ClaudeCodeFeaturedPluginOrderMap -ErrorAction SilentlyContinue)) {
            . (Join-Path $PSScriptRoot 'claude-code-presets.ps1')
        }
        $featuredOrderMap = Get-ClaudeCodeFeaturedPluginOrderMap -ToolRoot $ToolRoot
    }

    $catalogMap = Get-ClaudeMarketplaceCatalogVersionMap
    $recordMap = Get-ClaudePluginInstallRecordMap
    $entryMap = Get-ClaudePluginInstalledEntryMap

    $json = Invoke-ClaudePluginListJson -IncludeAvailable
    $installed = @{}
    foreach ($entry in @(Get-ClaudePluginInstalledEntries -JsonData $json)) {
        $id = Get-ClaudePluginDisplayId -Entry $entry
        if ($id) { $installed[$id] = $entry }
    }
    foreach ($pluginId in @($entryMap.Keys)) {
        if (-not $installed.ContainsKey($pluginId)) {
            $installed[[string]$pluginId] = $entryMap[$pluginId]
        }
    }

    $items = @()
    $catalogPluginIds = @{}
    foreach ($entry in @(Get-ClaudePluginAvailableEntries -JsonData $json)) {
        $pluginId = Get-ClaudePluginDisplayId -Entry $entry
        if ([string]::IsNullOrWhiteSpace($pluginId)) { continue }
        $catalogPluginIds[[string]$pluginId] = $true

        $entryVersion = if ($entry.PSObject.Properties['version']) { [string]$entry.version } else { '' }
        $latestVersion = Resolve-ClaudePluginLatestVersion -PluginId $pluginId `
            -AvailableVersion $entryVersion -CatalogVersionMap $catalogMap
        $description = if ($entry.PSObject.Properties['description']) { [string]$entry.description } else { '' }

        $isInstalled = $installed.ContainsKey($pluginId)
        $installedVersion = ''
        $updateVersion = ''
        $hasUpdate = $false
        $tags = @()

        if ($isInstalled) {
            $installedEntry = $installed[$pluginId]
            $installedVersion = Resolve-ClaudePluginInstalledVersion -Entry $installedEntry `
                -PluginId $pluginId -RecordMap $recordMap
            $updateEntry = $installedEntry
            if (-not ($updateEntry.PSObject.Properties['version']) `
                -or [string]::IsNullOrWhiteSpace([string]$updateEntry.version)) {
                $updateEntry = [pscustomobject]@{
                    PluginId = $pluginId
                    version  = $installedVersion
                }
            }
            if (Test-ClaudePluginUpdateAvailable -InstalledEntry $updateEntry -CatalogVersionMap $catalogMap `
                -AvailableVersion $entryVersion) {
                $hasUpdate = $true
                $updateVersion = $latestVersion
                $tags += "update:$updateVersion"
            }
            elseif (-not [string]::IsNullOrWhiteSpace($installedVersion) `
                -and -not [string]::IsNullOrWhiteSpace($latestVersion) `
                -and (Compare-ClaudeSemVersion -Left $installedVersion -Right $latestVersion) -le 0) {
                $tags += 'installed'
            }
        }

        $featured = $featuredOrderMap.ContainsKey($pluginId)
        $enabled = (-not $isInstalled) -or $hasUpdate

        $items += New-ClaudePluginMenuItem -PluginId $pluginId -Version $latestVersion `
            -InstalledVersion $installedVersion -UpdateVersion $updateVersion `
            -Description $description -Tags (($tags -join ' ') -replace '^\s+|\s+$', '') `
            -Featured:$featured -HasUpdate:$hasUpdate -Enabled:$enabled -Source $entry
    }

    foreach ($pluginId in @($installed.Keys | Sort-Object)) {
        if ($catalogPluginIds.ContainsKey([string]$pluginId)) { continue }

        $installedEntry = $installed[$pluginId]
        $installedVersion = Resolve-ClaudePluginInstalledVersion -Entry $installedEntry `
            -PluginId $pluginId -RecordMap $recordMap
        $latestVersion = Resolve-ClaudePluginLatestVersion -PluginId $pluginId `
            -CatalogVersionMap $catalogMap
        if ([string]::IsNullOrWhiteSpace($latestVersion)) {
            $latestVersion = $installedVersion
        }
        $updateVersion = ''
        $hasUpdate = $false
        $tags = @()

        $updateEntry = $installedEntry
        if (-not ($updateEntry.PSObject.Properties['version']) `
            -or [string]::IsNullOrWhiteSpace([string]$updateEntry.version)) {
            $updateEntry = [pscustomobject]@{
                PluginId = $pluginId
                version  = $installedVersion
            }
        }
        if (Test-ClaudePluginUpdateAvailable -InstalledEntry $updateEntry -CatalogVersionMap $catalogMap) {
            $hasUpdate = $true
            $updateVersion = $latestVersion
            $tags = @("update:$updateVersion")
        }
        elseif (-not [string]::IsNullOrWhiteSpace($installedVersion) `
            -and -not [string]::IsNullOrWhiteSpace($latestVersion) `
            -and (Compare-ClaudeSemVersion -Left $installedVersion -Right $latestVersion) -le 0) {
            $tags = @('installed')
        }

        $featured = $featuredOrderMap.ContainsKey($pluginId)
        $enabled = $hasUpdate

        $items += New-ClaudePluginMenuItem -PluginId $pluginId -Version $latestVersion `
            -InstalledVersion $installedVersion -UpdateVersion $updateVersion `
            -Description '' -Tags (($tags -join ' ') -replace '^\s+|\s+$', '') `
            -Featured:$featured -HasUpdate:$hasUpdate -Enabled:$enabled -Source $installedEntry
    }

    $installedMap = @{}
    foreach ($pluginId in @($installed.Keys)) {
        $installedMap[[string]$pluginId] = $true
    }

    $deduped = @{}
    $uniqueItems = @()
    foreach ($item in @($items)) {
        $id = [string]$item.PluginId
        if ([string]::IsNullOrWhiteSpace($id)) { continue }
        if ($deduped.ContainsKey($id)) { continue }
        $deduped[$id] = $true
        $uniqueItems += $item
    }

    return (Sort-ClaudePluginMenuItems -Items $uniqueItems -FeaturedOrderMap $featuredOrderMap `
        -InstalledMap $installedMap)
}

function Get-ClaudePluginInstallMenuItems {
    param([string]$ToolRoot = '')

    return @(Get-ClaudePluginManageMenuItems -ToolRoot $ToolRoot)
}

function Get-ClaudePluginInstalledMenuItems {
    param(
        [switch]$ForUpdate,
        [string]$ToolRoot = ''
    )

    if (-not (Get-Command Get-ClaudePluginInstalledEntryMap -ErrorAction SilentlyContinue)) {
        . (Join-Path $PSScriptRoot 'claude-plugin-state.ps1')
    }

    $featuredOrderMap = @{}
    if (-not [string]::IsNullOrWhiteSpace($ToolRoot)) {
        if (-not (Get-Command Get-ClaudeCodeFeaturedPluginOrderMap -ErrorAction SilentlyContinue)) {
            . (Join-Path $PSScriptRoot 'claude-code-presets.ps1')
        }
        $featuredOrderMap = Get-ClaudeCodeFeaturedPluginOrderMap -ToolRoot $ToolRoot
    }

    $catalogMap = if ($ForUpdate.IsPresent) {
        Get-ClaudeMarketplaceCatalogVersionMap
    }
    else {
        @{}
    }
    $recordMap = Get-ClaudePluginInstallRecordMap
    $entryMap = Get-ClaudePluginInstalledEntryMap
    $installedMap = @{}
    foreach ($pluginId in @($entryMap.Keys)) {
        $installedMap[[string]$pluginId] = $true
    }

    $items = @()
    foreach ($pluginId in @($entryMap.Keys)) {
        $entry = $entryMap[$pluginId]
        $version = Resolve-ClaudePluginInstalledVersion -Entry $entry -PluginId $pluginId -RecordMap $recordMap
        $updateVersion = ''
        $hasUpdate = $false
        if ($ForUpdate.IsPresent) {
            $updateEntry = $entry
            if (-not ($updateEntry.PSObject.Properties['version']) -or [string]::IsNullOrWhiteSpace([string]$updateEntry.version)) {
                $updateEntry = [pscustomobject]@{
                    PluginId = $pluginId
                    version  = $version
                }
            }
            if (Test-ClaudePluginUpdateAvailable -InstalledEntry $updateEntry -CatalogVersionMap $catalogMap) {
                $hasUpdate = $true
                $updateVersion = Resolve-ClaudePluginLatestVersion -PluginId $pluginId `
                    -CatalogVersionMap $catalogMap
            }
        }

        $tags = @()
        if (-not $ForUpdate.IsPresent) {
            if ($version) { $tags += "v$version" }
        }

        $enabled = if ($ForUpdate.IsPresent) { $hasUpdate } else { $true }
        $featured = $featuredOrderMap.ContainsKey($pluginId)

        $items += New-ClaudePluginMenuItem -PluginId $pluginId -Version $version `
            -UpdateVersion $updateVersion -Description '' `
            -Tags (($tags -join ' ') -replace '^\s+|\s+$', '') -Enabled:$enabled -Featured:$featured `
            -Source $entry
    }

    return (Sort-ClaudePluginMenuItems -Items $items -FeaturedOrderMap $featuredOrderMap `
        -InstalledMap $installedMap)
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

function Resolve-ClaudePluginInstallListLayout {
    param([hashtable]$Shell)

    if (-not (Get-Command Resolve-ShellListLayout -ErrorAction SilentlyContinue)) {
        $coreLib = Join-Path $PSScriptRoot '..\..\..\core\lib'
        . (Join-Path $coreLib 'ui\shell\ShellListLayout.ps1')
    }

    return Resolve-ShellListLayout -Shell $Shell -Layout (New-ClaudePluginListLayout) `
        -NumWidth 0 -Mode Multi -HideNumberColumn
}

function Get-ClaudePluginDisplayName {
    param([string]$PluginId)

    $split = Split-ClaudePluginId -PluginId ([string]$PluginId)
    if (-not [string]::IsNullOrWhiteSpace($split.Name)) {
        return [string]$split.Name
    }
    return [string]$PluginId
}

function Get-ClaudePluginMarketplaceName {
    param([string]$PluginId)

    $split = Split-ClaudePluginId -PluginId ([string]$PluginId)
    if (-not [string]::IsNullOrWhiteSpace($split.Marketplace)) {
        return [string]$split.Marketplace
    }
    return '-'
}

function New-ClaudePluginManageListLayout {
    param([hashtable]$Shell)

    $installLayout = Resolve-ClaudePluginInstallListLayout -Shell $Shell
    $marketWidth = [Math]::Max(12, [Math]::Min(18, [Math]::Floor([int]$installLayout.Widths[1] * 0.55)))
    return @{
        Widths           = @([int]$installLayout.Widths[0], $marketWidth, 8, 12)
        ScrollColumn     = 3
        ScrollIntervalMs = 300
    }
}

function New-ClaudePluginUpdateListLayout {
    param([hashtable]$Shell)

    return (New-ClaudePluginManageListLayout -Shell $Shell)
}

function New-ClaudePluginUninstallListLayout {
    param([hashtable]$Shell)

    $installLayout = Resolve-ClaudePluginInstallListLayout -Shell $Shell
    $marketWidth = [Math]::Max(12, [Math]::Min(18, [Math]::Floor([int]$installLayout.Widths[1] * 0.55)))
    $versionWidth = [Math]::Max(8, [int]$installLayout.Widths[1] - $marketWidth)
    return @{
        Widths           = @([int]$installLayout.Widths[0], $marketWidth, $versionWidth)
        ScrollColumn     = 0
        ScrollIntervalMs = 300
    }
}

function Format-ClaudePluginVersionCell {
    param([string]$Version)

    if ([string]::IsNullOrWhiteSpace($Version)) {
        return '-'
    }
    return [string]$Version
}

function Get-ClaudePluginInstalledStatusTags {
    param(
        $Item,
        [string]$ToolRoot,
        [string]$InstalledTagKey = 'claude-code.plugin.tagInstalled',
        [string]$UpdateTagKey = 'claude-code.plugin.tagUpdate'
    )

    if ($Item.PSObject.Properties['HasUpdate'] -and [bool]$Item.HasUpdate) {
        $target = [string]$Item.UpdateVersion
        if ([string]::IsNullOrWhiteSpace($target)) {
            if ([string]$Item.Tags -match 'update:([^\s]+)') {
                $target = $Matches[1]
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($target)) {
            return (Get-ClaudeCodeI18n -ToolRoot $ToolRoot -Key $UpdateTagKey -Vars @{
                version = $target
            })
        }
    }

    if (Test-ClaudePluginMenuItemInstalled -Item $Item) {
        $latest = [string]$Item.Version
        $installed = [string]$Item.InstalledVersion
        if (-not [string]::IsNullOrWhiteSpace($latest) -and -not [string]::IsNullOrWhiteSpace($installed) `
            -and (Compare-ClaudeSemVersion -Left $installed -Right $latest) -gt 0) {
            return ''
        }
        return (Get-ClaudeCodeI18n -ToolRoot $ToolRoot -Key $InstalledTagKey)
    }

    return ''
}

function Format-ClaudePluginInstalledStatusCell {
    param(
        $Item,
        [string]$ToolRoot
    )

    if (-not (Test-ClaudePluginMenuItemInstalled -Item $Item)) {
        return '-'
    }

    $versionText = Format-ClaudePluginVersionCell -Version ([string]$Item.InstalledVersion)
    $tags = Get-ClaudePluginInstalledStatusTags -Item $Item -ToolRoot $ToolRoot
    if ([string]::IsNullOrWhiteSpace($tags)) {
        return $versionText
    }
    return "$versionText $tags"
}

function Build-ClaudePluginManageRows {
    param(
        [array]$Items,
        [string]$ToolRoot
    )

    return @($Items | ForEach-Object {
        $item = $_
        $pluginId = [string]$item.PluginId
        $displayName = Get-ClaudePluginDisplayName -PluginId $pluginId
        $marketplaceName = Get-ClaudePluginMarketplaceName -PluginId $pluginId

        $cellColors = $null
        if ($item.PSObject.Properties['Featured'] -and [bool]$item.Featured) {
            $cellColors = @(
                (Get-ClaudeFeaturedPluginNameColor)
                [System.ConsoleColor]::DarkGray
                [System.ConsoleColor]::DarkGray
                [System.ConsoleColor]::DarkGray
            )
        }

        New-ShellListRow -Id $pluginId -Cells @(
            $displayName
            $marketplaceName
            (Format-ClaudePluginVersionCell -Version ([string]$item.Version))
            (Format-ClaudePluginInstalledStatusCell -Item $item -ToolRoot $ToolRoot)
        ) -Payload $item -SearchKey "$displayName $marketplaceName" -Enabled ([bool]$item.Enabled) `
            -CellColors $cellColors
    })
}

function Build-ClaudePluginUpdateRows {
    param(
        [array]$Items,
        [string]$ToolRoot = ''
    )

    if ([string]::IsNullOrWhiteSpace($ToolRoot)) {
        return (Build-ClaudePluginManageRows -Items $Items -ToolRoot '')
    }
    return (Build-ClaudePluginManageRows -Items $Items -ToolRoot $ToolRoot)
}

function Build-ClaudePluginUninstallRows {
    param([array]$Items)

    return @($Items | ForEach-Object {
        $item = $_
        $pluginId = [string]$item.PluginId
        $displayName = Get-ClaudePluginDisplayName -PluginId $pluginId
        $marketplaceName = Get-ClaudePluginMarketplaceName -PluginId $pluginId

        $cellColors = $null
        if ($item.PSObject.Properties['Featured'] -and [bool]$item.Featured) {
            $cellColors = @(
                (Get-ClaudeFeaturedPluginNameColor)
                [System.ConsoleColor]::DarkGray
                [System.ConsoleColor]::DarkGray
            )
        }

        New-ShellListRow -Id $pluginId -Cells @(
            $displayName
            $marketplaceName
            (Format-ClaudePluginVersionCell -Version ([string]$item.Version))
        ) -Payload $item -SearchKey "$displayName $marketplaceName" -Enabled ([bool]$item.Enabled) `
            -CellColors $cellColors
    })
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
