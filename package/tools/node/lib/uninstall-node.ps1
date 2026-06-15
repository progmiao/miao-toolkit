# node — 卸载已安装的 Node 版本（Shell 多选入口）

param(
    [hashtable]$ToolkitShell = $null,

    [int]$PageSize = 0,
    [int]$ViewHeight = 0
)

$ErrorActionPreference = 'Stop'

$entry = Join-Path $PSScriptRoot 'browse-uninstall.ps1'
& $entry @PSBoundParameters
exit $(if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE })
