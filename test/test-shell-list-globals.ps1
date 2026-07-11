$ErrorActionPreference = 'Stop'
$lib = Join-Path (Split-Path $PSScriptRoot -Parent) 'package\core\lib'
. (Join-Path $lib 'bootstrap\Load-Core.ps1') -LibDirectory $lib

$required = @(
    'Get-ShellListRowDisplayNumber'
    'Resolve-ShellListLayout'
    'Resolve-ShellListPageSize'
    'Get-ShellListDefaultPageSize'
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

if ((Get-ShellListDefaultPageSize) -ne 20) {
    throw 'shell list default page size should be 20'
}
if ((Resolve-ShellListPageSize) -ne 20) {
    throw 'shell list page size should default to 20'
}
if ((Resolve-ShellListPageSize -PageSize 15) -ne 15) {
    throw 'shell list page size override should be honored'
}

$coreShellLib = Join-Path (Split-Path $PSScriptRoot -Parent) 'package\core\lib\ui\shell\Layout.ps1'
. $coreShellLib
$c = Get-ShellLayoutConstants
if ([int]$c.ListSlotRows -ne 20) {
    throw "shell list slot rows should be 20, got $($c.ListSlotRows)"
}

Write-Host 'test-shell-list-globals: OK'
