$ErrorActionPreference = 'Stop'
$lib = Join-Path (Split-Path $PSScriptRoot -Parent) 'package\core\lib'
. (Join-Path $lib 'bootstrap\Load-Core.ps1') -LibDirectory $lib

$required = @(
    'Get-ShellListRowDisplayNumber'
    'Resolve-ShellListLayout'
    'ConvertTo-ShellListSelectResult'
    'Invoke-ToolkitShellList'
    'Invoke-ToolkitShellListSingleCore'
    'New-ToolkitMenuHeader'
    'Show-PaginatedMenu'
)

foreach ($name in $required) {
    if (-not (Get-Command $name -Scope Global -ErrorAction SilentlyContinue)) {
        throw "Missing global function: $name"
    }
}

Write-Host 'test-shell-list-globals: OK'
