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

    return @($Items | ForEach-Object {
        $item = $_
        New-ShellListRow -Id ([string]$item.Version) -Cells @(
            (Get-YarnBrowseUninstallTagsLabel -Item $item -InstalledMap $InstalledMap `
                -DefaultVersion $DefaultVersion -ActiveVersion $ActiveVersion)
        ) -Payload $item -SearchKey ([string]$item.Version) -Enabled $true
    })
}

function Resolve-YarnBrowseUninstallTagsColumnWidth {
    param([hashtable]$Shell)

    $metrics = Get-ToolkitShellLayoutLineMetrics -Shell $Shell
    $versionKeyWidth = Get-ShellMultiSelectSearchKeyWidth
    $prefixReserve = Get-ShellListRowPrefixReserve -Mode Multi -KeyWidth $versionKeyWidth
    $remaining = [int]$metrics.EndColumn - $prefixReserve
    $maxTags = 26
    return [Math]::Max(10, [Math]::Min($maxTags, $remaining))
}

function Invoke-YarnBrowseUninstallNoticePage {
    param(
        [hashtable]$Shell,
        [string]$SectionTitle,
        [string]$Message
    )

    Clear-ShellListCache -Shell $Shell -CacheKey 'YarnUninstallNotice'
    return Invoke-ToolkitShellList @{
        Mode                 = 'Single'
        Shell                = $Shell
        SectionTitle         = $SectionTitle
        Rows                 = @()
        CacheKey             = 'YarnUninstallNotice'
        Toolbar              = (New-ShellSystemToolbarConfig)
        InitialFlashMessage  = $Message
    }
}

function Invoke-YarnBrowseUninstallPage {
    param([hashtable]$Shell)

    $null = Ensure-ToolkitShellLayoutBrandInnerWidth -Shell $Shell
    $sectionTitle = $yarnActionSectionTitle

    if (-not (Get-Command volta -ErrorAction SilentlyContinue)) {
        $noticeResult = Invoke-YarnBrowseUninstallNoticePage -Shell $Shell -SectionTitle $sectionTitle `
            -Message (Get-YarnBrowseUninstallI18n -Key 'yarn.uninstall.voltaMissing')
        if ($nav = Get-ShellListSelectNavMarker $noticeResult) {
            return $nav
        }
        return (Get-ShellNavMarker -Action 'back')
    }

    while ($true) {
        $voltaInfo = Get-VoltaYarnVersionInfo
        $activeVersion = Get-ActiveYarnVersion -TimeoutMs 2000
        $installed = @($voltaInfo.Map.Keys)

        if ($installed.Count -eq 0) {
            $noticeResult = Invoke-YarnBrowseUninstallNoticePage -Shell $Shell -SectionTitle $sectionTitle `
                -Message (Get-YarnBrowseUninstallI18n -Key 'yarn.uninstall.noInstalled')
            if ($nav = Get-ShellListSelectNavMarker $noticeResult) {
                return $nav
            }
            return (Get-ShellNavMarker -Action 'back')
        }

        $items = Sort-YarnVersionItems -Items @(
            $installed | ForEach-Object { New-YarnVersionMenuItem -Version $_ }
        )
        $tagsWidth = Resolve-YarnBrowseUninstallTagsColumnWidth -Shell $Shell
        $listLayout = New-ShellListLayout -Widths @($tagsWidth)
        $rows = Build-YarnBrowseUninstallRows -Items $items -InstalledMap $voltaInfo.Map `
            -DefaultVersion $voltaInfo.Default -ActiveVersion $activeVersion

        Clear-ShellListCache -Shell $Shell -CacheKey 'YarnUninstall'

        $listResult = Invoke-ToolkitShellList @{
            Mode         = 'Multi'
            Shell        = $Shell
            SectionTitle = $sectionTitle
            Rows         = $rows
            CacheKey     = 'YarnUninstall'
            Layout       = $listLayout
            Toolbar      = (New-ShellSystemToolbarConfig)
            CountLabel   = (Get-YarnBrowseUninstallI18n -Key 'yarn.uninstall.countUnit')
            KeyColumn    = 'SearchKey'
        }
        if ($nav = Get-ShellListSelectNavMarker $listResult) {
            return $nav
        }
        if ($listResult.Action -ne 'Pick') {
            return (Get-ShellNavMarker -Action 'back')
        }
        $picked = @($listResult.Payloads)

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
