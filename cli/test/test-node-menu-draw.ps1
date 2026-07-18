$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$lib = Join-Path $root 'package\core\lib'
. (Join-Path $lib 'bootstrap\Load-Core.ps1') -LibDirectory $lib
Initialize-Paths -BinDirectory (Join-Path $root 'package\bin')
Import-MiaoModule -Name Tool

$toolRoot = Join-Path $root 'package\tools\01-node'
$tool = Get-ToolFromDirectory -ToolRoot $toolRoot
$config = Get-Content (Join-Path $toolRoot 'index.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$menuItems = @(Get-ToolMenuItems -BusinessActions @($config.actions) -Tool $tool)
$rows = ConvertTo-ToolMenuListRows -ToolRoot $toolRoot -MenuItems $menuItems

if ([string]::IsNullOrWhiteSpace($rows[0].Cells[1])) {
    throw "expected name column, got: $($rows[0].Cells -join '|')"
}

$listLayout = New-ShellListLayout -Widths @(12, 18, 0)
$columnLayout = Resolve-ShellListLayoutColumnLayout -Layout $listLayout
$normalized = @(Normalize-ShellListRows -Rows $rows -Layout $listLayout)
$built = Build-ShellSingleSelectListRowCache -Rows $normalized -ColumnLayout $columnLayout
if ([string]::IsNullOrWhiteSpace($built.RowCache[0].BodyPlain)) {
    throw 'BodyPlain should not be empty'
}

$spec = Build-ShellSingleSelectListRowSpec -RowCacheEntry $built.RowCache[0] -Selected $false `
    -NumWidth 2 -DisplayNumber 1 -Gap $built.ColGap
if ($spec.Segments.Count -lt 2) {
    throw "expected mark/key/body segments, got $($spec.Segments.Count)"
}
if ($spec.Segments[0].Text -ne '  ') {
    throw "unfocused mark segment should be two spaces, got '$($spec.Segments[0].Text)'"
}

$unfocusedPrefix = $spec.Segments[0].Text + $spec.Segments[1].Text
$specFocused = Build-ShellSingleSelectListRowSpec -RowCacheEntry $built.RowCache[0] -Selected $true `
    -NumWidth 2 -DisplayNumber 1 -Gap $built.ColGap
$numIdxUnfocused = $unfocusedPrefix.IndexOf('01')
$numIdxFocused = $specFocused.Text.IndexOf('01')
if ($numIdxFocused -ne ($numIdxUnfocused + 1)) {
    throw "focused row should shift number column right by 1 (unfocused=$numIdxUnfocused focused=$numIdxFocused)"
}

$handlers = New-ShellSingleSelectListDrawHandlers -RowCache $built.RowCache -ColGap $built.ColGap
$label = & $handlers['GetLabel'] $normalized[0] 0
if ([string]::IsNullOrWhiteSpace($label)) {
    throw 'GetLabel returned empty'
}

Write-Host 'NODE MENU DRAW OK'
