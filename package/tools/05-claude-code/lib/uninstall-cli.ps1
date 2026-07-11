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

Import-ClaudeCodeWingetCore -CoreLib $page.CoreLib

$blocked = Invoke-ClaudeCodeCliRequiredNoticePage -Shell $shell -SectionTitle $sectionTitle `
    -ToolRoot $toolRoot -CacheKey 'ClaudeCodeUninstallNotice'
if ($blocked) {
    return $blocked
}

if (-not (Test-ClaudeCodeWingetPackageInstalled)) {
    $installPath = Get-ClaudeCodeCliInstallPath
    if ([string]::IsNullOrWhiteSpace($installPath)) {
        $installPath = '?'
    }
    $versionLabel = Get-ClaudeCodeInstalledVersion
    if ([string]::IsNullOrWhiteSpace($versionLabel)) {
        $versionLabel = '?'
    }
    return Invoke-ClaudeCodeNoticePage -Shell $shell -SectionTitle $sectionTitle `
        -Message (Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.cli.uninstallNotWingetManaged' `
            -Vars @{ path = $installPath; version = $versionLabel }) `
        -CacheKey 'ClaudeCodeUninstallNotWingetNotice'
}

return Invoke-ClaudeCodeWingetBatchPage -Shell $shell -SectionTitle $sectionTitle `
    -ReadyStatusText (Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.cli.uninstallStatusReady') `
    -Verb uninstall -SuccessLogKey 'claude-code.cli.uninstallSuccess' `
    -FailureLogKey 'claude-code.cli.uninstallFailed' -ToolRoot $toolRoot -CoreLib $page.CoreLib
