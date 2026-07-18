$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$lib = Join-Path $root 'package\core\lib'
. (Join-Path $lib 'bootstrap\Load-Core.ps1') -LibDirectory $lib
Initialize-Paths -BinDirectory (Join-Path $root 'package\bin')

$shell = Initialize-ToolkitShell -Force
if (-not $shell.BrandDrawn) {
    throw 'expected brand drawn after init'
}

$brandEnd = Get-ToolkitShellBrandEndRow -Shell $shell
if ($brandEnd -le 0) {
    throw "expected positive brand end row, got $brandEnd"
}

if (-not (Test-ToolkitShellBrandRowWriteBlocked -Row 0 -Shell $shell)) {
    throw 'expected brand row 0 to be protected'
}
if (-not (Test-ToolkitShellBrandRowWriteBlocked -Row ($brandEnd - 1) -Shell $shell)) {
    throw 'expected last brand row to be protected'
}
if (Test-ToolkitShellBrandRowWriteBlocked -Row $brandEnd -Shell $shell) {
    throw 'expected content row not to be protected'
}

$script:ToolkitShellBrandDrawing = $true
if (Test-ToolkitShellBrandRowWriteBlocked -Row 0 -Shell $shell) {
    throw 'brand drawing flag should allow writes'
}
$script:ToolkitShellBrandDrawing = $false

if (Test-ConsoleBufferDrawAvailable) {
    Repair-ToolkitShellBrandPanelTextRows -Shell $shell
}

Write-Host 'BRAND ROW PROTECTION OK'
