$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$lib = Join-Path $root 'package\core\lib'
. (Join-Path $lib 'bootstrap\Load-Core.ps1') -LibDirectory $lib
Initialize-Paths -BinDirectory (Join-Path $root 'package\bin')

$sw = [Diagnostics.Stopwatch]::StartNew()
Import-MiaoModule -Name Tool
$tImport = $sw.ElapsedMilliseconds

$null = Sync-ToolkitSessionInitState -Refresh
$initReady = Test-ToolkitSessionInitReady
Write-Output "initReady=$initReady importToolMs=$tImport"

$tools = @(Discover-Tools)
foreach ($toolId in @('node', 'pnpm', 'yarn', 'claude-code')) {
    $tool = $tools | Where-Object { $_.id -eq $toolId } | Select-Object -First 1
    if (-not $tool) { continue }

    $cfg = Get-Content -Raw (Join-Path $tool._root 'index.json') -Encoding UTF8 | ConvertFrom-Json
    $actions = @($cfg.actions)

    $sw.Restart()
    $cacheInstalled = Get-ToolDepInstalledRecord -Tool $tool
    $tCache = $sw.ElapsedMilliseconds

    $sw.Restart()
    $depInstalled = $cacheInstalled
    $menuItems = @(Get-ToolMenuItems -BusinessActions $actions -Tool $tool -DepInstalled $depInstalled)
    $tMenu = $sw.ElapsedMilliseconds

    $state = Get-ToolkitToolInitStateForTool -Tool $tool
    $stateText = if ($state) { "initInstalled=$($state.installed)" } else { 'initState=missing' }

    Write-Output "$toolId cache=$cacheInstalled cacheMs=$tCache menuMs=$tMenu $stateText items=$($menuItems.Count)"
}
