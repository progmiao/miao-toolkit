# 嵌套脚本进入工具页：不重复 dot-source core，复用父会话已 Import 的 Tool 模块
$ErrorActionPreference = 'Stop'
$lib = Join-Path (Split-Path $PSScriptRoot -Parent) 'package\core\lib'
. (Join-Path $lib 'bootstrap\Load-Core.ps1') -LibDirectory $lib
Initialize-Paths -BinDirectory (Join-Path (Split-Path $PSScriptRoot -Parent) 'package\bin')
$env:MIAO_SKIP_DEPS = '1'
Import-MiaoModule -Name Tool

$child = {
    param($ToolRoot)
    Initialize-PathsFromToolRoot -ToolRoot $ToolRoot
    $config = Get-Content (Join-Path $ToolRoot 'index.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $tool = Get-ToolFromDirectory -ToolRoot $ToolRoot
    $menuItems = @(Get-ToolMenuItems -BusinessActions @($config.actions) -Tool $tool)
    $rows = ConvertTo-ToolMenuListRows -ToolRoot $ToolRoot -MenuItems $menuItems
    $layout = New-ShellListColumnLayout -Preset MenuList
    $normalized = @(Normalize-ShellListRows -Rows $rows -ColumnLayout $layout)
    $built = Get-ShellSingleSelectListRowCache -Shell @{} -CacheKey 'Node' -Rows $normalized -ColumnLayout $layout
    $handlers = New-ShellSingleSelectListDrawHandlers -RowCache $built.RowCache -ColGap $built.ColGap
    & $handlers['GetLabel'] $normalized[0] 0 | Out-Null
}

$toolRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'package\tools\01-node'
& $child $toolRoot
Write-Host 'NESTED TOOL LIST OK'
