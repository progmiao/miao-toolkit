# test-batch-execution.ps1 — 批量执行组件入口与 API 别名

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$lib = Join-Path $root 'package\core\lib'
. (Join-Path $lib 'bootstrap\Load-Core.ps1') -LibDirectory $lib
Initialize-Paths -BinDirectory (Join-Path $root 'package\bin')

. (Join-Path $lib 'ui\shell\BatchExecution.ps1')

foreach ($name in @(
        'Initialize-ToolkitBatchExecutionView'
        'Invoke-ToolkitBatchExecutionWaitLoop'
        'Start-ToolkitBatchExecution'
        'Clear-ToolkitBatchExecutionView'
        'Set-ToolkitBatchExecutionCompleteUi'
        'Draw-ToolkitBatchExecutionView'
        'Initialize-ToolkitDepBatchOperationView'
        'Draw-ToolkitDepOperationView'
    )) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        throw "missing command: $name"
    }
}

$brandW = 48
$barSingle = Format-ToolkitDepProgressBar -Total 1 -BrandInnerWidth $brandW -ItemIndex 1 -ItemSubPercent 45
if ($barSingle -match '\d/\s*\d') {
    throw "single-item progress bar should not show x/x suffix, got: [$barSingle]"
}
if ($barSingle -notmatch ' 45%$') {
    throw "single-item progress bar should end with percent only, got: [$barSingle]"
}

$barMulti = Format-ToolkitDepProgressBar -Total 2 -BrandInnerWidth $brandW -ItemIndex 1 -ItemSubPercent 45
if ($barMulti -notmatch ' 1/ 2$') {
    throw "multi-item progress bar should show count suffix, got: [$barMulti]"
}

Write-Host 'test-batch-execution: OK'
