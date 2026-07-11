# node — 一级功能菜单（委托 core Invoke-ToolActionMenu）

param(
    [Parameter(Mandatory = $true)]
    $Config,

    [Parameter(Mandatory = $true)]
    [string]$ToolRoot,

    [hashtable]$ToolkitShell = $null,

    [int]$PageSize = 0,
    [int]$ViewHeight = 0,
    [switch]$LtsOnly
)

$ErrorActionPreference = 'Stop'

$coreLib = Join-Path $ToolRoot '..\..\core\lib'
if (-not (Get-Command Invoke-ToolActionMenu -CommandType Function -ErrorAction SilentlyContinue)) {
    . (Join-Path $coreLib 'ui\shell\ToolActionMenu.ps1')
}

$actionScriptParams = @{}
if ($LtsOnly.IsPresent) {
    $actionScriptParams['LtsOnly'] = $true
}

return Invoke-ToolActionMenu -Config $Config -ToolRoot $ToolRoot `
    -ToolkitShell $ToolkitShell -PageSize $PageSize -ViewHeight $ViewHeight `
    -ActionScriptParams $actionScriptParams
