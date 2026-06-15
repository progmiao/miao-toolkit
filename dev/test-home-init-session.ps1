$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$lib = Join-Path $root 'package\core\lib'
. (Join-Path $lib 'bootstrap\Load-Core.ps1') -LibDirectory $lib
Initialize-Paths -BinDirectory (Join-Path $root 'package\bin')

Clear-ToolkitSessionInitState

$sw = [Diagnostics.Stopwatch]::StartNew()
$v1 = Test-ToolkitInitValid
$t1 = $sw.ElapsedMilliseconds

$sw.Restart()
$v2 = Test-ToolkitInitValid
$t2 = $sw.ElapsedMilliseconds

$sw.Restart()
$ready1 = Test-ToolkitSessionInitReady
$tReady1 = $sw.ElapsedMilliseconds

$sw.Restart()
$ready2 = Test-ToolkitSessionInitReady
$tReady2 = $sw.ElapsedMilliseconds

if ($v1 -ne $v2) { throw 'init valid mismatch between calls' }
if ($ready1 -ne $ready2) { throw 'session ready mismatch between calls' }

Write-Output "initValid=$v1"
Write-Output "Test-ToolkitInitValid(1st)=${t1}ms (2nd)=${t2}ms"
Write-Output "Test-ToolkitSessionInitReady(1st)=${tReady1}ms (2nd)=${tReady2}ms"

if ($t2 -gt 5) { throw "expected memoized init valid under 5ms, got ${t2}ms" }
if ($tReady2 -gt 2) { throw "expected memoized session ready under 2ms, got ${tReady2}ms" }

$null = Sync-ToolkitSessionInitState -Refresh
$bundleOk = Initialize-ToolkitHomeBundle
if (-not (Test-ToolkitSessionInitReady)) {
    Write-Output 'SKIP home bundle: init not valid'
    Write-Output 'SESSION INIT MEMO OK'
    exit 0
}

if (-not $bundleOk) { throw 'Initialize-ToolkitHomeBundle failed' }
if ($null -eq $script:ToolkitToolsMemoryCache) { throw 'tools memory cache not warmed' }
if ($null -eq $script:ToolkitHomeRowsPayloadCache) { throw 'home rows payload not warmed' }

Write-Output 'HOME BUNDLE OK'
Write-Output 'SESSION INIT MEMO OK'
