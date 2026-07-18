$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$lib = Join-Path $root 'package\core\lib'
. (Join-Path $lib 'bootstrap\Load-Core.ps1') -LibDirectory $lib
. (Join-Path $lib 'config\Paths.ps1')
Initialize-Paths -BinDirectory (Join-Path $root 'package\bin')
Import-MiaoModule -Name Tool

$toolRoot = Join-Path $root 'package\tools\01-node'
$coreLib = Join-Path $toolRoot '..\..\core\lib'
foreach ($rel in @(
        'domain\Ensure-ToolDeps.ps1'
        'domain\Invoke-ToolkitDepOperation.ps1'
        'ui\shell\DepOperationView.ps1'
        'ui\shell\ToolkitDepBatchOperation.ps1'
    )) {
    . (Join-Path $coreLib $rel)
}

$shell = Initialize-ToolkitShell
$config = Get-Content (Join-Path $toolRoot 'index.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$mainParams = @{
    Config       = $config
    ToolRoot     = $toolRoot
    ToolkitShell = $shell
    PageSize     = 20
    ViewHeight   = 30
}

try {
    $tool = Get-ToolFromDirectory -ToolRoot $toolRoot
    $menuItems = @(Get-ToolMenuItems -BusinessActions @($config.actions) -Tool $tool)
    $depAction = $menuItems | Where-Object { $_.command -eq 'install' } | Select-Object -First 1
    if (-not $depAction) { throw 'install action not found' }
    Write-Host "Invoking dep install action..."
    $result = Invoke-ToolDependencyMenuAction -Tool $tool -Action $depAction -Shell $shell -SectionTitle 'test'
    Write-Host "Result: $result"
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
    exit 1
}
