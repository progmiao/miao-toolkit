$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$lib = Join-Path $root 'package\core\lib'
. (Join-Path $lib 'bootstrap\Load-Core.ps1') -LibDirectory $lib
Initialize-Paths -BinDirectory (Join-Path $root 'package\bin')
Import-MiaoModule -Name Tool

$toolRoot = Join-Path $root 'package\tools\node'
$tool = Get-ToolFromDirectory -ToolRoot $toolRoot
$config = Get-Content (Join-Path $toolRoot 'index.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$menuItems = @(Get-ToolMenuItems -BusinessActions @($config.actions) -Tool $tool)
$rows = ConvertTo-ToolMenuListRows -ToolRoot $toolRoot -MenuItems $menuItems

if ([string]::IsNullOrWhiteSpace($rows[0].Cells[1])) {
    throw "expected name column, got: $($rows[0].Cells -join '|')"
}

$layout = New-ShellListColumnLayout -Preset MenuList
$built = Build-ShellSingleSelectListRowCache -Rows $rows -ColumnLayout $layout
if ([string]::IsNullOrWhiteSpace($built.RowCache[0].BodyPlain)) {
    throw 'BodyPlain should not be empty'
}

$spec = Build-ShellSingleSelectListRowSpec -RowCacheEntry $built.RowCache[0] -Selected $false `
    -NumWidth 2 -DisplayNumber 1 -Gap $built.ColGap
if ($spec.Segments.Count -lt 2) {
    throw "expected body segments, got $($spec.Segments.Count)"
}

$handlers = New-ShellSingleSelectListDrawHandlers -RowCache $built.RowCache -ColGap $built.ColGap
$label = & $handlers['GetLabel'] $rows[0] 0
if ([string]::IsNullOrWhiteSpace($label)) {
    throw 'GetLabel returned empty'
}

Write-Host 'NODE MENU DRAW OK'
