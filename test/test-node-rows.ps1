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

foreach ($row in $rows) {
    Write-Host ("Num=$($row.Number) Cells=[$($row.Cells -join '|')]")
}

$layout = New-ShellListColumnLayout -Preset MenuList
Write-Host "Widths=$($layout.Widths -join ',')"
$built = Build-ShellSingleSelectListRowCache -Rows $rows -ColumnLayout $layout
foreach ($part in $built.RowCache) {
    Write-Host "BodyPlain=[$($part.BodyPlain)] Segments=$($part.BodySegments.Count)"
}

Write-Host 'NODE ROWS OK'
