# claude-code — 安装插件（多选）

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
. (Join-Path $PSScriptRoot 'claude-plugin.ps1')
. (Join-Path $PSScriptRoot 'claude-batch.ps1')

$page = Initialize-ClaudeCodeActionPage -ToolRoot $toolRoot -ToolkitShell $ToolkitShell `
    -PageSize $PageSize -ViewHeight $ViewHeight
$shell = $page.Shell
$sectionTitle = Get-ClaudeCodeActionSectionTitle -ToolRoot $toolRoot -Action $Action `
    -ScriptLeaf 'install-plugin.ps1'

if (-not (Test-ClaudeCodeCliAvailable)) {
    return Invoke-ClaudeCodeNoticePage -Shell $shell -SectionTitle $sectionTitle `
        -Message (Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.cli.notInstalled') `
        -CacheKey 'ClaudeCodeInstallPluginNotice'
}

try {
    $items = @(Get-ClaudePluginInstallMenuItems)
}
catch {
    return Invoke-ClaudeCodeNoticePage -Shell $shell -SectionTitle $sectionTitle `
        -Message (Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.plugin.loadFailed' -Vars @{
            detail = $_.Exception.Message
        }) -CacheKey 'ClaudeCodeInstallPluginLoadFailed'
}

$installable = @($items | Where-Object { $_.Enabled })
if ($installable.Count -eq 0) {
    return Invoke-ClaudeCodeNoticePage -Shell $shell -SectionTitle $sectionTitle `
        -Message (Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.plugin.noInstallable') `
        -CacheKey 'ClaudeCodeInstallPluginEmpty'
}

$null = Ensure-ToolkitShellLayoutBrandInnerWidth -Shell $shell
$rows = Build-ClaudePluginRows -Items $items -ToolRoot $toolRoot -GetTagsLabel {
    param($Item)
    Get-ClaudePluginTagsLabel -Item $Item -ToolRoot $toolRoot
}
$toolbar = New-ShellSystemToolbarConfig
$picked = Invoke-ShellMultiSelectList -Shell $shell -SectionTitle $sectionTitle `
    -Rows $rows -CacheKey 'ClaudeCodeInstallPlugin' `
    -ColumnLayout (New-ShellListColumnLayout -Preset ToolList) `
    -ToolbarConfig $toolbar `
    -CountLabel (Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.plugin.countUnit') `
    -SearchKeyMode

if ($null -eq $picked -or @($picked).Count -eq 0) {
    return (Get-ShellNavMarker -Action 'back')
}

$pluginIds = @(Resolve-ClaudePluginPick -Picked $picked)

return Invoke-ClaudeCodeBatchOperation -Shell $shell -SectionTitle $sectionTitle `
    -ReadyStatusText (Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.plugin.installStatusReady') `
    -Intent install -Items $pluginIds `
    -GetItemLabel { param($Item) [string]$Item } `
    -InvokeItem {
        param($Item)
        Invoke-ClaudePluginInstall -PluginId ([string]$Item)
    } `
    -GetSuccessLog {
        param($Item, $Result)
        Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.plugin.installSuccess' -Vars @{
            plugin = [string]$Item
        }
    } `
    -GetFailureLog {
        param($Item, $Result)
        $detail = if ($Result -is [string]) { $Result } else { [string]$Result.Output }
        if ([string]::IsNullOrWhiteSpace($detail)) {
            $detail = "exit $($Result.ExitCode)"
        }
        Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.plugin.installFailed' -Vars @{
            plugin = [string]$Item
            detail = $detail
        }
    }
