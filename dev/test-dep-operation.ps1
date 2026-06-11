$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$lib = Join-Path $root 'package\core\lib'
$bin = Join-Path $root 'package\bin'

. (Join-Path $lib 'bootstrap\Load-Core.ps1') -LibDirectory $lib
. (Join-Path $lib 'config\Paths.ps1')
Initialize-Paths -BinDirectory $bin
Import-MiaoModule -Name Install

$toolRoot = Join-Path $root 'package\tools\node'
$tool = Get-ToolFromDirectory -ToolRoot $toolRoot

$plan = Build-ToolDepSyncPlan -Tool $tool -Intent install
Write-Host "Plan items: $($plan.Items.Count)"
foreach ($item in $plan.Items) {
    Write-Host "  $($item.Status.Name) -> $($item.Status.Action) execute=$($item.ShouldExecute)"
}

$names = @(
    'Resolve-ToolDepPackageStatus'
    'Build-ToolDepSyncPlan'
    'Start-ToolkitDepOperation'
    'Invoke-ToolkitDepOperationView'
    'Set-ToolDepPackageVersion'
)
foreach ($name in $names) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        throw "Missing function: $name"
    }
}

Write-Host 'test-dep-operation: OK'
