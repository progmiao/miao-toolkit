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

$nodeEntry = Join-Path $node._root $node.entry
if (-not (Test-Path $nodeEntry)) {
    Write-Host "FAIL: node entry missing from cache path: $nodeEntry"
    exit 1
}

$staleRoot = Join-Path (Get-ToolsRoot) 'node'
$staleNode = [pscustomobject]@{
    id      = 'node'
    command = 'node'
    entry   = 'index.ps1'
    _root   = $staleRoot
}
$refreshed = @(Sync-ToolkitToolsLivePaths -Tools @($staleNode))
$refreshedEntry = Join-Path $refreshed[0]._root $refreshed[0].entry
if (-not (Test-Path $refreshedEntry)) {
    Write-Host "FAIL: stale _root not refreshed: $refreshedEntry"
    exit 1
}

$fingerprint = New-ToolkitInitFingerprint
if ([string]::IsNullOrWhiteSpace($fingerprint)) {
    Write-Host 'FAIL: init fingerprint should not be empty'
    exit 1
}

$manifest = Get-ToolkitInitManifest
if (-not $manifest -or [string]::IsNullOrWhiteSpace([string]$manifest.fingerprint)) {
    Write-Host 'FAIL: init manifest fingerprint missing'
    exit 1
}

$locale = Get-CurrentLocale
$homeRowsPath = Get-ToolkitInitHomeRowsPath -Locale $locale
$homeRowsPayload = Get-Content -Raw -Path $homeRowsPath -Encoding UTF8 | ConvertFrom-Json
$diskRows = Get-ToolkitDiskListRowCache -CacheKey 'Home' -Locale $locale `
    -LayoutKey ([string]$homeRowsPayload.layoutKey) `
    -RowsKey ([string]$homeRowsPayload.rowsKey)
if (-not $diskRows) {
    Write-Host 'FAIL: home row cache missing'
    exit 1
}

Write-Host 'TOOLKIT CACHE OK'
