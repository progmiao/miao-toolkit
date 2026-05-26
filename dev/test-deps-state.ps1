$ErrorActionPreference = 'Stop'
$lib = Join-Path (Split-Path $PSScriptRoot -Parent) 'package\core\lib'
. (Join-Path $lib 'bootstrap\Load-Core.ps1') -LibDirectory $lib
Initialize-Paths -BinDirectory (Join-Path (Split-Path $PSScriptRoot -Parent) 'package\bin')

foreach ($n in @(
        'Test-ToolDepInstalled'
        'Get-ToolDependencyStatus'
        'Start-InstallDepsSession'
        'Invoke-InstallDepsPage'
        'Set-ToolDepInstalled'
        'Remove-ToolDepInstalled'
    )) {
    if (-not (Get-Command $n -ErrorAction SilentlyContinue)) {
        Write-Host "MISSING: $n"
        exit 1
    }
    Write-Host "OK: $n"
}

$tools = @(Discover-Tools)
$node = $tools | Where-Object { $_.id -eq 'node' } | Select-Object -First 1
Write-Host "node status (no state): $(Get-ToolDependencyStatus -Tool $node)"

$env:MIAO_CONFIG = Join-Path $env:TEMP 'miao-test-deps'
if (-not (Test-Path $env:MIAO_CONFIG)) {
    New-Item -ItemType Directory -Path $env:MIAO_CONFIG -Force | Out-Null
}
Clear-DepsStateCache
Set-ToolDepInstalled -ToolId 'node' -DependencyVersions @{ volta = '2.0.1' }
Write-Host "node installed: $(Test-ToolDepInstalled -Tool $node)"
Write-Host "node status (with state): $(Get-ToolDependencyStatus -Tool $node)"
Remove-ToolDepInstalled -ToolId 'node'
Write-Host "node status (after remove): $(Get-ToolDependencyStatus -Tool $node)"

Remove-Item -Recurse -Force $env:MIAO_CONFIG -ErrorAction SilentlyContinue
$env:MIAO_CONFIG = $null
Clear-DepsStateCache

Write-Host 'DEPS STATE OK'
