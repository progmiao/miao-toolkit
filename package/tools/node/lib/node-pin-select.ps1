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

    return ConvertTo-ShellListRows -Items $Items -KeepSource -GetSearchKey {
        param($Item, [int]$Index)
        [string]$Item.Version
    } -MapCells {
        param($Item, [int]$Index)
        @(
            [string]$Item.Version
            (Get-NodePinTagsLabel -Item $Item -InstalledMap $InstalledMap `
                -DefaultVersion $DefaultVersion -ActiveVersion $ActiveVersion `
                -PinnedVersion $PinnedVersion)
        )
    } -GetEnabled {
        param($Item, [int]$Index)
        $true
    }
}

function Format-NodePinContentLineMessage {
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

function Format-NodePinGapContextMessage {
    param(
        [string]$ToolRoot,
        [hashtable]$PinContext,
        [hashtable]$VoltaInfo,
        [string]$SelectedVersion = ''
    )

    return Format-NodePinContentLineMessage -ToolRoot $ToolRoot -PinContext $PinContext `
        -VoltaInfo $VoltaInfo -SelectedVersion $SelectedVersion
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
    $columnLayout = New-ShellListColumnLayout -Widths @($widths.Version, $widths.Tags)

    Clear-ShellSingleSelectListCache -Shell $Shell -CacheKey 'NodePin'
    $normalized = @(Normalize-ShellListRows -Rows $rows -ColumnLayout $columnLayout)
    $null = Get-ShellSingleSelectListRowCache -Shell $Shell -CacheKey 'NodePin' `
        -Rows $normalized -ColumnLayout $columnLayout

    return @{
        BaseVersions  = $baseVersions
        Rows          = $rows
        VoltaInfo     = $voltaInfo
        ActiveVersion = $activeVersion
        Sorted        = $sorted
        ColumnLayout  = $columnLayout
    }
}

function Invoke-NodePinVersionSingleSelectPage {
    param(
        [hashtable]$Shell,
        [string]$ToolRoot,
        [array]$Rows,
        [hashtable]$ColumnLayout,
        [string]$InitialContentLine = '',
        [string]$InitialFlashMessage = '',
        [Parameter(Mandatory)]
        [string]$SectionTitle
    )

    $toolbar = New-ShellSystemToolbarConfig
    $invokeSingleSelect = Get-Command Invoke-ShellSingleSelectList -CommandType Function -ErrorAction Stop
    return & $invokeSingleSelect -Shell $Shell -SectionTitle $sectionTitle `
        -Rows $Rows -CacheKey 'NodePin' `
        -ColumnLayout $ColumnLayout `
        -ToolbarConfig $toolbar `
        -CountLabel (Get-NodePinI18n -ToolRoot $ToolRoot -Key 'node.pin.countUnit') `
        -InitialContentLine $InitialContentLine `
        -InitialFlashMessage $InitialFlashMessage
}

function Resolve-NodePinPickSourceItem {
    param($Picked)

    if ($null -eq $Picked) { return $null }
    if ($null -ne $Picked.Source) { return $Picked.Source }
    return $Picked
}
