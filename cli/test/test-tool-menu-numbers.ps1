$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$coreLib = Join-Path $root 'package\core\lib'

. (Join-Path $coreLib 'bootstrap\Load-Core.ps1') -LibDirectory $coreLib
Initialize-Paths -BinDirectory (Join-Path $root 'package\bin')

$tools = @(Discover-Tools)
if ($tools.Count -lt 4) { throw "expected at least 4 bundled tools, got $($tools.Count)" }

$common = @($tools | Where-Object { [string]$_.command -eq 'common' } | Select-Object -First 1)
$node = @($tools | Where-Object { [string]$_.command -eq 'node' } | Select-Object -First 1)
$pnpm = @($tools | Where-Object { [string]$_.command -eq 'pnpm' } | Select-Object -First 1)
$yarn = @($tools | Where-Object { [string]$_.command -eq 'yarn' } | Select-Object -First 1)
if ($common.Count -eq 0 -or $node.Count -eq 0 -or $pnpm.Count -eq 0 -or $yarn.Count -eq 0) {
    throw 'expected common, node, pnpm, yarn in Discover-Tools'
}

if ([int]$common.no -ne 1) { throw "expected common menu no=1, got $($common.no)" }
if ([int]$node.no -ne 2) { throw "expected node menu no=2, got $($node.no)" }
if ([int]$pnpm.no -ne 3) { throw "expected pnpm menu no=3, got $($pnpm.no)" }
if ([int]$yarn.no -ne 4) { throw "expected yarn menu no=4, got $($yarn.no)" }

if ([int]$common.sortOrder -ne 1) { throw "expected common sortOrder=1, got $($common.sortOrder)" }
if ([int]$node.sortOrder -ne 2) { throw "expected node sortOrder=2, got $($node.sortOrder)" }
if ([int]$pnpm.sortOrder -ne 3) { throw "expected pnpm sortOrder=3, got $($pnpm.sortOrder)" }
if ([int]$yarn.sortOrder -ne 4) { throw "expected yarn sortOrder=4, got $($yarn.sortOrder)" }

if ([string]$node.origin -ne 'bundled') { throw 'expected node origin=bundled' }

$assigned = @(Assign-ToolMenuNumbers -Tools @(
    [pscustomobject]@{ command = 'z-ext'; enabled = $true; origin = 'external'; sortOrder = 0 }
    [pscustomobject]@{ command = 'node'; enabled = $true; origin = 'bundled'; sortOrder = 2 }
))
if ([int](@($assigned | Where-Object { $_.command -eq 'node' }).no) -ne 1) {
    throw 'Assign-ToolMenuNumbers should keep bundled before external'
}
if ([int](@($assigned | Where-Object { $_.command -eq 'z-ext' }).no) -ne 2) {
    throw 'Assign-ToolMenuNumbers should place external after bundled'
}

Write-Host 'test-tool-menu-numbers: OK'
