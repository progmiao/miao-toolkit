$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$lib = Join-Path $root 'package\core\lib'
. (Join-Path $lib 'bootstrap\Load-Core.ps1') -LibDirectory $lib
Initialize-Paths -BinDirectory (Join-Path $root 'package\bin')

Clear-ToolkitInitDirectory
Reset-ToolkitToolsMemoryCache

if (Test-ToolkitInitValid) {
    Write-Host 'FAIL: init should be invalid after clear'
    exit 1
}

Invoke-ToolkitInitBuild | Out-Null

if (-not (Test-ToolkitInitValid)) {
    Write-Host 'FAIL: init should be valid after build'
    exit 1
}

$brand = Get-ToolkitBrandSnapshot
if (-not $brand) {
    Write-Host 'FAIL: brand snapshot missing'
    exit 1
}

$toolState = Get-ToolkitToolInitStateMap
if ($toolState.Count -lt 1) {
    Write-Host 'FAIL: tools-state missing'
    exit 1
}

$tools = @(Get-ToolkitTools)
if ($tools.Count -lt 1) {
    Write-Host 'FAIL: expected tools from cache'
    exit 1
}

$node = Get-Tool 'node' -Tools $tools
if (-not $node) {
    Write-Host 'FAIL: Get-Tool node from cache'
    exit 1
}

$diskRows = Get-ToolkitDiskListRowCache -CacheKey 'Home' -LayoutKey 'ToolList' -RowsKey (Get-ShellListRowsCacheKey -Rows (Get-HomeToolListRows -Tools $tools))
if (-not $diskRows) {
    Write-Host 'FAIL: home row cache missing'
    exit 1
}

Write-Host 'TOOLKIT CACHE OK'
