# yarn — 已安装版本单选列表

function Import-YarnInstalledSelectCore {
    param([string]$CoreLib)

    if (-not (Get-Command Initialize-PathsFromToolRoot -ErrorAction SilentlyContinue)) {
        . (Join-Path $CoreLib 'config\Paths.ps1')
        . (Join-Path $CoreLib 'config\ListLayout.ps1')
        . (Join-Path $CoreLib 'config\UserConfig.ps1')
        . (Join-Path $CoreLib 'config\I18n.ps1')
    }

    . (Join-Path $CoreLib 'ui\console\Console-Menu.ps1')
    . (Join-Path $CoreLib 'ui\shell\Nav.ps1')
    . (Join-Path $CoreLib 'ui\shell\SystemToolbar.ps1')
    . (Join-Path $CoreLib 'ui\shell\SingleSelectList.ps1')
    . (Join-Path $CoreLib 'ui\shell\MultiSelectList.ps1')
    . (Join-Path $CoreLib 'ui\shell\Draw.ps1')
    . (Join-Path $CoreLib 'ui\shell\Layout.ps1')
    . (Join-Path $CoreLib 'ui\shell\Header.ps1')
    . (Join-Path $CoreLib 'ui\shell\Title.ps1')
    . (Join-Path $CoreLib 'ui\shell\CatalogRow.ps1')
    . (Join-Path $CoreLib 'ui\shell\Exit.ps1')
    . (Join-Path $CoreLib 'ui\shell\Footer.ps1')
}

function Initialize-YarnVoltaToolRoot {
    param([string]$ToolRoot)

    if (Get-Command Set-YarnVoltaToolRoot -ErrorAction SilentlyContinue) {
        Set-YarnVoltaToolRoot -ToolRoot $ToolRoot
    }
}

function Get-YarnInstalledSelectI18n {
    param(
        [string]$ToolRoot,
        [string]$Key,
        [hashtable]$Vars = @{}
    )

    return Get-ToolI18n -ToolRoot $ToolRoot -Key $Key -Vars $Vars
}

function Get-YarnInstalledVersionTagsLabel {
    param(
        $Item,
        [hashtable]$InstalledMap,
        [string]$DefaultVersion,
        [string]$ActiveVersion
    )

    return (Get-YarnVersionStatusTags -Item $Item -InstalledMap $InstalledMap `
        -DefaultVersion $DefaultVersion -ActiveVersion $ActiveVersion)
}

function Build-YarnInstalledVersionRows {
    param(
        [array]$Items,
        [hashtable]$InstalledMap,
        [string]$DefaultVersion,
        [string]$ActiveVersion
    )

    return ConvertTo-ShellListRows -Items $Items -KeepSource -GetSearchKey {
        param($Item, [int]$Index)
        [string]$Item.Version
    } -MapCells {
        param($Item, [int]$Index)
        @(
            [string]$Item.Version
            (Get-YarnInstalledVersionTagsLabel -Item $Item -InstalledMap $InstalledMap `
                -DefaultVersion $DefaultVersion -ActiveVersion $ActiveVersion)
        )
    } -GetEnabled {
        param($Item, [int]$Index)
        $true
    }
}

function Resolve-YarnInstalledVersionColumnWidths {
    param([hashtable]$Shell)

    $metrics = Get-ToolkitShellLayoutLineMetrics -Shell $Shell
    $versionWidth = Get-ShellMultiSelectSearchKeyWidth
    $gap = Get-MenuColumnGap
    $prefixReserve = 2 + 3 + 1 + $versionWidth + $gap
    $remaining = [int]$metrics.EndColumn - $prefixReserve
    $maxTags = 26
    $tagsWidth = [Math]::Max(10, [Math]::Min($maxTags, $remaining))

    return @{
        Version = $versionWidth
        Tags    = $tagsWidth
    }
}

