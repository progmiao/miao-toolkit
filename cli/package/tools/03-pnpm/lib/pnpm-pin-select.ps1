# pnpm — 指定项目 pnpm 版本（全量列表 + 标准单选）

function Get-PnpmPinI18n {
    param(
        [string]$ToolRoot,
        [string]$Key,
        [hashtable]$Vars = @{}
    )

    return Get-ToolI18n -ToolRoot $ToolRoot -Key $Key -Vars $Vars
}

function Get-PnpmPinTagsLabel {
    param(
        $Item,
        [hashtable]$InstalledMap,
        [string]$DefaultVersion,
        [string]$ActiveVersion,
        [string]$PinnedVersion
    )

    return (Get-PnpmVersionStatusTags -Item $Item -InstalledMap $InstalledMap `
        -DefaultVersion $DefaultVersion -ActiveVersion $ActiveVersion `
        -PinnedVersion $PinnedVersion -IncludeInstalledTag)
}

function Build-PnpmPinMergedItems {
    param(
        [array]$BaseVersions,
        [hashtable]$VoltaInfo,
        [string]$PinnedVersion
    )

    $merged = @(Build-PnpmBrowseInstallMergedItems -BaseVersions $BaseVersions -VoltaInfo $VoltaInfo)
    $pinned = Normalize-PnpmVersionLabel -Version $PinnedVersion
    if ([string]::IsNullOrWhiteSpace($pinned)) {
        return $merged
    }

    if ($VoltaInfo -and $VoltaInfo.Map -and $VoltaInfo.Map.ContainsKey($pinned)) {
        return $merged
    }

    $seen = @{}
    foreach ($item in $merged) {
        $ver = Normalize-PnpmVersionLabel -Version ([string]$item.Version)
        if ($ver) { $seen[$ver] = $true }
    }
    if ($seen[$pinned]) {
        return $merged
    }

    return @($merged + @((New-PnpmVersionMenuItem -Version $pinned)))
}

function Build-PnpmPinRows {
    param(
        [array]$Items,
        [hashtable]$InstalledMap,
        [string]$DefaultVersion,
        [string]$ActiveVersion,
        [string]$PinnedVersion
    )

    return @($Items | ForEach-Object {
        $item = $_
        New-ShellListRow -Id ([string]$item.Version) -Cells @(
            [string]$item.Version
            (Get-PnpmPinTagsLabel -Item $item -InstalledMap $InstalledMap `
                -DefaultVersion $DefaultVersion -ActiveVersion $ActiveVersion `
                -PinnedVersion $PinnedVersion)
        ) -Payload $item -SearchKey ([string]$item.Version) -Enabled $true
    })
}

