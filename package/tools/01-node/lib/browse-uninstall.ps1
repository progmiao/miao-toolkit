# node — 浏览并卸载（Shell 多选已安装版本列表）

param(
    [hashtable]$ToolkitShell = $null,
    $Action = $null,

    [int]$PageSize = 0,
    [int]$ViewHeight = 0
)

$ErrorActionPreference = 'Stop'

$toolRoot = Split-Path $PSScriptRoot -Parent
$coreLib = Join-Path $toolRoot '..\..\core\lib'

function Import-NodeBrowseUninstallCore {
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
    . (Join-Path $coreLib 'ui\shell\Exit.ps1')
    . (Join-Path $coreLib 'ui\shell\Footer.ps1')

    if (-not (Get-Command Draw-ToolkitDepOperationView -ErrorAction SilentlyContinue)) {
        . (Join-Path $coreLib 'ui\shell\DepOperationView.ps1')
    }
}

Import-NodeBrowseUninstallCore
. (Join-Path $PSScriptRoot 'node-action-title.ps1')
Import-NodeActionTitleCore -CoreLib $coreLib
. (Join-Path $PSScriptRoot 'volta-node.ps1')
Set-NodeVoltaToolRoot -ToolRoot $toolRoot
. (Join-Path $PSScriptRoot 'browse-install-run.ps1')
. (Join-Path $PSScriptRoot 'browse-uninstall-run.ps1')
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

$nodeToolAction = Resolve-NodeToolAction -ToolRoot $toolRoot -Action $Action -ScriptLeaf 'browse-uninstall.ps1'
$nodeActionSectionTitle = Get-NodeActionSectionTitle -ToolRoot $toolRoot -Action $nodeToolAction `
    -ScriptLeaf 'browse-uninstall.ps1'
$script:NodeActionSectionTitle = $nodeActionSectionTitle

function Get-NodeBrowseUninstallI18n {
    param(
        [string]$Key,
        [hashtable]$Vars = @{}
    )

    return Get-ToolI18n -ToolRoot $toolRoot -Key $Key -Vars $Vars
}

function Get-NodeBrowseUninstallTagsLabel {
    param(
        $Item,
        [hashtable]$InstalledMap,
        [string]$DefaultVersion,
        [string]$ActiveVersion
    )

    return (Get-NodeVersionStatusTags -Item $Item -InstalledMap $InstalledMap `
        -DefaultVersion $DefaultVersion -ActiveVersion $ActiveVersion)
}

function Build-NodeBrowseUninstallRows {
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
            (Get-NodeBrowseUninstallTagsLabel -Item $Item -InstalledMap $InstalledMap `
                -DefaultVersion $DefaultVersion -ActiveVersion $ActiveVersion)
        )
    } -GetEnabled {
        param($Item, [int]$Index)
        $true
    }
}

function Resolve-NodeBrowseUninstallTagsColumnWidth {
    param([hashtable]$Shell)

    $metrics = Get-ToolkitShellLayoutLineMetrics -Shell $Shell
    $versionKeyWidth = Get-ShellMultiSelectSearchKeyWidth
    $gap = Get-MenuColumnGap
    $prefixReserve = 2 + 3 + 1 + $versionKeyWidth + $gap
    $remaining = [int]$metrics.EndColumn - $prefixReserve
    $maxTags = 26
    return [Math]::Max(10, [Math]::Min($maxTags, $remaining))
}

function Invoke-NodeBrowseUninstallPage {
    param([hashtable]$Shell)

    $null = Ensure-ToolkitShellLayoutBrandInnerWidth -Shell $Shell
    $sectionTitle = $nodeActionSectionTitle

    if (-not (Get-Command volta -ErrorAction SilentlyContinue)) {
        Initialize-ToolkitShellBodyView -Shell $Shell -SectionTitle $sectionTitle `
            -FooterTemplate SystemToolbarOnly
        $layout = $Shell.Layout
        Write-FixedLine $layout.ListStartRow (Get-NodeBrowseUninstallI18n -Key 'node.uninstall.voltaMissing') -Color Red
        Start-Sleep -Milliseconds 1200
        return (Get-ShellNavMarker -Action 'back')
    }

    while ($true) {
        $voltaInfo = Get-VoltaNodeVersionInfo
        $activeVersion = Get-ActiveNodeVersion -TimeoutMs 2000
        $installed = @($voltaInfo.Map.Keys)

        if ($installed.Count -eq 0) {
            Initialize-ToolkitShellBodyView -Shell $Shell -SectionTitle $sectionTitle -FooterTemplate SystemToolbarOnly
            $layout = $Shell.Layout
            Write-FixedLine $layout.ListStartRow (Get-NodeBrowseUninstallI18n -Key 'node.uninstall.noInstalled') -Color Yellow
            Start-Sleep -Milliseconds 900
            return (Get-ShellNavMarker -Action 'back')
        }

        $items = Sort-NodeVersionItems -Items @(
            $installed | ForEach-Object { New-NodeVersionMenuItem -Version $_ }
        )

        $tagsWidth = Resolve-NodeBrowseUninstallTagsColumnWidth -Shell $Shell
        $rows = Build-NodeBrowseUninstallRows -Items $items -InstalledMap $voltaInfo.Map `
            -DefaultVersion $voltaInfo.Default -ActiveVersion $activeVersion

        Clear-ShellMultiSelectListCache -Shell $Shell -CacheKey 'NodeUninstall'

        $toolbar = New-ShellSystemToolbarConfig
        $invokeMultiSelect = Get-Command Invoke-ShellMultiSelectList -CommandType Function -ErrorAction Stop
        $picked = & $invokeMultiSelect -Shell $Shell -SectionTitle $sectionTitle `
            -Rows $rows -CacheKey 'NodeUninstall' `
            -ColumnLayout (New-ShellListColumnLayout -Widths @($tagsWidth)) `
            -ToolbarConfig $toolbar -CountLabel (Get-NodeBrowseUninstallI18n -Key 'node.uninstall.countUnit') `
            -SearchKeyMode

        if (Test-ShellNavMarker $picked) {
            return $picked
        }
        if ($null -eq $picked -or @($picked).Count -eq 0) {
            return (Get-ShellNavMarker -Action 'back')
        }

        $pickedVersions = @((Get-NodeBrowseUninstallPlanVersions -Items $picked -InstalledMap $voltaInfo.Map))
        if ($pickedVersions.Count -eq 0) {
            return (Get-ShellNavMarker -Action 'back')
        }

        $uninstallResult = Run-NodeBrowseUninstallOperation -Shell $Shell -Items $picked `
            -SectionTitle $nodeActionSectionTitle
        if (Test-ShellNavMarker $uninstallResult) {
            return $uninstallResult
        }
    }
}

$result = Invoke-NodeBrowseUninstallPage -Shell $ToolkitShell
if ($standaloneShell) {
    exit 0
}
return $result
