# claude-code — 卸载插件（多选）

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
. (Join-Path $PSScriptRoot 'claude-plugin-list-load.ps1')
. (Join-Path $PSScriptRoot 'claude-batch.ps1')

$page = Initialize-ClaudeCodeActionPage -ToolRoot $toolRoot -ToolkitShell $ToolkitShell `
    -PageSize $PageSize -ViewHeight $ViewHeight
$shell = $page.Shell
$sectionTitle = Get-ClaudeCodeActionSectionTitle -ToolRoot $toolRoot -Action $Action `
    -ScriptLeaf 'uninstall-plugin.ps1'

if (-not (Test-ClaudeCodeCliAvailable)) {
    return Invoke-ClaudeCodeNoticePage -Shell $shell -SectionTitle $sectionTitle `
        -Message (Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.cli.notInstalled') `
        -CacheKey 'ClaudeCodeUninstallPluginNotice'
}

$loadResult = Invoke-ClaudePluginMenuItemsWithLoading -Shell $shell -ToolRoot $toolRoot `
    -SectionTitle $sectionTitle -LoadMode installed
if ($loadResult.Nav) {
    return $loadResult.Nav
}
if ($loadResult.Error) {
    return Invoke-ClaudeCodeNoticePage -Shell $shell -SectionTitle $sectionTitle `
        -Message (Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.plugin.loadFailed' -Vars @{
            detail = $loadResult.Error.Exception.Message
        }) -CacheKey 'ClaudeCodeUninstallPluginLoadFailed'
}

$items = @($loadResult.Items)
$progress = $loadResult.Progress

if ($items.Count -eq 0) {
    return Invoke-ClaudeCodeNoticePage -Shell $shell -SectionTitle $sectionTitle `
        -Message (Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.plugin.noInstalled') `
        -CacheKey 'ClaudeCodeUninstallPluginEmpty'
}

$null = Ensure-ToolkitShellLayoutBrandInnerWidth -Shell $shell
$rows = Build-ClaudePluginRows -Items $items -ToolRoot $toolRoot -GetTagsLabel {
    param($Item)
    Get-ClaudePluginTagsLabel -Item $Item -ToolRoot $toolRoot
}
$listResult = Invoke-ToolkitShellList @{
    Mode            = 'Multi'
    Shell           = $shell
    SectionTitle    = $sectionTitle
    Rows            = $rows
    CacheKey        = 'ClaudeCodeUninstallPlugin'
    Layout          = (New-ClaudePluginListLayout)
    Toolbar         = (New-ShellSystemToolbarConfig)
    CountLabel      = (Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.plugin.countUnit')
    Search          = @{ Columns = @(0) }
    LoadingProgress = $progress
}

if ($nav = Get-ShellListSelectNavMarker $listResult) {
    return $nav
}
if ($listResult.Action -ne 'Pick') {
    return (Get-ShellNavMarker -Action 'back')
}

$pluginIds = @(Resolve-ClaudePluginPick -Picked @($listResult.Payloads))

$batchSectionTitle = Get-ClaudeCodePluginBatchSectionTitle -ToolRoot $toolRoot `
    -SubPhaseKey 'claude-code.section.pluginUninstallExecute'

return Invoke-ClaudeCodeBatchOperation -Shell $shell -SectionTitle $batchSectionTitle `
    -ReadyStatusText (Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.plugin.uninstallStatusReady') `
    -Intent uninstall -Items $pluginIds `
    -GetItemLabel { param($Item) [string]$Item } `
    -InvokeItem {
        param($Item, $Pump)
        Invoke-ClaudePluginUninstall -PluginId ([string]$Item) -OnUiPoll $Pump -OnChromePulse $Pump
    } `
    -GetSuccessLog {
        param($Item, $Result)
        Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.plugin.uninstallSuccess' -Vars @{
            plugin = [string]$Item
        }
    } `
    -GetFailureLog {
        param($Item, $Result)
        Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.plugin.uninstallFailed' -Vars @{
            plugin = [string]$Item
            detail = (Get-ClaudeCodeCliFailureDetail -Result $Result)
        }
    }
