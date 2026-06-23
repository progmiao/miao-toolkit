# pnpm — 设置全局默认 pnpm 版本

param(
    [hashtable]$ToolkitShell = $null,
    $Action = $null,

    [int]$PageSize = 0,
    [int]$ViewHeight = 0
)

$ErrorActionPreference = 'Stop'

$toolRoot = Split-Path $PSScriptRoot -Parent
$coreLib = Join-Path $toolRoot '..\..\core\lib'

. (Join-Path $PSScriptRoot 'pnpm-installed-select.ps1')
Import-PnpmInstalledSelectCore -CoreLib $coreLib
. (Join-Path $PSScriptRoot 'pnpm-action-title.ps1')
Import-PnpmActionTitleCore -CoreLib $coreLib
. (Join-Path $PSScriptRoot 'volta-pnpm.ps1')
Initialize-PnpmVoltaToolRoot -ToolRoot $toolRoot
Initialize-PathsFromToolRoot -ToolRoot $toolRoot

$PnpmToolAction = Resolve-PnpmToolAction -ToolRoot $toolRoot -Action $Action -ScriptLeaf 'set-default.ps1'
$PnpmActionSectionTitle = Get-PnpmActionSectionTitle -ToolRoot $toolRoot -Action $PnpmToolAction `
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

function Get-PnpmSetDefaultFlashMessage {
    param(
        [string]$ToolRoot,
        [string]$Version,
        [int]$ExitCode,
        [bool]$NoChange
    )

    if ($NoChange) {
        return (Get-PnpmInstalledSelectI18n -ToolRoot $ToolRoot -Key 'pnpm.default.noChange' `
            -Vars @{ version = $Version })
    }
    if ($ExitCode -ne 0) {
        return (Get-PnpmInstalledSelectI18n -ToolRoot $ToolRoot -Key 'pnpm.default.failed')
    }

    $message = Get-PnpmInstalledSelectI18n -ToolRoot $ToolRoot -Key 'pnpm.default.success' `
        -Vars @{ version = $Version }
    $active = Get-ActivePnpmVersion
    if (-not [string]::IsNullOrWhiteSpace($active)) {
        $message += ' · ' + (Get-PnpmInstalledSelectI18n -ToolRoot $ToolRoot -Key 'pnpm.default.activePnpm' `
            -Vars @{ version = $active })
    }
    return $message
}

function Invoke-PnpmSetDefaultPage {
    param([hashtable]$Shell)

    $flashMessage = ''

    while ($true) {
        $picked = Invoke-PnpmInstalledVersionSingleSelectPage -Shell $Shell -ToolRoot $toolRoot `
            -I18nPrefix 'pnpm.default' -CacheKey 'PnpmDefault' -InitialFlashMessage $flashMessage `
            -SectionTitle $PnpmActionSectionTitle
        $flashMessage = ''

        if (Test-ShellNavMarker $picked) {
            return $picked
        }
        if ($null -eq $picked) {
            return (Get-ShellNavMarker -Action 'back')
        }

        $ver = Resolve-PnpmInstalledVersionFromPick -Picked $picked
        if ([string]::IsNullOrWhiteSpace($ver)) {
            continue
        }

        $voltaInfo = Get-VoltaPnpmVersionInfo
        if ($ver -eq $voltaInfo.Default) {
            $flashMessage = Get-PnpmSetDefaultFlashMessage -ToolRoot $toolRoot -Version $ver `
                -ExitCode 0 -NoChange
            continue
        }

        Ensure-VoltaPnpmFeatureEnabled
        & volta install "pnpm@$ver"
        $code = $LASTEXITCODE
        $flashMessage = Get-PnpmSetDefaultFlashMessage -ToolRoot $toolRoot -Version $ver `
            -ExitCode $code -NoChange:$false
    }
}

$result = Invoke-PnpmSetDefaultPage -Shell $ToolkitShell
if ($standaloneShell) {
    exit $(if ($null -eq $result) { 0 } elseif ($result -is [int]) { $result } else { 0 })
}
return $result
