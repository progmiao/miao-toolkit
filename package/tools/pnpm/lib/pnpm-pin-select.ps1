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

    return ConvertTo-ShellListRows -Items $Items -KeepSource -GetSearchKey {
        param($Item, [int]$Index)
        [string]$Item.Version
    } -MapCells {
        param($Item, [int]$Index)
        @(
            [string]$Item.Version
            (Get-PnpmPinTagsLabel -Item $Item -InstalledMap $InstalledMap `
                -DefaultVersion $DefaultVersion -ActiveVersion $ActiveVersion `
                -PinnedVersion $PinnedVersion)
        )
    } -GetEnabled {
        param($Item, [int]$Index)
        $true
    }
}

function Format-PnpmPinContentLineMessage {
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
    $columnLayout = New-ShellListColumnLayout -Widths @($widths.Version, $widths.Tags)

    Clear-ShellSingleSelectListCache -Shell $Shell -CacheKey 'PnpmPin'
    $normalized = @(Normalize-ShellListRows -Rows $rows -ColumnLayout $columnLayout)
    $null = Get-ShellSingleSelectListRowCache -Shell $Shell -CacheKey 'PnpmPin' `
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

function Invoke-PnpmPinVersionSingleSelectPage {
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
        -Rows $Rows -CacheKey 'PnpmPin' `
        -ColumnLayout $ColumnLayout `
        -ToolbarConfig $toolbar `
        -CountLabel (Get-PnpmPinI18n -ToolRoot $ToolRoot -Key 'pnpm.pin.countUnit') `
        -InitialContentLine $InitialContentLine `
        -InitialFlashMessage $InitialFlashMessage
}

function Resolve-PnpmPinPickSourceItem {
    param($Picked)

    if ($null -eq $Picked) { return $null }
    if ($null -ne $Picked.Source) { return $Picked.Source }
    return $Picked
}
