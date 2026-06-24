$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$lib = Join-Path $root 'package\core\lib'
. (Join-Path $lib 'bootstrap\Load-Core.ps1') -LibDirectory $lib
Initialize-Paths -BinDirectory (Join-Path $root 'package\bin')

Import-MiaoModule -Name Init

foreach ($name in @(
        'Initialize-ToolkitDepBatchOperationView'
        'Initialize-ToolkitBatchExecutionView'
        'Invoke-ToolkitDepBatchOperationWaitLoop'
        'Draw-ToolkitDepOperationView'
    )) {
    if (-not (Get-Command $name -Scope Global -ErrorAction SilentlyContinue)) {
        throw "global export missing: $name"
    }
}

Write-Host 'test-import-init-exports: OK'
