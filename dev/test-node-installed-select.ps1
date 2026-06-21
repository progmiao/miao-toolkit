$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$toolRoot = Join-Path $root 'package\tools\node'
$coreLib = Join-Path $toolRoot '..\..\core\lib'

. (Join-Path $coreLib 'bootstrap\Load-Core.ps1') -LibDirectory $coreLib
Initialize-Paths -BinDirectory (Join-Path $root 'package\bin')
. (Join-Path $toolRoot 'lib\node-installed-select.ps1')
Import-NodeInstalledSelectCore -CoreLib $coreLib
. (Join-Path $toolRoot 'lib\volta-node.ps1')
Set-NodeVoltaToolRoot -ToolRoot $toolRoot

$items = @(
    (New-NodeVersionMenuItem -Version '20.11.0')
    (New-NodeVersionMenuItem -Version '18.19.0')
)
$map = @{ '20.11.0' = $true; '18.19.0' = $true }
$rows = Build-NodeInstalledVersionRows -Items $items -InstalledMap $map `
    -DefaultVersion '20.11.0' -ActiveVersion '20.11.0'

if ($rows.Count -ne 2) { throw "expected 2 rows, got $($rows.Count)" }
if ($rows[0].Cells.Count -ne 2) { throw 'expected 2 cells per row' }
if ([string]$rows[0].SearchKey -ne '20.11.0') { throw 'unexpected search key' }
if ($rows[0].Cells[0] -ne '20.11.0') { throw 'unexpected version cell' }
if ([string]$rows[0].Cells[1] -notmatch '\[') { throw 'expected status tags in cell' }

Write-Host 'test-node-installed-select: OK'
