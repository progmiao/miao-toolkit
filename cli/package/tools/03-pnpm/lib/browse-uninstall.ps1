# pnpm — 浏览并卸载（Shell 多选已安装版本列表）

param(
    [hashtable]$ToolkitShell = $null,
    $Action = $null,

    [int]$PageSize = 0,
    [int]$ViewHeight = 0
)

$ErrorActionPreference = 'Stop'

$toolRoot = Split-Path $PSScriptRoot -Parent
$coreLib = Join-Path $toolRoot '..\..\core\lib'

function Import-PnpmBrowseUninstallCore {
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
    . (Join-Path $coreLib 'ui\shell\ShellListModel.ps1')
    . (Join-Path $coreLib 'ui\shell\ShellListLayout.ps1')
    . (Join-Path $coreLib 'ui\shell\ToolkitShellList.ps1')
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

Import-PnpmBrowseUninstallCore
. (Join-Path $PSScriptRoot 'pnpm-action-title.ps1')
Import-PnpmActionTitleCore -CoreLib $coreLib
. (Join-Path $PSScriptRoot 'volta-pnpm.ps1')
Set-PnpmVoltaToolRoot -ToolRoot $toolRoot
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

$PnpmToolAction = Resolve-PnpmToolAction -ToolRoot $toolRoot -Action $Action -ScriptLeaf 'browse-uninstall.ps1'
$PnpmActionSectionTitle = Get-PnpmActionSectionTitle -ToolRoot $toolRoot -Action $PnpmToolAction `
    -ScriptLeaf 'browse-uninstall.ps1'
$script:PnpmActionSectionTitle = $PnpmActionSectionTitle

function Get-PnpmBrowseUninstallI18n {
    param(
        [string]$Key,
        [hashtable]$Vars = @{}
    )

    return Get-ToolI18n -ToolRoot $toolRoot -Key $Key -Vars $Vars
}

function Get-PnpmBrowseUninstallTagsLabel {
    param(
        $Item,
        [hashtable]$InstalledMap,
        [string]$DefaultVersion,
        [string]$ActiveVersion
    )

    return (Get-PnpmVersionStatusTags -Item $Item -InstalledMap $InstalledMap `
        -DefaultVersion $DefaultVersion -ActiveVersion $ActiveVersion)
}

function Build-PnpmBrowseUninstallRows {
    param(
        [array]$Items,
        [hashtable]$InstalledMap,
        [string]$DefaultVersion,
        [string]$ActiveVersion
    )

    return @($Items | ForEach-Object {
        $item = $_
        New-ShellListRow -Id ([string]$item.Version) -Cells @(
            (Get-PnpmBrowseUninstallTagsLabel -Item $item -InstalledMap $InstalledMap `
                -DefaultVersion $DefaultVersion -ActiveVersion $ActiveVersion)
        ) -Payload $item -SearchKey ([string]$item.Version) -Enabled $true
    })
}

function Resolve-PnpmBrowseUninstallTagsColumnWidth {
    param([hashtable]$Shell)

    $metrics = Get-ToolkitShellLayoutLineMetrics -Shell $Shell
    $versionKeyWidth = Get-ShellMultiSelectSearchKeyWidth
    $prefixReserve = Get-ShellListRowPrefixReserve -Mode Multi -KeyWidth $versionKeyWidth
    $remaining = [int]$metrics.EndColumn - $prefixReserve
    $maxTags = 26
    return [Math]::Max(10, [Math]::Min($maxTags, $remaining))
}

function Invoke-PnpmBrowseUninstallNoticePage {
    param(
        [hashtable]$Shell,
        [string]$SectionTitle,
        [string]$Message
    )

    Clear-ShellListCache -Shell $Shell -CacheKey 'PnpmUninstallNotice'
    return Invoke-ToolkitShellList @{
        Mode                 = 'Single'
        Shell                = $Shell
        SectionTitle         = $SectionTitle
        Rows                 = @()
        CacheKey             = 'PnpmUninstallNotice'
        Toolbar              = (New-ShellSystemToolbarConfig)
        InitialFlashMessage  = $Message
    }
}

function Invoke-PnpmBrowseUninstallPage {
    param([hashtable]$Shell)

    $null = Ensure-ToolkitShellLayoutBrandInnerWidth -Shell $Shell
    $sectionTitle = $PnpmActionSectionTitle

    if (-not (Get-Command volta -ErrorAction SilentlyContinue)) {
        $noticeResult = Invoke-PnpmBrowseUninstallNoticePage -Shell $Shell -SectionTitle $sectionTitle `
            -Message (Get-PnpmBrowseUninstallI18n -Key 'pnpm.uninstall.voltaMissing')
        if ($nav = Get-ShellListSelectNavMarker $noticeResult) {
            return $nav
        }
        return (Get-ShellNavMarker -Action 'back')
    }

    while ($true) {
        $voltaInfo = Get-VoltaPnpmVersionInfo
        $activeVersion = Get-ActivePnpmVersion -TimeoutMs 2000
        $installed = @($voltaInfo.Map.Keys)

        if ($installed.Count -eq 0) {
            $noticeResult = Invoke-PnpmBrowseUninstallNoticePage -Shell $Shell -SectionTitle $sectionTitle `
                -Message (Get-PnpmBrowseUninstallI18n -Key 'pnpm.uninstall.noInstalled')
            if ($nav = Get-ShellListSelectNavMarker $noticeResult) {
                return $nav
            }
            return (Get-ShellNavMarker -Action 'back')
        }

        $items = Sort-PnpmVersionItems -Items @(
            $installed | ForEach-Object { New-PnpmVersionMenuItem -Version $_ }
        )
        $tagsWidth = Resolve-PnpmBrowseUninstallTagsColumnWidth -Shell $Shell
        $listLayout = New-ShellListLayout -Widths @($tagsWidth)
        $rows = Build-PnpmBrowseUninstallRows -Items $items -InstalledMap $voltaInfo.Map `
            -DefaultVersion $voltaInfo.Default -ActiveVersion $activeVersion

        Clear-ShellListCache -Shell $Shell -CacheKey 'PnpmUninstall'

        $listResult = Invoke-ToolkitShellList @{
            Mode         = 'Multi'
            Shell        = $Shell
            SectionTitle = $sectionTitle
            Rows         = $rows
            CacheKey     = 'PnpmUninstall'
            Layout       = $listLayout
            Toolbar      = (New-ShellSystemToolbarConfig)
            CountLabel   = (Get-PnpmBrowseUninstallI18n -Key 'pnpm.uninstall.countUnit')
            KeyColumn    = 'SearchKey'
        }
        if ($nav = Get-ShellListSelectNavMarker $listResult) {
            return $nav
        }
        if ($listResult.Action -ne 'Pick') {
            return (Get-ShellNavMarker -Action 'back')
        }
        $picked = @($listResult.Payloads)

        $uninstallResult = Run-PnpmBrowseUninstallOperation -Shell $Shell -Items $picked `
            -SectionTitle $PnpmActionSectionTitle
        if (Test-ShellNavMarker $uninstallResult) {
            return $uninstallResult
        }
    }
}

$result = Invoke-PnpmBrowseUninstallPage -Shell $ToolkitShell
if ($standaloneShell) {
    exit 0
}
return $result
