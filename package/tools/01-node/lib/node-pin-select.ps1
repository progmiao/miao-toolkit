# node — 指定项目 Node 版本（全量列表 + 标准单选）

function Get-NodePinI18n {
    param(
        [string]$ToolRoot,
        [string]$Key,
        [hashtable]$Vars = @{}
    )

    return Get-ToolI18n -ToolRoot $ToolRoot -Key $Key -Vars $Vars
}

function Get-NodePinTagsLabel {
    param(
        $Item,
        [hashtable]$InstalledMap,
        [string]$DefaultVersion,
        [string]$ActiveVersion,
        [string]$PinnedVersion
    )

    return (Get-NodeVersionStatusTags -Item $Item -InstalledMap $InstalledMap `
        -DefaultVersion $DefaultVersion -ActiveVersion $ActiveVersion `
        -PinnedVersion $PinnedVersion -IncludeInstalledTag)
}

function Build-NodePinMergedItems {
    param(
        [array]$BaseVersions,
        [hashtable]$VoltaInfo,
        [string]$PinnedVersion
    )

    $merged = @(Build-NodeBrowseInstallMergedItems -BaseVersions $BaseVersions -VoltaInfo $VoltaInfo)
    $pinned = Normalize-NodeVersionLabel -Version $PinnedVersion
    if ([string]::IsNullOrWhiteSpace($pinned)) {
        return $merged
    }

    if ($VoltaInfo -and $VoltaInfo.Map -and $VoltaInfo.Map.ContainsKey($pinned)) {
        return $merged
    }

    $seen = @{}
    foreach ($item in $merged) {
        $ver = Normalize-NodeVersionLabel -Version ([string]$item.Version)
        if ($ver) { $seen[$ver] = $true }
    }
    if ($seen[$pinned]) {
        return $merged
    }

    return @($merged + @((New-NodeVersionMenuItem -Version $pinned)))
}

function Build-NodePinRows {
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
            (Get-NodePinTagsLabel -Item $item -InstalledMap $InstalledMap `
                -DefaultVersion $DefaultVersion -ActiveVersion $ActiveVersion `
                -PinnedVersion $PinnedVersion)
        ) -Payload $item -SearchKey ([string]$item.Version) -Enabled $true
    })
}

