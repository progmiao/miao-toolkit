$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$lib = Join-Path $root 'package\core\lib'
. (Join-Path $lib 'bootstrap\Load-Core.ps1') -LibDirectory $lib
Initialize-Paths -BinDirectory (Join-Path $root 'package\bin')

$toolRoot = Join-Path $root 'package\tools\01-node'
Initialize-PathsFromToolRoot -ToolRoot $toolRoot
. (Join-Path $lib 'ui\shell\DepOperationView.ps1')

$brandInner = 40
$expectedWidth = 1 + (Get-BrandSeparatorLineWidth -BrandInnerWidth $brandInner)

$bar0 = Format-ToolkitDepProgressBar -Current 0 -Total 1 -Name '' -BrandInnerWidth $brandInner -LoadingPercent 0
$bar35 = Format-ToolkitDepProgressBar -Current 0 -Total 1 -Name '' -BrandInnerWidth $brandInner -LoadingPercent 35
$bar100 = Format-ToolkitDepProgressBar -Current 0 -Total 1 -Name '' -BrandInnerWidth $brandInner -LoadingPercent 100

foreach ($bar in @($bar0, $bar35, $bar100)) {
    if ((Get-DisplayWidth $bar) -ne $expectedWidth) {
        throw "loading bar width mismatch: expected $expectedWidth, got $(Get-DisplayWidth $bar) [$bar]"
    }
    if ($bar -match '0/1') {
        throw "loading bar should not show 0/1, got: [$bar]"
    }
}

if ($bar0 -notmatch '  0%$') {
    throw "expected zero-padded 0% suffix, got: [$bar0]"
}
if ($bar35 -notmatch ' 35%$') {
    throw "expected padded 35% suffix, got: [$bar35]"
}
if ($bar100 -notmatch '100%$') {
    throw "expected 100% suffix, got: [$bar100]"
}

$suffix0 = ($bar0 -replace '^.*\]', '')
$suffix35 = ($bar35 -replace '^.*\]', '')
$suffix100 = ($bar100 -replace '^.*\]', '')
if ((Get-DisplayWidth $suffix0) -ne (Get-DisplayWidth $suffix100)) {
    throw "suffix width should match 100% slot: 0=[$suffix0] 100=[$suffix100]"
}
if ((Get-DisplayWidth $suffix35) -ne (Get-DisplayWidth $suffix100)) {
    throw "suffix width should match 100% slot: 35=[$suffix35] 100=[$suffix100]"
}

if ($bar100 -match '-') {
    throw "expected no dash at 100%, got: [$bar100]"
}

$fetch = Get-ToolI18n -ToolRoot $toolRoot -Key 'node.browse.loadingFetch' -Vars @{ spinner = '|' }
if ($fetch -notmatch 'Node') {
    throw "expected fetch loading text with Node, got: [$fetch]"
}

Write-Host 'BROWSE LOADING PERCENT OK'
