$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$lib = Join-Path $root 'package\core\lib'
. (Join-Path $lib 'bootstrap\Load-Core.ps1') -LibDirectory $lib
Initialize-Paths -BinDirectory (Join-Path $root 'package\bin')

$script:CurrentLocale = 'zh'
$anchor = Measure-BrandStandardRightPanelWidth
$inner = Measure-ToolkitShellBrandInnerWidthForLocale -Locale 'zh'
$logo = Get-LogoColumnWidth
$expectedInner = $logo + 2 + $anchor
if ($inner -ne $expectedInner) {
    throw "zh brand inner should be logo+gap+anchor ($expectedInner), got $inner"
}

$compact = Format-I18nPaginationCompactStatus -PageIndex 0 -PageCount 5 -ItemCount 20
if ($compact -ne '01/05-20') {
    throw "compact pagination should be 01/05-20, got $compact"
}

$layout = Resolve-ShellToolListColumnLayout -NumWidth 2 -BrandInnerWidth $inner
$metrics = Get-ToolkitShellContentMetrics -BrandInnerWidth $inner
$colGap = Get-MenuColumnGap
$leading = Get-ShellSingleSelectListLeadingSpaces
$prefixW = $leading + 1 + 1 + 2 + $colGap
$fixedW = $layout.Widths[0] + $colGap + $layout.Widths[1] + $colGap
$rowW = $prefixW + $fixedW + $layout.Widths[2]
if ($rowW -gt $metrics.EndColumn) {
    throw "tool list row width $rowW exceeds content end $($metrics.EndColumn)"
}
if ($layout.Widths[0] -ne 12 -or $layout.Widths[1] -ne 18) {
    throw 'command/name columns should stay 12/18'
}
if ((Get-BrandSeparatorExtra) -ne 0) {
    throw 'toolbox chrome should not extend past brand inner width'
}
if ($layout.Widths[2] -ge 32) {
    throw "description column should shrink below fixed 32, got $($layout.Widths[2])"
}

Write-Host 'test-home-toolbox-ui: OK'
