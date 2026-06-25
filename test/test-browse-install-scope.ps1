$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$coreLib = Join-Path $root 'package\core\lib'
. (Join-Path $coreLib 'bootstrap\Load-Core.ps1') -LibDirectory $coreLib

foreach ($name in @(
        'Redraw-PaginatedMenuPage'
        'Update-PaginatedMenuSelection'
        'Show-ShellMultiSelectListMenu'
        'Invoke-ToolkitShellList'
    )) {
    if (-not (Get-Command $name -Scope Global -ErrorAction SilentlyContinue)) {
        throw "expected global function: $name"
    }
}

# 模拟 browse-install 子脚本：仅 global + 按需 dot-source Console-Menu
$child = {
    param($CoreLib)
    if (-not (Get-Command Redraw-PaginatedMenuPage -ErrorAction SilentlyContinue)) {
        . (Join-Path $CoreLib 'config\I18n.ps1')
        . (Join-Path $CoreLib 'config\ListLayout.ps1')
        . (Join-Path $CoreLib 'ui\console\Console-Menu.ps1')
    }
    . (Join-Path $CoreLib 'ui\shell\MultiSelectList.ps1')
    Initialize-ShellMultiSelectListDependencies
    $cmd = Get-ShellMultiSelectMenuCommand 'Redraw-PaginatedMenuPage'
    if (-not $cmd) { throw 'Redraw command missing' }
}.GetNewClosure()

& $child $coreLib

Write-Host 'test-browse-install-scope: OK'
