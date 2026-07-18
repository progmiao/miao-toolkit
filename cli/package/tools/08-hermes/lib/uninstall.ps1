# hermes — 卸载 CLI（hermes uninstall --yes）

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

. (Join-Path $PSScriptRoot 'hermes-core.ps1')
. (Join-Path $PSScriptRoot 'hermes-action-title.ps1')
. (Join-Path $PSScriptRoot 'hermes-state.ps1')
. (Join-Path $PSScriptRoot 'hermes-progress.ps1')
. (Join-Path $PSScriptRoot 'hermes-batch.ps1')
. (Join-Path $PSScriptRoot 'manage-cli.ps1')

$page = Initialize-HermesActionPage -ToolRoot $toolRoot -ToolkitShell $ToolkitShell `
    -PageSize $PageSize -ViewHeight $ViewHeight
$shell = $page.Shell
$sectionTitle = Get-HermesActionSectionTitle -ToolRoot $toolRoot -Action $Action `
    -ScriptLeaf 'uninstall.ps1'

$blocked = Invoke-HermesCliRequiredNoticePage -Shell $shell -SectionTitle $sectionTitle `
    -ToolRoot $toolRoot -CacheKey 'HermesUninstallNotice'
if ($blocked) {
    return $blocked
}

return Invoke-HermesUninstallPage -Shell $shell -SectionTitle $sectionTitle `
    -ToolRoot $toolRoot -CoreLib $page.CoreLib
