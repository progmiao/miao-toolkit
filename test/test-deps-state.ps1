$ErrorActionPreference = 'Stop'
$lib = Join-Path (Split-Path $PSScriptRoot -Parent) 'package\core\lib'
. (Join-Path $lib 'bootstrap\Load-Core.ps1') -LibDirectory $lib
Initialize-Paths -BinDirectory (Join-Path (Split-Path $PSScriptRoot -Parent) 'package\bin')

Import-MiaoModule -Name Install

foreach ($n in @(
        'Get-ToolDepInstalled'
        'Get-ToolDependencyStatus'
        'Start-ToolboxDepInstallSession'
        'Invoke-InstallPage'
        'Set-ToolDepInstalled'
        'Set-GlobalDepPackageVersion'
        'Get-GlobalDepRecordedVersion'
    )) {
    if (-not (Get-Command $n -ErrorAction SilentlyContinue)) {
        Write-Host "MISSING: $n"
        exit 1
    }
    Write-Host "OK: $n"
}

$tools = @(Discover-Tools)
$node = $tools | Where-Object { $_.command -eq 'node' } | Select-Object -First 1
if (-not $node) { throw 'node tool not discovered' }

Write-Host "node no=$($node.no) command=$($node.command) dir=$($node._dirName)"
Write-Host "node status (no state): $(Get-ToolDependencyStatus -Tool $node) (volta on PATH: $(Test-ToolDepCommandAvailable -CheckCommand 'volta --version'))"

$env:MIAO_CONFIG = Join-Path $env:TEMP 'miao-test-deps'
if (-not (Test-Path $env:MIAO_CONFIG)) {
    New-Item -ItemType Directory -Path $env:MIAO_CONFIG -Force | Out-Null
}
Clear-DepsStateCache
Set-GlobalDepPackageVersion -Fingerprint 'winget:Volta.Volta' -Name 'volta' -Version '2.0.1'
Write-Host "node installed: $(Get-ToolDepInstalled -Tool $node)"
Write-Host "node status (with state): $(Get-ToolDependencyStatus -Tool $node)"

$pnpm = $tools | Where-Object { $_.command -eq 'pnpm' } | Select-Object -First 1
Write-Host "pnpm installed (shared volta): $(Get-ToolDepInstalled -Tool $pnpm)"

Remove-GlobalDepPackage -Fingerprint 'winget:Volta.Volta'
Write-Host "node status (after remove global record): $(Get-ToolDependencyStatus -Tool $node)"

Remove-Item -Recurse -Force $env:MIAO_CONFIG -ErrorAction SilentlyContinue
$env:MIAO_CONFIG = $null
Clear-DepsStateCache

Write-Host 'DEPS STATE OK'
