# yarn — 指定项目 Yarn 版本（全量列表 + 标准单选）

function Get-YarnPinI18n {
    param(
        [string]$ToolRoot,
        [string]$Key,
        [hashtable]$Vars = @{}
    )

    return Get-ToolI18n -ToolRoot $ToolRoot -Key $Key -Vars $Vars
}

function Get-YarnPinTagsLabel {
    param(
        $Item,
        [hashtable]$InstalledMap,
        [string]$DefaultVersion,
        [string]$ActiveVersion,
        [string]$PinnedVersion
    )

    return (Get-YarnVersionStatusTags -Item $Item -InstalledMap $InstalledMap `
        -DefaultVersion $DefaultVersion -ActiveVersion $ActiveVersion `
        -PinnedVersion $PinnedVersion -IncludeInstalledTag)
}

function Build-YarnPinMergedItems {
    param(
        [array]$BaseVersions,
        [hashtable]$VoltaInfo,
        [string]$PinnedVersion
    )

    $merged = @(Build-YarnBrowseInstallMergedItems -BaseVersions $BaseVersions -VoltaInfo $VoltaInfo)
    $pinned = Normalize-YarnVersionLabel -Version $PinnedVersion
    if ([string]::IsNullOrWhiteSpace($pinned)) {
        return $merged
    }

    if ($VoltaInfo -and $VoltaInfo.Map -and $VoltaInfo.Map.ContainsKey($pinned)) {
        return $merged
    }

    $seen = @{}
    foreach ($item in $merged) {
        $ver = Normalize-YarnVersionLabel -Version ([string]$item.Version)
        if ($ver) { $seen[$ver] = $true }
    }
    if ($seen[$pinned]) {
        return $merged
    }

    return @($merged + @((New-YarnVersionMenuItem -Version $pinned)))
}

function Build-YarnPinRows {
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
            (Get-YarnPinTagsLabel -Item $item -InstalledMap $InstalledMap `
                -DefaultVersion $DefaultVersion -ActiveVersion $ActiveVersion `
                -PinnedVersion $PinnedVersion)
        ) -Payload $item -SearchKey ([string]$item.Version) -Enabled $true
    })
}

function Format-YarnPinCatalogLineMessage {
    param(
        [string]$ToolRoot,
        [hashtable]$PinContext,
        [hashtable]$VoltaInfo
    )

    if (-not $PinContext.HasProject) {
        return ''
    }

    $pinned = Normalize-YarnVersionLabel -Version ([string]$PinContext.PinnedVersion)
    $projectLabel = [string]$PinContext.ProjectName
    $pathLabel = [string]$PinContext.PackageJsonRel
    $isSubProject = ($pathLabel -and $pathLabel -ne 'package.json')

    if ($pinned) {
        if ($isSubProject) {
            return (Get-YarnPinI18n -ToolRoot $ToolRoot -Key 'yarn.pin.contextSubProjectPinned' `
                -Vars @{ path = $pathLabel; version = $pinned })
        }
        return (Get-YarnPinI18n -ToolRoot $ToolRoot -Key 'yarn.pin.contextProjectPinned' `
            -Vars @{ project = $projectLabel; version = $pinned })
    }

    if ($isSubProject) {
        return (Get-YarnPinI18n -ToolRoot $ToolRoot -Key 'yarn.pin.contextSubProjectUnpinned' `
            -Vars @{ path = $pathLabel })
    }
    return (Get-YarnPinI18n -ToolRoot $ToolRoot -Key 'yarn.pin.contextProjectUnpinned' `
        -Vars @{ project = $projectLabel })
}

function Format-YarnPinMessageLineMessage {
    param(
        [string]$ToolRoot,
        [hashtable]$PinContext,
        [hashtable]$VoltaInfo,
        [string]$SelectedVersion = ''
    )

    $pinned = Normalize-YarnVersionLabel -Version ([string]$PinContext.PinnedVersion)
    $selected = Normalize-YarnVersionLabel -Version $SelectedVersion
    $installedMap = if ($VoltaInfo -and $VoltaInfo.Map) { $VoltaInfo.Map } else { @{} }

    if ($selected -and -not (Test-YarnVersionInstalled -Version $selected -InstalledMap $installedMap)) {
        if ($pinned -and $selected -eq $pinned) {
            return (Get-YarnPinI18n -ToolRoot $ToolRoot -Key 'yarn.pin.contextPinnedNotInstalled' `
                -Vars @{ version = $selected })
        }
        return (Get-YarnPinI18n -ToolRoot $ToolRoot -Key 'yarn.pin.contextSelectedNotInstalled' `
            -Vars @{ version = $selected })
    }

    if (-not $PinContext.HasProject) {
        return (Get-YarnPinI18n -ToolRoot $ToolRoot -Key 'yarn.pin.contextNoProject')
    }

    return ''
}

function Prepare-YarnPinListContent {
    param(
        [hashtable]$Shell,
        [hashtable]$Progress,
        [array]$Remote,
        [string]$PinnedVersion
    )

    Update-YarnBrowseInstallLoadingProgress -Shell $Shell -Progress $Progress -TargetPercent 60
    $baseVersions = Build-YarnBrowseInstallBaseVersions -Remote $Remote

    Update-YarnBrowseInstallLoadingProgress -Shell $Shell -Progress $Progress -TargetPercent 70
    $voltaInfo = Get-VoltaYarnVersionInfo
    $activeVersion = Get-ActiveYarnVersion

    Update-YarnBrowseInstallLoadingProgress -Shell $Shell -Progress $Progress -TargetPercent 85
    $merged = Build-YarnPinMergedItems -BaseVersions $baseVersions -VoltaInfo $voltaInfo `
        -PinnedVersion $PinnedVersion
    $sorted = Sort-YarnVersionItems -Items $merged

    Update-YarnBrowseInstallLoadingProgress -Shell $Shell -Progress $Progress -TargetPercent 95
    $widths = Resolve-YarnInstalledVersionColumnWidths -Shell $Shell
    $rows = Build-YarnPinRows -Items $sorted -InstalledMap $voltaInfo.Map `
        -DefaultVersion $voltaInfo.Default -ActiveVersion $activeVersion `
        -PinnedVersion $PinnedVersion
    $listLayout = New-ShellListLayout -Widths @($widths.Version, $widths.Tags)

    Clear-ShellListCache -Shell $Shell -CacheKey 'YarnPin'
    $normalized = @(Normalize-ShellListRows -Rows $rows -Layout $listLayout)
    $columnLayout = Resolve-ShellListLayoutColumnLayout -Layout $listLayout
    $null = Get-ShellSingleSelectListRowCache -Shell $Shell -CacheKey 'YarnPin' `
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

function Invoke-YarnPinVersionSingleSelectPage {
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
        CacheKey             = 'YarnPin'
        Layout               = $ListLayout
        Toolbar              = (New-ShellSystemToolbarConfig)
        CountLabel           = (Get-YarnPinI18n -ToolRoot $ToolRoot -Key 'yarn.pin.countUnit')
        InitialCatalogLine   = $InitialCatalogLine
        InitialFlashMessage  = $InitialFlashMessage
    }
}

function Resolve-YarnPinPickSourceItem {
    param($Picked)

    if ($null -eq $Picked) { return $null }
    if ($null -ne $Picked.Payload) { return $Picked.Payload }
    if ($null -ne $Picked.Source) { return $Picked.Source }
    return $Picked
}
