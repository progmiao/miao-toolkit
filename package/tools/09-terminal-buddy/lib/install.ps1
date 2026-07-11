# terminal-buddy — 安装（Gitee Release，含检测/更新）

param(
    [hashtable]$ToolkitShell = $null,
    $Action = $null,
    [int]$PageSize = 0,
    [int]$ViewHeight = 0
)

$ErrorActionPreference = 'Stop'
$toolRoot = Split-Path $PSScriptRoot -Parent
$coreLib = (Resolve-Path -LiteralPath (Join-Path $toolRoot '..\..\core\lib')).Path
if (-not (Get-Command Initialize-ToolkitDepBatchOperationView -ErrorAction SilentlyContinue)) {
    . (Join-Path $coreLib 'ui\shell\BatchExecution.ps1')
}

. (Join-Path $PSScriptRoot 'terminal-buddy-core.ps1')
. (Join-Path $PSScriptRoot 'terminal-buddy-action-title.ps1')
. (Join-Path $PSScriptRoot 'terminal-buddy-state.ps1')
. (Join-Path $PSScriptRoot 'manage-app.ps1')

$page = Initialize-TerminalBuddyActionPage -ToolRoot $toolRoot -ToolkitShell $ToolkitShell `
    -PageSize $PageSize -ViewHeight $ViewHeight
$shell = $page.Shell
$sectionTitle = Get-TerminalBuddyActionSectionTitle -ToolRoot $toolRoot -Action $Action `
    -ScriptLeaf 'install.ps1'

return Invoke-TerminalBuddyAppSyncPage -Shell $shell -SectionTitle $sectionTitle `
    -ToolRoot $toolRoot -CoreLib $page.CoreLib
