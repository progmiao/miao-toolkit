$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$lib = Join-Path $root 'package\core\lib'
$bin = Join-Path $root 'package\bin'

. (Join-Path $lib 'bootstrap\Load-Core.ps1') -LibDirectory $lib
. (Join-Path $lib 'config\Paths.ps1')
Initialize-Paths -BinDirectory $bin
Import-MiaoModule -Name ToolDeps

$needsUpgrade = Test-ToolDepPackageNeedsUpgrade -Package @{
    install = @{ packageId = 'Volta.Volta' }
    version = 'latest'
} -EffectiveVersion '' -ProbeCache @{}

if ($needsUpgrade) {
    throw 'empty EffectiveVersion should not need upgrade'
}

$lines = @([char]0x627E, [char]0x4E0D, [char]0x5230, [char]0x53EF, [char]0x7528, [char]0x7684, [char]0x5347, [char]0x7EA7, [char]0x3002 -join '')
$result = @{
    Success  = $false
    ExitCode = -1978335189
    Lines    = $lines
}
if (-not (Test-WingetDepResultIsAlreadyLatest $result)) {
    throw 'winget no-upgrade output should count as already latest'
}

Write-Host 'test-dep-plan-reconcile: OK'
