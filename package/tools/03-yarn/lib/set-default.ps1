# yarn — 设置全局默认 Yarn 版本

param(
    [hashtable]$ToolkitShell = $null,
    $Action = $null,

    [int]$PageSize = 0,
    [int]$ViewHeight = 0
)

$ErrorActionPreference = 'Stop'

$toolRoot = Split-Path $PSScriptRoot -Parent
$coreLib = Join-Path $toolRoot '..\..\core\lib'

. (Join-Path $PSScriptRoot 'yarn-installed-select.ps1')
Import-YarnInstalledSelectCore -CoreLib $coreLib
. (Join-Path $PSScriptRoot 'yarn-action-title.ps1')
Import-YarnActionTitleCore -CoreLib $coreLib
. (Join-Path $PSScriptRoot 'volta-yarn.ps1')
Initialize-YarnVoltaToolRoot -ToolRoot $toolRoot
Initialize-PathsFromToolRoot -ToolRoot $toolRoot

$yarnToolAction = Resolve-YarnToolAction -ToolRoot $toolRoot -Action $Action -ScriptLeaf 'set-default.ps1'
$yarnActionSectionTitle = Get-YarnActionSectionTitle -ToolRoot $toolRoot -Action $yarnToolAction `
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

function Get-YarnSetDefaultFlashMessage {
    param(
        [string]$ToolRoot,
        [string]$Version,
        [int]$ExitCode,
        [bool]$NoChange
    )

    if ($NoChange) {
        return (Get-YarnInstalledSelectI18n -ToolRoot $ToolRoot -Key 'yarn.default.noChange' `
            -Vars @{ version = $Version })
    }
    if ($ExitCode -ne 0) {
        return (Get-YarnInstalledSelectI18n -ToolRoot $ToolRoot -Key 'yarn.default.failed')
    }

    $message = Get-YarnInstalledSelectI18n -ToolRoot $ToolRoot -Key 'yarn.default.success' `
        -Vars @{ version = $Version }
    $active = Get-ActiveYarnVersion
    if (-not [string]::IsNullOrWhiteSpace($active)) {
        $message += ' · ' + (Get-YarnInstalledSelectI18n -ToolRoot $ToolRoot -Key 'yarn.default.activeYarn' `
            -Vars @{ version = $active })
    }
    return $message
}

function Invoke-YarnSetDefaultPage {
    param([hashtable]$Shell)

    $flashMessage = ''

    while ($true) {
        $listResult = Invoke-YarnInstalledVersionSingleSelectPage -Shell $Shell -ToolRoot $toolRoot `
            -I18nPrefix 'yarn.default' -CacheKey 'YarnDefault' -InitialFlashMessage $flashMessage `
            -SectionTitle $yarnActionSectionTitle
        $flashMessage = ''

        if ($nav = Get-ShellListSelectNavMarker $listResult) {
            return $nav
        }
        if ($listResult.Action -ne 'Pick' -or @($listResult.Rows).Count -eq 0) {
            return (Get-ShellNavMarker -Action 'back')
        }

        $ver = Resolve-YarnInstalledVersionFromPick -Picked $listResult.Rows[0]
        if ([string]::IsNullOrWhiteSpace($ver)) {
            continue
        }

        $voltaInfo = Get-VoltaYarnVersionInfo
        if ($ver -eq $voltaInfo.Default) {
            $flashMessage = Get-YarnSetDefaultFlashMessage -ToolRoot $toolRoot -Version $ver `
                -ExitCode 0 -NoChange
            continue
        }

        & volta install "yarn@$ver"
        $code = $LASTEXITCODE
        $flashMessage = Get-YarnSetDefaultFlashMessage -ToolRoot $toolRoot -Version $ver `
            -ExitCode $code -NoChange:$false
    }
}

$result = Invoke-YarnSetDefaultPage -Shell $ToolkitShell
if ($standaloneShell) {
    exit $(if ($null -eq $result) { 0 } elseif ($result -is [int]) { $result } else { 0 })
}
return $result