function Format-PnpmPinCatalogLineMessage {
    param(
        [string]$ToolRoot,
        [hashtable]$PinContext,
        [hashtable]$VoltaInfo
    )

    if (-not $PinContext.HasProject) {
        return ''
    }

    $pinned = Normalize-PnpmVersionLabel -Version ([string]$PinContext.PinnedVersion)
    $projectLabel = [string]$PinContext.ProjectName
    $pathLabel = [string]$PinContext.PackageJsonRel
    $isSubProject = ($pathLabel -and $pathLabel -ne 'package.json')

    if ($pinned) {
        if ($isSubProject) {
            return (Get-PnpmPinI18n -ToolRoot $ToolRoot -Key 'pnpm.pin.contextSubProjectPinned' `
                -Vars @{ path = $pathLabel; version = $pinned })
        }
        return (Get-PnpmPinI18n -ToolRoot $ToolRoot -Key 'pnpm.pin.contextProjectPinned' `
            -Vars @{ project = $projectLabel; version = $pinned })
    }

    if ($isSubProject) {
        return (Get-PnpmPinI18n -ToolRoot $ToolRoot -Key 'pnpm.pin.contextSubProjectUnpinned' `
            -Vars @{ path = $pathLabel })
    }
    return (Get-PnpmPinI18n -ToolRoot $ToolRoot -Key 'pnpm.pin.contextProjectUnpinned' `
        -Vars @{ project = $projectLabel })
}

function Format-PnpmPinMessageLineMessage {
    param(
        [string]$ToolRoot,
        [hashtable]$PinContext,
        [hashtable]$VoltaInfo,
        [string]$SelectedVersion = ''
    )

    $pinned = Normalize-PnpmVersionLabel -Version ([string]$PinContext.PinnedVersion)
    $selected = Normalize-PnpmVersionLabel -Version $SelectedVersion
    $installedMap = if ($VoltaInfo -and $VoltaInfo.Map) { $VoltaInfo.Map } else { @{} }

    if ($selected -and -not (Test-PnpmVersionInstalled -Version $selected -InstalledMap $installedMap)) {
        if ($pinned -and $selected -eq $pinned) {
            return (Get-PnpmPinI18n -ToolRoot $ToolRoot -Key 'pnpm.pin.contextPinnedNotInstalled' `
                -Vars @{ version = $selected })
        }
        return (Get-PnpmPinI18n -ToolRoot $ToolRoot -Key 'pnpm.pin.contextSelectedNotInstalled' `
            -Vars @{ version = $selected })
    }

    if (-not $PinContext.HasProject) {
        return (Get-PnpmPinI18n -ToolRoot $ToolRoot -Key 'pnpm.pin.contextNoProject')
    }

    return ''
}

function Prepare-PnpmPinListContent {
    param(
        [hashtable]$Shell,
        [hashtable]$Progress,
        [array]$Remote,
        [string]$PinnedVersion
    )

    Update-PnpmBrowseInstallLoadingProgress -Shell $Shell -Progress $Progress -TargetPercent 60
    $baseVersions = Build-PnpmBrowseInstallBaseVersions -Remote $Remote

    Update-PnpmBrowseInstallLoadingProgress -Shell $Shell -Progress $Progress -TargetPercent 70
    $voltaInfo = Get-VoltaPnpmVersionInfo
    $activeVersion = Get-ActivePnpmVersion

    Update-PnpmBrowseInstallLoadingProgress -Shell $Shell -Progress $Progress -TargetPercent 85
    $merged = Build-PnpmPinMergedItems -BaseVersions $baseVersions -VoltaInfo $voltaInfo `
        -PinnedVersion $PinnedVersion
    $sorted = Sort-PnpmVersionItems -Items $merged

    Update-PnpmBrowseInstallLoadingProgress -Shell $Shell -Progress $Progress -TargetPercent 95
    $widths = Resolve-PnpmInstalledVersionColumnWidths -Shell $Shell
    $rows = Build-PnpmPinRows -Items $sorted -InstalledMap $voltaInfo.Map `
        -DefaultVersion $voltaInfo.Default -ActiveVersion $activeVersion `
        -PinnedVersion $PinnedVersion
    $listLayout = New-ShellListLayout -Widths @($widths.Version, $widths.Tags)

    Clear-ShellListCache -Shell $Shell -CacheKey 'PnpmPin'
    $normalized = @(Normalize-ShellListRows -Rows $rows -Layout $listLayout)
    $columnLayout = Resolve-ShellListLayoutColumnLayout -Layout $listLayout
    $null = Get-ShellSingleSelectListRowCache -Shell $Shell -CacheKey 'PnpmPin' `
        -Rows $normalized -ColumnLayout $columnLayout

    return @{
        BaseVersions  = $baseVersions
        Rows          = $rows
        VoltaInfo     = $voltaInfo
        ActiveVersion = $activeVersion
        Sorted        = $sorted
        ListLayout    = $listLayout
    }
}

function Invoke-PnpmPinVersionSingleSelectPage {
    param(
        [hashtable]$Shell,
        [string]$ToolRoot,
        [array]$Rows,
        [hashtable]$ListLayout,
        [string]$InitialCatalogLine = '',
        [string]$InitialFlashMessage = '',
        [Parameter(Mandatory)]
        [string]$SectionTitle
    )

    return Invoke-ToolkitShellList @{
        Mode                 = 'Single'
        Shell                = $Shell
        SectionTitle         = $SectionTitle
        Rows                 = $Rows
        CacheKey             = 'PnpmPin'
        Layout               = $ListLayout
        Toolbar              = (New-ShellSystemToolbarConfig)
        CountLabel           = (Get-PnpmPinI18n -ToolRoot $ToolRoot -Key 'pnpm.pin.countUnit')
        InitialCatalogLine   = $InitialCatalogLine
        InitialFlashMessage  = $InitialFlashMessage
    }
}

function Resolve-PnpmPinPickSourceItem {
    param($Picked)

    if ($null -eq $Picked) { return $null }
    if ($null -ne $Picked.Payload) { return $Picked.Payload }
    if ($null -ne $Picked.Source) { return $Picked.Source }
    return $Picked
}
