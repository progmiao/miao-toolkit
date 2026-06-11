$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent

$lib = Join-Path $root 'package\core\lib'

$bin = Join-Path $root 'package\bin'



. (Join-Path $lib 'bootstrap\Load-Core.ps1') -LibDirectory $lib

Initialize-Paths -BinDirectory $bin

Import-MiaoModule -Name ToolDeps



$toolRoot = Join-Path $root 'package\tools\node'

$tool = Get-ToolFromDirectory -ToolRoot $toolRoot

$businessActions = @((Get-Content -Raw (Join-Path $toolRoot 'index.json') -Encoding UTF8 | ConvertFrom-Json).actions)



$env:MIAO_CONFIG = Join-Path $env:TEMP 'miao-test-tool-menu'

if (-not (Test-Path $env:MIAO_CONFIG)) {

    New-Item -ItemType Directory -Path $env:MIAO_CONFIG -Force | Out-Null

}

Remove-ToolDepInstalled -ToolId 'node' -ErrorAction SilentlyContinue
Clear-DepsStateCache

$before = @(Get-ToolMenuItems -BusinessActions $businessActions -Tool $tool)

if ($before.Count -ne 1 -or -not (Test-ToolDependencyMenuAction $before[0])) {

    throw "Expected single install menu before state, got $($before.Count) items"

}

if ($before[0].command -ne 'install') {

    throw 'Only install-deps menu should show when install record is missing'

}



Set-ToolDepInstalled -ToolId 'node' -DependencyVersions @{ volta = '2.0.1' }

Clear-DepsStateCache

$voltaCheck = [string](@(Get-ToolDependencyPackages -Tool $tool)[0].checkCommand)
if ((Test-ToolDepCommandAvailable -CheckCommand $voltaCheck) `
        -and (Test-ToolDependencyNeedsImmediateLocalAttention -Tool $tool)) {
    throw 'latest-policy install record should not need immediate local attention when command is available'
}

$after = @(Get-ToolMenuItems -BusinessActions $businessActions -Tool $tool)

$expectedAfter = $businessActions.Count + 1

if ($after.Count -ne $expectedAfter) {

    throw "Expected business + uninstall menus after install, got $($after.Count) items"

}

if (Test-ToolDependencyMenuAction $after[0]) {

    throw 'First item should be a business action after install'

}

$updateOnlyMenus = @($after | Where-Object {
        (Test-ToolDependencyMenuAction $_) -and ($_.command -eq 'update')
    })
if ($updateOnlyMenus.Count -gt 0) {
    throw 'Update menu should not show when deps are satisfied locally'
}

if (-not ($after | Where-Object { Test-ToolDependencyMenuAction $_ -and $_.command -eq 'uninstall' })) {

    throw 'Expected uninstall menu after install'

}



$withUpdate = @(Get-ToolMenuItems -BusinessActions $businessActions -Tool $tool -DependencyUpdateAvailable)

if ($withUpdate.Count -ne ($businessActions.Count + 2)) {
    throw 'Expected business + uninstall + update when update is available'
}
$last = $withUpdate[$withUpdate.Count - 1]
if (-not (Test-ToolDependencyMenuAction $last) -or $last.command -ne 'update') {
    throw 'Update-deps menu should be appended after uninstall-deps'
}



Remove-ToolDepInstalled -ToolId 'node'

Remove-Item -Recurse -Force $env:MIAO_CONFIG -ErrorAction SilentlyContinue

$env:MIAO_CONFIG = $null

Clear-DepsStateCache



Write-Host 'test-tool-menu-items: OK'

