$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$lib = Join-Path $root 'package\core\lib'
. (Join-Path $lib 'bootstrap\Load-Core.ps1') -LibDirectory $lib
. (Join-Path $lib 'config\Paths.ps1')
Initialize-Paths -BinDirectory (Join-Path $root 'package\bin')
Import-MiaoModule -Name Tool
$coreLib = Join-Path $root 'package\core\lib'
foreach ($rel in @(
        'ui\shell\DepOperationView.ps1'
        'ui\shell\ToolkitDepBatchOperation.ps1'
    )) {
    . (Join-Path $coreLib $rel)
}

function Test-DepClosureOrderBug {
    param([switch]$FixedOrder)

    $ui = New-ToolkitDepOperationUiState
    $ui.ItemInFlight = $true

    if (-not $FixedOrder) {
        $onOutputLine = {
            $wingetOutputState['WingetOutputSeen'] = $true
        }.GetNewClosure()
        $wingetOutputState = @{ WingetOutputSeen = $false }
    }
    else {
        $wingetOutputState = @{ WingetOutputSeen = $false }
        $onOutputLine = {
            $wingetOutputState['WingetOutputSeen'] = $true
        }.GetNewClosure()
    }

    & $onOutputLine
    return [bool]$wingetOutputState['WingetOutputSeen']
}

$brokenFailed = $false
try { $null = Test-DepClosureOrderBug } catch { $brokenFailed = $true }
if (-not $brokenFailed) { throw 'broken closure order should throw' }
if (-not (Test-DepClosureOrderBug -FixedOrder)) { throw 'fixed closure order should update state' }

Write-Host 'test-closure-order: OK'
