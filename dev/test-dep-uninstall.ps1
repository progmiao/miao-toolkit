$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$lib = Join-Path $root 'package\core\lib'
$bin = Join-Path $root 'package\bin'

. (Join-Path $lib 'bootstrap\Load-Core.ps1') -LibDirectory $lib
Initialize-Paths -BinDirectory $bin
Import-MiaoModule -Name ToolDeps

$toolRoot = Join-Path $root 'package\tools\node'
$tool = Get-ToolFromDirectory -ToolRoot $toolRoot

$env:MIAO_CONFIG = Join-Path $env:TEMP 'miao-test-dep-uninstall'
if (-not (Test-Path $env:MIAO_CONFIG)) {
    New-Item -ItemType Directory -Path $env:MIAO_CONFIG -Force | Out-Null
}
Clear-DepsStateCache
Set-ToolDepInstalled -ToolId 'node' -DependencyVersions @{ volta = '2.0.1' }

$plan = Build-ToolDepSyncPlan -Tool $tool -Intent uninstall
$item = $plan.Items[0]
if ([string]$item.Status.Action -ne 'Skip' -and -not $item.Status.CommandAvailable) {
    Write-Host "note: uninstall action=$($item.Status.Action) commandAvailable=$($item.Status.CommandAvailable)"
}

$runner = New-ToolkitDepOperationRunner -Tool $tool -Plan $plan -Log (New-ToolkitDepOperationLog)
if ($item.ShouldExecute) {
    & $runner.ProcessItem $item
}

Complete-ToolkitDepUninstallRecord -Tool $tool -Runner $runner
if (Test-ToolDepInstalled -Tool $tool) {
    throw 'install record should be cleared after uninstall completes'
}

$removed = @{
    Success  = $false
    ExitCode = 1
    Lines    = @('No installed package found matching input criteria.')
}
if (-not (Test-WingetDepResultIsAlreadyRemoved $removed)) {
    throw 'winget already-removed output should count as removed'
}

Remove-Item -Recurse -Force $env:MIAO_CONFIG -ErrorAction SilentlyContinue
$env:MIAO_CONFIG = $null
Clear-DepsStateCache

$uninstallCmd = (Get-Command Invoke-ToolDepWingetUninstall).ScriptBlock.ToString()
if ($uninstallCmd -match 'accept-package-agreements') {
    throw 'winget uninstall must not pass install-only agreement flags'
}

Write-Host 'test-dep-uninstall: OK'