function Format-NodePinCatalogLineMessage {
    param(
        [string]$ToolRoot,
        [hashtable]$PinContext,
        [hashtable]$VoltaInfo
    )

    if (-not $PinContext.HasProject) {
        return ''
    }

    $pinned = Normalize-NodeVersionLabel -Version ([string]$PinContext.PinnedVersion)
    $projectLabel = [string]$PinContext.ProjectName
    $pathLabel = [string]$PinContext.PackageJsonRel
    $isSubProject = ($pathLabel -and $pathLabel -ne 'package.json')

    if ($pinned) {
        if ($isSubProject) {
            return (Get-NodePinI18n -ToolRoot $ToolRoot -Key 'node.pin.contextSubProjectPinned' `
                -Vars @{ path = $pathLabel; version = $pinned })
        }
        return (Get-NodePinI18n -ToolRoot $ToolRoot -Key 'node.pin.contextProjectPinned' `
            -Vars @{ project = $projectLabel; version = $pinned })
    }

    if ($isSubProject) {
        return (Get-NodePinI18n -ToolRoot $ToolRoot -Key 'node.pin.contextSubProjectUnpinned' `
            -Vars @{ path = $pathLabel })
    }
    return (Get-NodePinI18n -ToolRoot $ToolRoot -Key 'node.pin.contextProjectUnpinned' `
        -Vars @{ project = $projectLabel })
}

function Format-NodePinMessageLineMessage {
    param(
        [string]$ToolRoot,
        [hashtable]$PinContext,
        [hashtable]$VoltaInfo,
        [string]$SelectedVersion = ''
    )

    $pinned = Normalize-NodeVersionLabel -Version ([string]$PinContext.PinnedVersion)
    $selected = Normalize-NodeVersionLabel -Version $SelectedVersion
    $installedMap = if ($VoltaInfo -and $VoltaInfo.Map) { $VoltaInfo.Map } else { @{} }

    if ($selected -and -not (Test-NodeVersionInstalled -Version $selected -InstalledMap $installedMap)) {
        if ($pinned -and $selected -eq $pinned) {
            return (Get-NodePinI18n -ToolRoot $ToolRoot -Key 'node.pin.contextPinnedNotInstalled' `
                -Vars @{ version = $selected })
        }
        return (Get-NodePinI18n -ToolRoot $ToolRoot -Key 'node.pin.contextSelectedNotInstalled' `
            -Vars @{ version = $selected })
    }

    if (-not $PinContext.HasProject) {
        return (Get-NodePinI18n -ToolRoot $ToolRoot -Key 'node.pin.contextNoProject')
    }

    return ''
}

function Format-NodePinGapContextMessage {
    param(
        [string]$ToolRoot,
        [hashtable]$PinContext,
        [hashtable]$VoltaInfo,
        [string]$SelectedVersion = ''
    )

    return Format-NodePinCatalogLineMessage -ToolRoot $ToolRoot -PinContext $PinContext `
        -VoltaInfo $VoltaInfo
}

function Prepare-NodePinListContent {
    param(
        [hashtable]$Shell,
        [hashtable]$Progress,
        [array]$Remote,
        [string]$PinnedVersion
    )

    Update-NodeBrowseInstallLoadingProgress -Shell $Shell -Progress $Progress -TargetPercent 60
    $baseVersions = Build-NodeBrowseInstallBaseVersions -Remote $Remote

    Update-NodeBrowseInstallLoadingProgress -Shell $Shell -Progress $Progress -TargetPercent 70
    $voltaInfo = Get-VoltaNodeVersionInfo
    $activeVersion = Get-ActiveNodeVersion

    Update-NodeBrowseInstallLoadingProgress -Shell $Shell -Progress $Progress -TargetPercent 85
    $merged = Build-NodePinMergedItems -BaseVersions $baseVersions -VoltaInfo $voltaInfo `
        -PinnedVersion $PinnedVersion
    $sorted = Sort-NodeVersionItems -Items $merged

    Update-NodeBrowseInstallLoadingProgress -Shell $Shell -Progress $Progress -TargetPercent 95
    $widths = Resolve-NodeInstalledVersionColumnWidths -Shell $Shell
    $rows = Build-NodePinRows -Items $sorted -InstalledMap $voltaInfo.Map `
        -DefaultVersion $voltaInfo.Default -ActiveVersion $activeVersion `
        -PinnedVersion $PinnedVersion
    $listLayout = New-ShellListLayout -Widths @($widths.Version, $widths.Tags)

    Clear-ShellListCache -Shell $Shell -CacheKey 'NodePin'
    $normalized = @(Normalize-ShellListRows -Rows $rows -Layout $listLayout)
    $columnLayout = Resolve-ShellListLayoutColumnLayout -Layout $listLayout
    $null = Get-ShellSingleSelectListRowCache -Shell $Shell -CacheKey 'NodePin' `
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

function Invoke-NodePinVersionSingleSelectPage {
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
        CacheKey             = 'NodePin'
        Layout               = $ListLayout
        Toolbar              = (New-ShellSystemToolbarConfig)
        CountLabel           = (Get-NodePinI18n -ToolRoot $ToolRoot -Key 'node.pin.countUnit')
        InitialCatalogLine   = $InitialCatalogLine
        InitialFlashMessage  = $InitialFlashMessage
    }
}

function Resolve-NodePinPickSourceItem {
    param($Picked)

    if ($null -eq $Picked) { return $null }
    if ($null -ne $Picked.Payload) { return $Picked.Payload }
    if ($null -ne $Picked.Source) { return $Picked.Source }
    return $Picked
}
