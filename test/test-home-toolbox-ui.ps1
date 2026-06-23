$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$lib = Join-Path $root 'package\core\lib'
. (Join-Path $lib 'bootstrap\Load-Core.ps1') -LibDirectory $lib
Initialize-Paths -BinDirectory (Join-Path $root 'package\bin')

$script:CurrentLocale = 'zh'
$anchor = Measure-BrandStandardRightPanelWidth
$inner = Measure-ToolkitShellBrandInnerWidthForLocale -Locale 'zh'
$logo = Get-LogoColumnWidth
$naturalInner = $logo + 2 + $anchor
$expandedInner = Expand-ToolkitBrandInnerWidth -NaturalWidth $naturalInner
$consoleLimit = [Math]::Max(24, (Get-ConsoleLineWidth) - 1)
$expectedInner = [Math]::Min($expandedInner, $consoleLimit)
if ($inner -ne $expectedInner) {
    throw "zh brand inner should be min(expanded,console) ($expectedInner from natural $naturalInner), got $inner"
}
if ($expandedInner -le $naturalInner) {
    throw "brand inner should expand beyond natural width"
}

$compact = Format-I18nPaginationCompactStatus -PageIndex 0 -PageCount 5 -ItemCount 20
if ($compact -ne '01/05-20') {
    throw "compact pagination should be 01/05-20, got $compact"
}

$script:CurrentLocale = 'zh'
$keys = Get-MiaoI18nKeys
$multiSpace = Get-I18nKeyHint -Key $keys.Space -LabelKey 'common.toggle'
$singleSpace = Get-I18nKeyHint -Key $keys.Space -LabelKey 'common.confirm'
if ($multiSpace -eq $singleSpace) {
    throw 'multi-select space hint should differ from single-select confirm'
}

$layout = Resolve-ShellToolListColumnLayout -NumWidth 2 -BrandInnerWidth $inner
$metrics = Get-ToolkitShellLayoutLineMetrics -BrandInnerWidth $inner
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
$naturalDescEnd = 1 + $naturalInner
$naturalDescW = $naturalDescEnd - $prefixW - $fixedW
if ($layout.Widths[2] -lt $naturalDescW) {
    throw "description column should be at least natural-width desc ($naturalDescW), got $($layout.Widths[2])"
}

Write-Host 'test-home-toolbox-ui: OK'
