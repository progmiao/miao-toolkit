# common placeholder page

param(
    [Parameter(Mandatory = $true)]
    $Config,

    [Parameter(Mandatory = $true)]
    [string]$ToolRoot,

    [hashtable]$ToolkitShell = $null,

    [int]$PageSize = 0,
    [int]$ViewHeight = 0
)

$ErrorActionPreference = 'Stop'

$coreLib = Join-Path $ToolRoot '..\..\core\lib'
. (Join-Path $coreLib 'config\Paths.ps1')
. (Join-Path $coreLib 'config\I18n.ps1')
. (Join-Path $coreLib 'domain\Discover-Tools.ps1')
. (Join-Path $coreLib 'ui\shell\Nav.ps1')
. (Join-Path $coreLib 'ui\shell\SystemToolbar.ps1')
. (Join-Path $coreLib 'ui\shell\ToolkitShellList.ps1')

Initialize-PathsFromToolRoot -ToolRoot $ToolRoot
$paging = Resolve-MenuPagingDefaults -PageSize $PageSize -ViewHeight $ViewHeight

if (-not $ToolkitShell) {
    $ToolkitShell = Initialize-ToolkitShell
}

Sync-MiaoLocaleFromShell -Shell $ToolkitShell
$tool = Get-ToolFromDirectory -ToolRoot $ToolRoot
$sectionTitle = Get-ToolSectionTitle -Tool $tool
$emptyMsg = Get-ToolI18n -ToolRoot $ToolRoot -Key 'common.empty' -Fallback 'No utilities yet'

return Invoke-ToolkitShellList @{
    Mode             = 'Single'
    Shell            = $ToolkitShell
    SectionTitle     = $sectionTitle
    Rows             = @()
    CacheKey         = 'common'
    Toolbar          = (New-ShellSystemToolbarConfig)
    EmptyListMessage = $emptyMsg
}
