$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$lib = Join-Path $root 'package\core\lib'
. (Join-Path $lib 'bootstrap\Load-Core.ps1') -LibDirectory $lib

$built = Build-ShellSingleSelectListRowCache -Rows @(
    [pscustomobject]@{ Cells = @('cmd', 'name', 'desc'); Enabled = $true; Number = 1 }
) -ColumnLayout @{ Widths = @(12, 18, 20) }
$gap = $built.ColGap

$un = Build-ShellSingleSelectListRowSpec -RowCacheEntry $built.RowCache[0] -Selected $false `
    -NumWidth 2 -DisplayNumber 1 -Gap $gap
$sel = Build-ShellSingleSelectListRowSpec -RowCacheEntry $built.RowCache[0] -Selected $true `
    -NumWidth 2 -DisplayNumber 1 -Gap $gap

$unPrefix = $un.Segments[0].Text + $un.Segments[1].Text
$numUn = $unPrefix.IndexOf('01')
$numSel = $sel.Text.IndexOf('01')
if ($numSel -ne ($numUn + 1)) {
    throw "single-select focus should shift number right by 1 (un=$numUn sel=$numSel unPrefix=[$unPrefix] selPrefix=[$($sel.Text.Substring(0, 8))])"
}

$menuUn = Format-MenuNumberedRow -GlobalIndex 0 -Label 'test' -NumWidth 2 -Selected $false -Disabled $false
$menuSel = Format-MenuNumberedRow -GlobalIndex 0 -Label 'test' -NumWidth 2 -Selected $true -Disabled $false
$menuNumUn = $menuUn.IndexOf('01')
$menuNumSel = $menuSel.IndexOf('01')
if ($menuNumSel -ne ($menuNumUn + 1)) {
    throw "Format-MenuNumberedRow should shift number right by 1 (un=$menuNumUn sel=$menuNumSel)"
}

Write-Host 'test-single-select-focus-shift: OK'
