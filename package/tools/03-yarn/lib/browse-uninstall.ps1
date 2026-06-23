# yarn — 浏览并卸载（Shell 多选已安装版本列表）

param(
    [hashtable]$ToolkitShell = $null,
    $Action = $null,

    [int]$PageSize = 0,
    [int]$ViewHeight = 0
)

$ErrorActionPreference = 'Stop'

$toolRoot = Split-Path $PSScriptRoot -Parent
$coreLib = Join-Path $toolRoot '..\..\core\lib'

function Import-YarnBrowseUninstallCore {
    if (-not (Get-Command Initialize-PathsFromToolRoot -ErrorAction SilentlyContinue)) {
        . (Join-Path $coreLib 'config\Paths.ps1')
        . (Join-Path $coreLib 'config\ListLayout.ps1')
        . (Join-Path $coreLib 'config\UserConfig.ps1')
        . (Join-Path $coreLib 'config\I18n.ps1')
    }

    . (Join-Path $coreLib 'ui\console\Console-Menu.ps1')
    . (Join-Path $coreLib 'ui\shell\Nav.ps1')
    . (Join-Path $coreLib 'ui\shell\SystemToolbar.ps1')
    . (Join-Path $coreLib 'ui\shell\SingleSelectList.ps1')
    . (Join-Path $coreLib 'ui\shell\MultiSelectList.ps1')
    . (Join-Path $coreLib 'ui\shell\Draw.ps1')
    . (Join-Path $coreLib 'ui\shell\Layout.ps1')
    . (Join-Path $coreLib 'ui\shell\Header.ps1')
    . (Join-Path $coreLib 'ui\shell\Title.ps1')
    . (Join-Path $coreLib 'ui\shell\CatalogRow.ps1')
    . (Join-Path $coreLib 'ui\shell\Exit.ps1')
    . (Join-Path $coreLib 'ui\shell\Footer.ps1')

    if (-not (Get-Command Draw-ToolkitDepOperationView -ErrorAction SilentlyContinue)) {
        . (Join-Path $coreLib 'ui\shell\DepOperationView.ps1')
    }
}

Import-YarnBrowseUninstallCore
. (Join-Path $PSScriptRoot 'yarn-action-title.ps1')
Import-YarnActionTitleCore -CoreLib $coreLib
. (Join-Path $PSScriptRoot 'volta-yarn.ps1')
Set-YarnVoltaToolRoot -ToolRoot $toolRoot
. (Join-Path $PSScriptRoot 'browse-install-run.ps1')
Initialize-PathsFromToolRoot -ToolRoot $toolRoot

$paging = Resolve-MenuPagingDefaults -PageSize $PageSize -ViewHeight $ViewHeight
$PageSize = $paging.PageSize
$ViewHeight = $paging.ViewHeight

$standaloneShell = $false
if (-not $ToolkitShell) {
    $ToolkitShell = Initialize-ToolkitShell
    $standaloneShell = $true
}

Sync-MiaoLocaleFromShell -Shell $ToolkitShell

$yarnToolAction = Resolve-YarnToolAction -ToolRoot $toolRoot -Action $Action -ScriptLeaf 'browse-uninstall.ps1'
$yarnActionSectionTitle = Get-YarnActionSectionTitle -ToolRoot $toolRoot -Action $yarnToolAction `
    -ScriptLeaf 'browse-uninstall.ps1'
$script:YarnActionSectionTitle = $yarnActionSectionTitle

function Get-YarnBrowseUninstallI18n {
    param(
        [string]$Key,
        [hashtable]$Vars = @{}
    )

    return Get-ToolI18n -ToolRoot $toolRoot -Key $Key -Vars $Vars
}

function Get-YarnBrowseUninstallTagsLabel {
    param(
        $Item,
        [hashtable]$InstalledMap,
        [string]$DefaultVersion,
        [string]$ActiveVersion
    )

    return (Get-YarnVersionStatusTags -Item $Item -InstalledMap $InstalledMap `
        -DefaultVersion $DefaultVersion -ActiveVersion $ActiveVersion)
}

