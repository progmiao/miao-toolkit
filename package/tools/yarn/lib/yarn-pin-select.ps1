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

    return ConvertTo-ShellListRows -Items $Items -KeepSource -GetSearchKey {
        param($Item, [int]$Index)
        [string]$Item.Version
    } -MapCells {
        param($Item, [int]$Index)
        @(
            [string]$Item.Version
            (Get-YarnPinTagsLabel -Item $Item -InstalledMap $InstalledMap `
                -DefaultVersion $DefaultVersion -ActiveVersion $ActiveVersion `
                -PinnedVersion $PinnedVersion)
        )
    } -GetEnabled {
        param($Item, [int]$Index)
        $true
    }
}

function Format-YarnPinContentLineMessage {
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
    $columnLayout = New-ShellListColumnLayout -Widths @($widths.Version, $widths.Tags)

    Clear-ShellSingleSelectListCache -Shell $Shell -CacheKey 'YarnPin'
    $normalized = @(Normalize-ShellListRows -Rows $rows -ColumnLayout $columnLayout)
    $null = Get-ShellSingleSelectListRowCache -Shell $Shell -CacheKey 'YarnPin' `
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

function Invoke-YarnPinVersionSingleSelectPage {
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
        -Rows $Rows -CacheKey 'YarnPin' `
        -ColumnLayout $ColumnLayout `
        -ToolbarConfig $toolbar `
        -CountLabel (Get-YarnPinI18n -ToolRoot $ToolRoot -Key 'yarn.pin.countUnit') `
        -InitialContentLine $InitialContentLine `
        -InitialFlashMessage $InitialFlashMessage
}

function Resolve-YarnPinPickSourceItem {
    param($Picked)

    if ($null -eq $Picked) { return $null }
    if ($null -ne $Picked.Source) { return $Picked.Source }
    return $Picked
}
