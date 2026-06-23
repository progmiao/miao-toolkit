# claude-code — 卸载 CLI（WinGet）

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
. (Join-Path $PSScriptRoot 'claude-batch.ps1')

$page = Initialize-ClaudeCodeActionPage -ToolRoot $toolRoot -ToolkitShell $ToolkitShell `
    -PageSize $PageSize -ViewHeight $ViewHeight
$shell = $page.Shell
$sectionTitle = Get-ClaudeCodeActionSectionTitle -ToolRoot $toolRoot -Action $Action `
    -ScriptLeaf 'uninstall-cli.ps1'

if (-not (Test-ClaudeCodeInstalled)) {
    return Invoke-ClaudeCodeNoticePage -Shell $shell -SectionTitle $sectionTitle `
        -Message (Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.cli.notInstalled') `
        -CacheKey 'ClaudeCodeUninstallNotice'
}

return Invoke-ClaudeCodeWingetBatchPage -Shell $shell -SectionTitle $sectionTitle `
    -ReadyStatusText (Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.cli.uninstallStatusReady') `
    -Verb uninstall -SuccessLogKey 'claude-code.cli.uninstallSuccess' `
    -FailureLogKey 'claude-code.cli.uninstallFailed' -ToolRoot $toolRoot -CoreLib $page.CoreLib
