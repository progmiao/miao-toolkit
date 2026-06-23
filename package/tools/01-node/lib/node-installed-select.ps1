# node — 已安装版本单选列表（Shell 标准：标题 + 列表 + 工具栏）

function Import-NodeInstalledSelectCore {
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
    . (Join-Path $CoreLib 'ui\shell\Exit.ps1')
    . (Join-Path $CoreLib 'ui\shell\Footer.ps1')
}

function Initialize-NodeVoltaToolRoot {
    param([string]$ToolRoot)

    if (Get-Command Set-NodeVoltaToolRoot -ErrorAction SilentlyContinue) {
        Set-NodeVoltaToolRoot -ToolRoot $ToolRoot
    }
}

function Get-NodeInstalledSelectI18n {
    param(
        [string]$ToolRoot,
        [string]$Key,
        [hashtable]$Vars = @{}
    )

    return Get-ToolI18n -ToolRoot $ToolRoot -Key $Key -Vars $Vars
}

function Get-NodeInstalledSelectSectionTitle {
    param(
        [string]$ToolRoot,
        [string]$SectionTitle = '',
        [string]$I18nPrefix = ''
    )

    if (-not [string]::IsNullOrWhiteSpace($SectionTitle)) {
        return $SectionTitle
    }

    return (Resolve-ToolI18nLabel -ToolRoot $ToolRoot -Key "$I18nPrefix.sectionTitle" `
        -Fallback $I18nPrefix)
}

function Get-NodeInstalledVersionTagsLabel {
    param(
        $Item,
        [hashtable]$InstalledMap,
        [string]$DefaultVersion,
        [string]$ActiveVersion
    )

    return (Get-NodeVersionStatusTags -Item $Item -InstalledMap $InstalledMap `
        -DefaultVersion $DefaultVersion -ActiveVersion $ActiveVersion)
}

function Build-NodeInstalledVersionRows {
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
            (Get-NodeInstalledVersionTagsLabel -Item $Item -InstalledMap $InstalledMap `
                -DefaultVersion $DefaultVersion -ActiveVersion $ActiveVersion)
        )
    } -GetEnabled {
        param($Item, [int]$Index)
        $true
    }
}

function Resolve-NodeInstalledVersionColumnWidths {
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

function Show-NodeInstalledSelectMessagePage {
    param(
        [hashtable]$Shell,
        [string]$SectionTitle,
        [string]$Message,
        [System.ConsoleColor]$Color = [System.ConsoleColor]::Yellow,
        [int]$DelayMs = 900
    )

    Initialize-ToolkitShellBodyView -Shell $Shell -SectionTitle $SectionTitle `
        -FooterTemplate SystemToolbarOnly
    $layout = $Shell.Layout
    Write-FixedLine $layout.ListStartRow $Message -Color $Color
    if ($DelayMs -gt 0) {
        Start-Sleep -Milliseconds $DelayMs
    }
}

function Resolve-NodeInstalledVersionFromPick {
    param($Picked)

    if ($null -eq $Picked) { return $null }
    if ($null -ne $Picked.Source -and $Picked.Source.Version) {
        return Normalize-NodeVersionLabel -Version ([string]$Picked.Source.Version)
    }
    if ($null -ne $Picked.PSObject.Properties['Version'] -and $Picked.Version) {
        return Normalize-NodeVersionLabel -Version ([string]$Picked.Version)
    }
    if ($null -ne $Picked.PSObject.Properties['SearchKey'] -and $Picked.SearchKey) {
        return Normalize-NodeVersionLabel -Version ([string]$Picked.SearchKey)
    }
    return $null
}

function Invoke-NodeInstalledVersionSingleSelectPage {
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
        $sectionTitle = Get-NodeInstalledSelectSectionTitle -ToolRoot $ToolRoot -I18nPrefix $I18nPrefix
    }
    else {
        $sectionTitle = $SectionTitle
    }

    if (-not (Get-Command volta -ErrorAction SilentlyContinue)) {
        Show-NodeInstalledSelectMessagePage -Shell $Shell -SectionTitle $sectionTitle `
            -Message (Get-NodeInstalledSelectI18n -ToolRoot $ToolRoot -Key "$I18nPrefix.voltaMissing") `
            -Color ([System.ConsoleColor]::Red) -DelayMs 1200
        return (Get-ShellNavMarker -Action 'back')
    }

    $voltaInfo = Get-VoltaNodeVersionInfo
    $activeVersion = Get-ActiveNodeVersion -TimeoutMs 2000
    $installed = @($voltaInfo.Map.Keys)

    if ($installed.Count -eq 0) {
        Show-NodeInstalledSelectMessagePage -Shell $Shell -SectionTitle $sectionTitle `
            -Message (Get-NodeInstalledSelectI18n -ToolRoot $ToolRoot -Key "$I18nPrefix.noInstalled") `
            -Color ([System.ConsoleColor]::Yellow)
        return (Get-ShellNavMarker -Action 'back')
    }

    $items = Sort-NodeVersionItems -Items @(
        $installed | ForEach-Object { New-NodeVersionMenuItem -Version $_ }
    )

    $widths = Resolve-NodeInstalledVersionColumnWidths -Shell $Shell
    $rows = Build-NodeInstalledVersionRows -Items $items -InstalledMap $voltaInfo.Map `
        -DefaultVersion $voltaInfo.Default -ActiveVersion $activeVersion

    Clear-ShellSingleSelectListCache -Shell $Shell -CacheKey $CacheKey

    $toolbar = New-ShellSystemToolbarConfig
    $invokeSingleSelect = Get-Command Invoke-ShellSingleSelectList -CommandType Function -ErrorAction Stop
    return & $invokeSingleSelect -Shell $Shell -SectionTitle $sectionTitle `
        -Rows $rows -CacheKey $CacheKey `
        -ColumnLayout (New-ShellListColumnLayout -Widths @($widths.Version, $widths.Tags)) `
        -ToolbarConfig $toolbar `
        -CountLabel (Get-NodeInstalledSelectI18n -ToolRoot $ToolRoot -Key "$I18nPrefix.countUnit") `
        -InitialFlashMessage $InitialFlashMessage
}
