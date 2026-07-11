# claude-code — 初始化（无输入默认配置）

param(
    [hashtable]$ToolkitShell = $null,
    $Action = $null,
    [int]$PageSize = 0,
    [int]$ViewHeight = 0
)

$ErrorActionPreference = 'Stop'
$toolRoot = Split-Path $PSScriptRoot -Parent

. (Join-Path $PSScriptRoot 'claude-code-core.ps1')
. (Join-Path $PSScriptRoot 'claude-code-action-title.ps1')
. (Join-Path $PSScriptRoot 'claude-code-state.ps1')
. (Join-Path $PSScriptRoot 'claude-settings.ps1')
. (Join-Path $PSScriptRoot 'claude-plugin.ps1')
. (Join-Path $PSScriptRoot 'claude-code-presets.ps1')
. (Join-Path $PSScriptRoot 'claude-batch.ps1')

$page = Initialize-ClaudeCodeActionPage -ToolRoot $toolRoot -ToolkitShell $ToolkitShell `
    -PageSize $PageSize -ViewHeight $ViewHeight
$shell = $page.Shell
$sectionTitle = Get-ClaudeCodeActionSectionTitle -ToolRoot $toolRoot -Action $Action `
    -ScriptLeaf 'init.ps1'

$blocked = Invoke-ClaudeCodeCliRequiredNoticePage -Shell $shell -SectionTitle $sectionTitle `
    -ToolRoot $toolRoot -CacheKey 'ClaudeCodeInitNotice'
if ($blocked) {
    return $blocked
}

return Invoke-ClaudeCodeInitBatchPage -Shell $shell -SectionTitle $sectionTitle -ToolRoot $toolRoot
