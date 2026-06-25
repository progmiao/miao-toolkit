$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$lib = Join-Path $root 'package\core\lib'
. (Join-Path $lib 'bootstrap\Load-Core.ps1') -LibDirectory $lib
Initialize-Paths -BinDirectory (Join-Path $root 'package\bin')
. (Join-Path $lib 'config\ToolkitInit.ps1')

$script:InitValidCallCount = 0
$original = Get-Command Test-ToolkitInitValid -CommandType Function
function Test-ToolkitInitValid {
    $script:InitValidCallCount++
    & $original
}

$tools = @(Get-ToolkitTools)
$shell = Initialize-ToolkitShell

$script:InitValidCallCount = 0
$sw = [Diagnostics.Stopwatch]::StartNew()
$rows = Get-HomeToolListRows -Tools $tools
$tRows = $sw.ElapsedMilliseconds

# simulate list cache path without interactive UI
$listLayout = New-ShellListLayout
$columnLayout = Resolve-ShellListLayoutColumnLayout -Layout $listLayout
$normalized = @(Normalize-ShellListRows -Rows $rows -Layout $listLayout)
$built = Get-ShellSingleSelectListRowCache -Shell $shell -CacheKey 'Home' -Rows $normalized -ColumnLayout $columnLayout
$tCache = $sw.ElapsedMilliseconds

Write-Output "Get-HomeToolListRows=${tRows}ms"
Write-Output "RowCachePath=${tCache}ms total"
Write-Output "Test-ToolkitInitValid calls=$script:InitValidCallCount"
Write-Output "RowCache entries=$($built.RowCache.Count)"