function Build-YarnBrowseUninstallRows {
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
            (Get-YarnBrowseUninstallTagsLabel -Item $Item -InstalledMap $InstalledMap `
                -DefaultVersion $DefaultVersion -ActiveVersion $ActiveVersion)
        )
    } -GetEnabled {
        param($Item, [int]$Index)
        $true
    }
}

function Resolve-YarnBrowseUninstallTagsColumnWidth {
    param([hashtable]$Shell)

    $metrics = Get-ToolkitShellLayoutLineMetrics -Shell $Shell
    $versionKeyWidth = Get-ShellMultiSelectSearchKeyWidth
    $gap = Get-MenuColumnGap
    $prefixReserve = 2 + 3 + 1 + $versionKeyWidth + $gap
    $remaining = [int]$metrics.EndColumn - $prefixReserve
    $maxTags = 26
    return [Math]::Max(10, [Math]::Min($maxTags, $remaining))
}

function Invoke-YarnBrowseUninstallPage {
    param([hashtable]$Shell)

    $null = Ensure-ToolkitShellLayoutBrandInnerWidth -Shell $Shell
    $sectionTitle = $yarnActionSectionTitle

    if (-not (Get-Command volta -ErrorAction SilentlyContinue)) {
        Initialize-ToolkitShellBodyView -Shell $Shell -SectionTitle $sectionTitle `
            -FooterTemplate SystemToolbarOnly
        $layout = $Shell.Layout
        Write-FixedLine $layout.ListStartRow (Get-YarnBrowseUninstallI18n -Key 'yarn.uninstall.voltaMissing') -Color Red
        Start-Sleep -Milliseconds 1200
        return (Get-ShellNavMarker -Action 'back')
    }

    while ($true) {
        $voltaInfo = Get-VoltaYarnVersionInfo
        $activeVersion = Get-ActiveYarnVersion -TimeoutMs 2000
        $installed = @($voltaInfo.Map.Keys)

        if ($installed.Count -eq 0) {
            Initialize-ToolkitShellBodyView -Shell $Shell -SectionTitle $sectionTitle -FooterTemplate SystemToolbarOnly
            $layout = $Shell.Layout
            Write-FixedLine $layout.ListStartRow (Get-YarnBrowseUninstallI18n -Key 'yarn.uninstall.noInstalled') -Color Yellow
            Start-Sleep -Milliseconds 900
            return (Get-ShellNavMarker -Action 'back')
        }

        $items = Sort-YarnVersionItems -Items @(
            $installed | ForEach-Object { New-YarnVersionMenuItem -Version $_ }
        )
        $tagsWidth = Resolve-YarnBrowseUninstallTagsColumnWidth -Shell $Shell
        $rows = Build-YarnBrowseUninstallRows -Items $items -InstalledMap $voltaInfo.Map `
            -DefaultVersion $voltaInfo.Default -ActiveVersion $activeVersion
        $columnLayout = New-ShellListColumnLayout -Widths @($tagsWidth)

        Clear-ShellMultiSelectListCache -Shell $Shell -CacheKey 'YarnUninstall'
        Initialize-ShellMultiSelectListDependencies

        $toolbar = New-ShellSystemToolbarConfig
        $invokeMultiSelect = Get-Command Invoke-ShellMultiSelectList -CommandType Function -ErrorAction Stop
        $picked = & $invokeMultiSelect -Shell $Shell -SectionTitle $sectionTitle `
            -Rows $rows -CacheKey 'YarnUninstall' `
            -ColumnLayout $columnLayout `
            -ToolbarConfig $toolbar -CountLabel (Get-YarnBrowseUninstallI18n -Key 'yarn.uninstall.countUnit') `
            -SearchKeyMode

        if (Test-ShellNavMarker $picked) {
            return $picked
        }
        if ($null -eq $picked -or @($picked).Count -eq 0) {
            return (Get-ShellNavMarker -Action 'back')
        }

        $uninstallResult = Run-YarnBrowseUninstallOperation -Shell $Shell -Items $picked `
            -SectionTitle $yarnActionSectionTitle
        if (Test-ShellNavMarker $uninstallResult) {
            return $uninstallResult
        }
    }
}

$result = Invoke-YarnBrowseUninstallPage -Shell $ToolkitShell
if ($standaloneShell) {
    exit 0
}
return $result
