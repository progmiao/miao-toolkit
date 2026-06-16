$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$lib = Join-Path $root 'package\core\lib'
. (Join-Path $lib 'bootstrap\Load-Core.ps1') -LibDirectory $lib
Initialize-Paths -BinDirectory (Join-Path $root 'package\bin')

$toolRoot = Join-Path $root 'package\tools\node'
Initialize-PathsFromToolRoot -ToolRoot $toolRoot
. (Join-Path $lib 'ui\shell\DepOperationView.ps1')

$bar = Format-ToolkitDepProgressBar -Current 0 -Total 1 -Name '' -BrandInnerWidth 40 -LoadingPercent 35
if ($bar -notmatch '35%') {
    throw "expected 35% suffix, got: [$bar]"
}
if ($bar -match '0/1') {
    throw "loading bar should not show 0/1, got: [$bar]"
}

$bar100 = Format-ToolkitDepProgressBar -Current 0 -Total 1 -Name '' -BrandInnerWidth 40 -LoadingPercent 100
if ($bar100 -notmatch '100%') {
    throw "expected 100% suffix, got: [$bar100]"
}

$fetch = Get-ToolI18n -ToolRoot $toolRoot -Key 'node.browse.loadingFetch' -Vars @{ spinner = '|' }
if ($fetch -notmatch 'Node') {
    throw "expected fetch loading text with Node, got: [$fetch]"
}

Write-Host 'BROWSE LOADING PERCENT OK'
