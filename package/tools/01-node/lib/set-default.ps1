# node — 设置全局默认 Node 版本（Shell 单选已安装列表）

param(
    [hashtable]$ToolkitShell = $null,
    $Action = $null,

    [int]$PageSize = 0,
    [int]$ViewHeight = 0
)

$ErrorActionPreference = 'Stop'

$toolRoot = Split-Path $PSScriptRoot -Parent
$coreLib = Join-Path $toolRoot '..\..\core\lib'

. (Join-Path $PSScriptRoot 'node-installed-select.ps1')
Import-NodeInstalledSelectCore -CoreLib $coreLib
. (Join-Path $PSScriptRoot 'node-action-title.ps1')
Import-NodeActionTitleCore -CoreLib $coreLib
. (Join-Path $PSScriptRoot 'volta-node.ps1')
Initialize-NodeVoltaToolRoot -ToolRoot $toolRoot
Initialize-PathsFromToolRoot -ToolRoot $toolRoot

$nodeToolAction = Resolve-NodeToolAction -ToolRoot $toolRoot -Action $Action -ScriptLeaf 'set-default.ps1'
$nodeActionSectionTitle = Get-NodeActionSectionTitle -ToolRoot $toolRoot -Action $nodeToolAction `
    -ScriptLeaf 'set-default.ps1'

$paging = Resolve-MenuPagingDefaults -PageSize $PageSize -ViewHeight $ViewHeight
$PageSize = $paging.PageSize
$ViewHeight = $paging.ViewHeight

$standaloneShell = $false
if (-not $ToolkitShell) {
    $ToolkitShell = Initialize-ToolkitShell
    $standaloneShell = $true
}

Sync-MiaoLocaleFromShell -Shell $ToolkitShell

function Get-NodeSetDefaultFlashMessage {
    param(
        [string]$ToolRoot,
        [string]$Version,
        [int]$ExitCode,
        [bool]$NoChange
    )

    if ($NoChange) {
        return (Get-NodeInstalledSelectI18n -ToolRoot $ToolRoot -Key 'node.default.noChange' `
            -Vars @{ version = $Version })
    }
    if ($ExitCode -ne 0) {
        return (Get-NodeInstalledSelectI18n -ToolRoot $ToolRoot -Key 'node.default.failed')
    }

    $message = Get-NodeInstalledSelectI18n -ToolRoot $ToolRoot -Key 'node.default.success' `
        -Vars @{ version = $Version }
    $active = Get-ActiveNodeVersion
    if (-not [string]::IsNullOrWhiteSpace($active)) {
        $message += ' · ' + (Get-NodeInstalledSelectI18n -ToolRoot $ToolRoot -Key 'node.default.activeNode' `
            -Vars @{ version = $active })
    }
    return $message
}

function Invoke-NodeSetDefaultPage {
    param([hashtable]$Shell)

    $flashMessage = ''

    while ($true) {
        $listResult = Invoke-NodeInstalledVersionSingleSelectPage -Shell $Shell -ToolRoot $toolRoot `
            -I18nPrefix 'node.default' -CacheKey 'NodeDefault' -InitialFlashMessage $flashMessage `
            -SectionTitle $nodeActionSectionTitle
        $flashMessage = ''

        if ($nav = Get-ShellListSelectNavMarker $listResult) {
            return $nav
        }
        if ($listResult.Action -ne 'Pick' -or @($listResult.Rows).Count -eq 0) {
            return (Get-ShellNavMarker -Action 'back')
        }

        $ver = Resolve-NodeInstalledVersionFromPick -Picked $listResult.Rows[0]
        if ([string]::IsNullOrWhiteSpace($ver)) {
            continue
        }

        $voltaInfo = Get-VoltaNodeVersionInfo
        if ($ver -eq $voltaInfo.Default) {
            $flashMessage = Get-NodeSetDefaultFlashMessage -ToolRoot $toolRoot -Version $ver `
                -ExitCode 0 -NoChange
            continue
        }

        & volta install "node@$ver"
        $code = $LASTEXITCODE
        $flashMessage = Get-NodeSetDefaultFlashMessage -ToolRoot $toolRoot -Version $ver `
            -ExitCode $code -NoChange:$false
    }
}

$result = Invoke-NodeSetDefaultPage -Shell $ToolkitShell
if ($standaloneShell) {
    exit $(if ($null -eq $result) { 0 } elseif ($result -is [int]) { $result } else { 0 })
}
return $result