function Show-YarnInstalledSelectMessagePage {
    param(
        [hashtable]$Shell,
        [string]$SectionTitle,
        [string]$Message,
        [System.ConsoleColor]$Color = [System.ConsoleColor]::Yellow,
        [int]$DelayMs = 900
    )

    Show-ToolkitShellNoticePage -Shell $Shell -SectionTitle $SectionTitle -Message $Message `
        -Color $Color -DelayMs $DelayMs
}

function Invoke-YarnInstalledSelectNoticePage {
    param(
        [hashtable]$Shell,
        [string]$SectionTitle,
        [string]$Message,
        [string]$CacheKey
    )

    Clear-ShellSingleSelectListCache -Shell $Shell -CacheKey $CacheKey
    $toolbar = New-ShellSystemToolbarConfig
    $invokeSingleSelect = Get-Command Invoke-ShellSingleSelectList -CommandType Function -ErrorAction Stop
    return & $invokeSingleSelect -Shell $Shell -SectionTitle $SectionTitle `
        -Rows @() -CacheKey $CacheKey `
        -ColumnLayout (New-ShellListColumnLayout -Preset ToolList) `
        -ToolbarConfig $toolbar `
        -InitialFlashMessage $Message
}

function Resolve-YarnInstalledVersionFromPick {
    param($Picked)

    if ($null -eq $Picked) { return $null }
    if ($null -ne $Picked.Source -and $Picked.Source.Version) {
        return Normalize-YarnVersionLabel -Version ([string]$Picked.Source.Version)
    }
    if ($null -ne $Picked.PSObject.Properties['Version'] -and $Picked.Version) {
        return Normalize-YarnVersionLabel -Version ([string]$Picked.Version)
    }
    if ($null -ne $Picked.PSObject.Properties['SearchKey'] -and $Picked.SearchKey) {
        return Normalize-YarnVersionLabel -Version ([string]$Picked.SearchKey)
    }
    return $null
}

function Invoke-YarnInstalledVersionSingleSelectPage {
    param(
        [hashtable]$Shell,
        [string]$ToolRoot,
        [string]$I18nPrefix,
        [string]$CacheKey,
        [string]$InitialFlashMessage = '',
        [string]$SectionTitle = ''
    )

    $null = Ensure-ToolkitShellLayoutBrandInnerWidth -Shell $Shell
    if ([string]::IsNullOrWhiteSpace($SectionTitle)) {
        $sectionTitle = Resolve-ToolI18nLabel -ToolRoot $ToolRoot -Key "$I18nPrefix.sectionTitle" `
            -Fallback $I18nPrefix
    }
    else {
        $sectionTitle = $SectionTitle
    }

    if (-not (Get-Command volta -ErrorAction SilentlyContinue)) {
        return Invoke-YarnInstalledSelectNoticePage -Shell $Shell -SectionTitle $sectionTitle `
            -Message (Get-YarnInstalledSelectI18n -ToolRoot $ToolRoot -Key "$I18nPrefix.voltaMissing") `
            -CacheKey "${CacheKey}Notice"
    }

    $voltaInfo = Get-VoltaYarnVersionInfo
    $activeVersion = Get-ActiveYarnVersion -TimeoutMs 2000
    $installed = @($voltaInfo.Map.Keys)

    if ($installed.Count -eq 0) {
        return Invoke-YarnInstalledSelectNoticePage -Shell $Shell -SectionTitle $sectionTitle `
            -Message (Get-YarnInstalledSelectI18n -ToolRoot $ToolRoot -Key "$I18nPrefix.noInstalled") `
            -CacheKey "${CacheKey}Notice"
    }

    $items = Sort-YarnVersionItems -Items @(
        $installed | ForEach-Object { New-YarnVersionMenuItem -Version $_ }
    )

    $widths = Resolve-YarnInstalledVersionColumnWidths -Shell $Shell
    $rows = Build-YarnInstalledVersionRows -Items $items -InstalledMap $voltaInfo.Map `
        -DefaultVersion $voltaInfo.Default -ActiveVersion $activeVersion

    Clear-ShellSingleSelectListCache -Shell $Shell -CacheKey $CacheKey

    $toolbar = New-ShellSystemToolbarConfig
    $invokeSingleSelect = Get-Command Invoke-ShellSingleSelectList -CommandType Function -ErrorAction Stop
    return & $invokeSingleSelect -Shell $Shell -SectionTitle $sectionTitle `
        -Rows $rows -CacheKey $CacheKey `
        -ColumnLayout (New-ShellListColumnLayout -Widths @($widths.Version, $widths.Tags)) `
        -ToolbarConfig $toolbar `
        -CountLabel (Get-YarnInstalledSelectI18n -ToolRoot $ToolRoot -Key "$I18nPrefix.countUnit") `
        -InitialFlashMessage $InitialFlashMessage
}
