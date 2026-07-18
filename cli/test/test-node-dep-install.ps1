$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$toolRoot = Join-Path $root 'package\tools\01-node'
$config = Get-Content -Raw (Join-Path $toolRoot 'index.json') -Encoding UTF8 | ConvertFrom-Json

$mainParams = @{
    Config     = $config
    ToolRoot   = $toolRoot
    PageSize   = 10
    ViewHeight = 20
    ToolkitShell = $null
}

# Load like index.ps1 without full miao - dot main with shell from Initialize
$lib = Join-Path $root 'package\core\lib'
$bin = Join-Path $root 'package\bin'
. (Join-Path $lib 'bootstrap\Load-Core.ps1') -LibDirectory $lib
. (Join-Path $lib 'config\Paths.ps1')
Initialize-Paths -BinDirectory $bin
Initialize-Console
Import-MiaoModule -Name Tool

$mainParams.ToolkitShell = Initialize-ToolkitShell
$tool = Get-ToolFromDirectory -ToolRoot $toolRoot

try {
    $action = @($config.actions | Where-Object { $_.command -eq 'install' } | Select-Object -First 1)
    if (-not $action) { throw 'no install action in index.json' }
    $depResult = Invoke-ToolDependencyMenuAction -Tool $tool -Action $action -Shell $mainParams.ToolkitShell
    Write-Host "dep-result: $depResult"
}
catch {
    Write-Host "FAIL $($_.Exception.GetType().FullName) $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
    exit 1
}
