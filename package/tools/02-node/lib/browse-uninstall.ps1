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
    . (Join-Path $coreLib 'ui\shell\ShellListModel.ps1')
    . (Join-Path $coreLib 'ui\shell\ShellListLayout.ps1')
    . (Join-Path $coreLib 'ui\shell\ToolkitShellList.ps1')
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

    return @($Items | ForEach-Object {
        $item = $_
        New-ShellListRow -Id ([string]$item.Version) -Cells @(
            (Get-NodeBrowseUninstallTagsLabel -Item $item -InstalledMap $InstalledMap `
                -DefaultVersion $DefaultVersion -ActiveVersion $ActiveVersion)
        ) -Payload $item -SearchKey ([string]$item.Version) -Enabled $true
    })
}

function Resolve-NodeBrowseUninstallTagsColumnWidth {
    param([hashtable]$Shell)

    $metrics = Get-ToolkitShellLayoutLineMetrics -Shell $Shell
    $versionKeyWidth = Get-ShellMultiSelectSearchKeyWidth
    $prefixReserve = Get-ShellListRowPrefixReserve -Mode Multi -KeyWidth $versionKeyWidth
    $remaining = [int]$metrics.EndColumn - $prefixReserve
    $maxTags = 26
    return [Math]::Max(10, [Math]::Min($maxTags, $remaining))
}

function Invoke-NodeBrowseUninstallNoticePage {
    param(
        [hashtable]$Shell,
        [string]$SectionTitle,
        [string]$Message
    )

    Clear-ShellListCache -Shell $Shell -CacheKey 'NodeUninstallNotice'
    return Invoke-ToolkitShellList @{
        Mode                 = 'Single'
        Shell                = $Shell
        SectionTitle         = $SectionTitle
        Rows                 = @()
        CacheKey             = 'NodeUninstallNotice'
        Toolbar              = (New-ShellSystemToolbarConfig)
        InitialFlashMessage  = $Message
    }
}

function Invoke-NodeBrowseUninstallPage {
    param([hashtable]$Shell)

    $null = Ensure-ToolkitShellLayoutBrandInnerWidth -Shell $Shell
    $sectionTitle = $nodeActionSectionTitle

    if (-not (Get-Command volta -ErrorAction SilentlyContinue)) {
        $noticeResult = Invoke-NodeBrowseUninstallNoticePage -Shell $Shell -SectionTitle $sectionTitle `
            -Message (Get-NodeBrowseUninstallI18n -Key 'node.uninstall.voltaMissing')
        if ($nav = Get-ShellListSelectNavMarker $noticeResult) {
            return $nav
        }
        return (Get-ShellNavMarker -Action 'back')
    }

    while ($true) {
        $voltaInfo = Get-VoltaNodeVersionInfo
        $activeVersion = Get-ActiveNodeVersion -TimeoutMs 2000
        $installed = @($voltaInfo.Map.Keys)

        if ($installed.Count -eq 0) {
            $noticeResult = Invoke-NodeBrowseUninstallNoticePage -Shell $Shell -SectionTitle $sectionTitle `
                -Message (Get-NodeBrowseUninstallI18n -Key 'node.uninstall.noInstalled')
            if ($nav = Get-ShellListSelectNavMarker $noticeResult) {
                return $nav
            }
            return (Get-ShellNavMarker -Action 'back')
        }

        $items = Sort-NodeVersionItems -Items @(
            $installed | ForEach-Object { New-NodeVersionMenuItem -Version $_ }
        )

        $tagsWidth = Resolve-NodeBrowseUninstallTagsColumnWidth -Shell $Shell
        $listLayout = New-ShellListLayout -Widths @($tagsWidth)
        $rows = Build-NodeBrowseUninstallRows -Items $items -InstalledMap $voltaInfo.Map `
            -DefaultVersion $voltaInfo.Default -ActiveVersion $activeVersion

        Clear-ShellListCache -Shell $Shell -CacheKey 'NodeUninstall'

        $listResult = Invoke-ToolkitShellList @{
            Mode         = 'Multi'
            Shell        = $Shell
            SectionTitle = $sectionTitle
            Rows         = $rows
            CacheKey     = 'NodeUninstall'
            Layout       = $listLayout
            Toolbar      = (New-ShellSystemToolbarConfig)
            CountLabel   = (Get-NodeBrowseUninstallI18n -Key 'node.uninstall.countUnit')
            KeyColumn    = 'SearchKey'
        }
        if ($nav = Get-ShellListSelectNavMarker $listResult) {
            return $nav
        }
        if ($listResult.Action -ne 'Pick') {
            return (Get-ShellNavMarker -Action 'back')
        }
        $picked = @($listResult.Payloads)

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
