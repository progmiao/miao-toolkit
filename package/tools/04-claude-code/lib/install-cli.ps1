# claude-code — 安装 CLI（WinGet）

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
    -ScriptLeaf 'install-cli.ps1'

if (Test-ClaudeCodeInstalled) {
    $version = Get-ClaudeCodeInstalledVersion
    $message = Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.cli.alreadyInstalled' -Vars @{
        version = if ($version) { $version } else { '?' }
    }
    return Invoke-ClaudeCodeNoticePage -Shell $shell -SectionTitle $sectionTitle `
        -Message $message -CacheKey 'ClaudeCodeInstallNotice'
}

return Invoke-ClaudeCodeWingetBatchPage -Shell $shell -SectionTitle $sectionTitle `
    -ReadyStatusText (Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.cli.installStatusReady') `
    -Verb install -SuccessLogKey 'claude-code.cli.installSuccess' `
    -FailureLogKey 'claude-code.cli.installFailed' -ToolRoot $toolRoot -CoreLib $page.CoreLib
