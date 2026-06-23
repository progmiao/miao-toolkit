$ErrorActionPreference = 'Stop'
$lib = Join-Path (Split-Path $PSScriptRoot -Parent) 'package\core\lib'
. (Join-Path $lib 'bootstrap\Load-Core.ps1') -LibDirectory $lib
Initialize-Paths -BinDirectory (Join-Path (Split-Path $PSScriptRoot -Parent) 'package\bin')

$shell = Initialize-ToolkitShell -Force
if ($shell -is [System.Array]) {
    throw "Initialize-ToolkitShell returned array (count=$($shell.Count))"
}
if ($shell -isnot [hashtable]) {
    throw "Initialize-ToolkitShell returned $($shell.GetType().FullName)"
}

Write-Host 'SHELL INIT TYPE OK'
