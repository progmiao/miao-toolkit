$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$lib = Join-Path $root 'package\core\lib'
. (Join-Path $lib 'bootstrap\Load-Core.ps1') -LibDirectory $lib
Initialize-Paths -BinDirectory (Join-Path $root 'package\bin')

Import-MiaoModule -Name Tool

$tools = @(Discover-Tools)
$node = $tools | Where-Object { $_.command -eq 'node' } | Select-Object -First 1
if (-not $node) { throw 'node tool missing' }

if (-not (Get-Command Get-ToolDepInstalledRecord -ErrorAction SilentlyContinue)) {
    throw 'Get-ToolDepInstalledRecord missing'
}

$sw = [Diagnostics.Stopwatch]::StartNew()
$fromRecord = Get-ToolDepInstalledRecord -Tool $node
$recordMs = $sw.ElapsedMilliseconds
if ($recordMs -gt 150) {
    throw "Get-ToolDepInstalledRecord too slow: ${recordMs}ms"
}

$state = Get-ToolkitToolInitStateForTool -Tool $node
if (-not $state) {
    Write-Host 'SKIP: init tool state unavailable (init not built)'
    Write-Host 'test-tool-dep-record: OK'
    exit 0
}

$expected = [bool]$state.installed
if ($fromRecord -ne $expected) {
    throw "record installed=$fromRecord init installed=$expected"
}

Set-ToolDepInstalledSessionCache -Tool $node -Installed $false
if (Get-ToolDepInstalledRecord -Tool $node) {
    throw 'session record override should mark not installed'
}
Clear-ToolDepInstalledSessionCache -ToolId $node.id

Write-Host "recordMs=$recordMs initInstalled=$expected"
Write-Host 'test-tool-dep-record: OK'
