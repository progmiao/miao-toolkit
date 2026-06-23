# claude-code — 更新插件（多选，可更新项打标签）

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
    -ScriptLeaf 'update-plugin.ps1'

if (-not (Test-ClaudeCodeCliAvailable)) {
    return Invoke-ClaudeCodeNoticePage -Shell $shell -SectionTitle $sectionTitle `
        -Message (Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.cli.notInstalled') `
        -CacheKey 'ClaudeCodeUpdatePluginNotice'
}

try {
    $items = @(Get-ClaudePluginInstalledMenuItems -ForUpdate)
}
catch {
    return Invoke-ClaudeCodeNoticePage -Shell $shell -SectionTitle $sectionTitle `
        -Message (Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.plugin.loadFailed' -Vars @{
            detail = $_.Exception.Message
        }) -CacheKey 'ClaudeCodeUpdatePluginLoadFailed'
}

if ($items.Count -eq 0) {
    return Invoke-ClaudeCodeNoticePage -Shell $shell -SectionTitle $sectionTitle `
        -Message (Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.plugin.noInstalled') `
        -CacheKey 'ClaudeCodeUpdatePluginEmpty'
}

$null = Ensure-ToolkitShellLayoutBrandInnerWidth -Shell $shell
$rows = Build-ClaudePluginRows -Items $items -ToolRoot $toolRoot -GetTagsLabel {
    param($Item)
    Get-ClaudePluginTagsLabel -Item $Item -ToolRoot $toolRoot
}
$toolbar = New-ShellSystemToolbarConfig
$picked = Invoke-ShellMultiSelectList -Shell $shell -SectionTitle $sectionTitle `
    -Rows $rows -CacheKey 'ClaudeCodeUpdatePlugin' `
    -ColumnLayout (New-ShellListColumnLayout -Preset ToolList) `
    -ToolbarConfig $toolbar `
    -CountLabel (Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.plugin.countUnit') `
    -SearchKeyMode

if ($null -eq $picked -or @($picked).Count -eq 0) {
    return (Get-ShellNavMarker -Action 'back')
}

$pluginIds = @(Resolve-ClaudePluginPick -Picked $picked)

return Invoke-ClaudeCodeBatchOperation -Shell $shell -SectionTitle $sectionTitle `
    -ReadyStatusText (Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.plugin.updateStatusReady') `
    -Intent update -Items $pluginIds `
    -GetItemLabel { param($Item) [string]$Item } `
    -InvokeItem {
        param($Item)
        Invoke-ClaudePluginUpdate -PluginId ([string]$Item)
    } `
    -GetSuccessLog {
        param($Item, $Result)
        $output = if ($Result -is [string]) { $Result } else { [string]$Result.Output }
        Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.plugin.updateSuccess' -Vars @{
            plugin = [string]$Item
            detail = ($output.Trim() -replace '\s+', ' ')
        }
    } `
    -GetFailureLog {
        param($Item, $Result)
        $detail = if ($Result -is [string]) { $Result } else { [string]$Result.Output }
        if ([string]::IsNullOrWhiteSpace($detail)) {
            $detail = "exit $($Result.ExitCode)"
        }
        Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.plugin.updateFailed' -Vars @{
            plugin = [string]$Item
            detail = $detail
        }
    }
