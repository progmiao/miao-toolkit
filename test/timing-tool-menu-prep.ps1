$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$lib = Join-Path $root 'package\core\lib'
. (Join-Path $lib 'bootstrap\Load-Core.ps1') -LibDirectory $lib
Initialize-Paths -BinDirectory (Join-Path $root 'package\bin')
Import-MiaoModule -Name Tool

$tools = @(Discover-Tools)
Write-Output "discovered=$($tools.Count)"
foreach ($t in $tools) {
    Write-Output "  id=$($t.id) command=$($t.command)"
}

$targets = @('node', 'pnpm', 'yarn', 'claude-code')

foreach ($toolId in $targets) {
    $tool = $tools | Where-Object { $_.id -eq $toolId -or $_.command -eq $toolId } | Select-Object -First 1
    if (-not $tool) {
        Write-Output "$toolId missing"
        continue
    }

    $cfgPath = Join-Path $tool._root 'index.json'
    $cfg = Get-Content -Raw -Path $cfgPath -Encoding UTF8 | ConvertFrom-Json
    $actions = @($cfg.actions)

    $sw = [Diagnostics.Stopwatch]::StartNew()
    $depInstalled = Get-ToolDepInstalled $tool
    $tDep = $sw.ElapsedMilliseconds

    $sw.Restart()
    $updateAvailable = $false
    $ref = [ref]$updateAvailable
    $null = Update-ToolDependencyMenuProbe -Tool $tool -Shell @{} -UpdateMenuAvailable $ref `
        -AllowProbeSync:$false -DepInstalled $depInstalled
    $tProbe = $sw.ElapsedMilliseconds

    $sw.Restart()
    $menuItems = @(Get-ToolMenuItems -BusinessActions $actions -Tool $tool `
        -DependencyUpdateAvailable:$updateAvailable -DepInstalled $depInstalled)
    $tMenu = $sw.ElapsedMilliseconds

    $sw.Restart()
    $rows = ConvertTo-ToolMenuListRows -ToolRoot $tool._root -MenuItems $menuItems
    $tRows = $sw.ElapsedMilliseconds

    Write-Output "$toolId dep=$depInstalled depMs=$tDep probeMs=$tProbe menuMs=$tMenu rowsMs=$tRows items=$($menuItems.Count)"
}
