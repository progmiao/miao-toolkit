# claude-code — 一级功能菜单（委托 core Invoke-ToolActionMenu）

param(
    $Config = $null,
    [string]$ToolRoot = '',
    [hashtable]$ToolkitShell = $null,
    [int]$PageSize = 0,
    [int]$ViewHeight = 0
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ToolRoot)) {
    $ToolRoot = Split-Path $PSScriptRoot -Parent
}

if (-not $Config) {
    $configPath = Join-Path $ToolRoot 'index.json'
    $Config = Get-Content -Raw -Path $configPath -Encoding UTF8 | ConvertFrom-Json
}

$coreLib = Join-Path $ToolRoot '..\..\core\lib'
. (Join-Path $coreLib 'ui\shell\ToolActionMenu.ps1')

return Invoke-ToolActionMenu -Config $Config -ToolRoot $ToolRoot `
    -ToolkitShell $ToolkitShell -PageSize $PageSize -ViewHeight $ViewHeight
