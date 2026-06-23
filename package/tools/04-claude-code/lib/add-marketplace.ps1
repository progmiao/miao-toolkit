# claude-code — 添加插件市场（多选）

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
    -ScriptLeaf 'add-marketplace.ps1'

if (-not (Test-ClaudeCodeCliAvailable)) {
    return Invoke-ClaudeCodeNoticePage -Shell $shell -SectionTitle $sectionTitle `
        -Message (Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.cli.notInstalled') `
        -CacheKey 'ClaudeCodeAddMarketplaceNotice'
}

$items = @(Get-ClaudeCodePresetMarketplaces | ForEach-Object {
    New-ClaudePluginMenuItem -PluginId ([string]$_.Source) -Description ([string]$_.Description) `
        -Enabled $true -Source $_
})

if ($items.Count -eq 0) {
    return Invoke-ClaudeCodeNoticePage -Shell $shell -SectionTitle $sectionTitle `
        -Message (Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.marketplace.noPresets') `
        -CacheKey 'ClaudeCodeAddMarketplaceEmpty'
}

$null = Ensure-ToolkitShellLayoutBrandInnerWidth -Shell $shell
$rows = Build-ClaudePluginRows -Items $items -ToolRoot $toolRoot
$toolbar = New-ShellSystemToolbarConfig
$picked = Invoke-ShellMultiSelectList -Shell $shell -SectionTitle $sectionTitle `
    -Rows $rows -CacheKey 'ClaudeCodeAddMarketplace' `
    -ColumnLayout (New-ShellListColumnLayout -Preset ToolList) `
    -ToolbarConfig $toolbar `
    -CountLabel (Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.marketplace.countUnit')

if ($null -eq $picked -or @($picked).Count -eq 0) {
    return (Get-ShellNavMarker -Action 'back')
}

$sources = @($picked | ForEach-Object {
    if ($_.Source -and $_.Source.Source) { [string]$_.Source.Source }
    elseif ($_.Source -and $_.Source.PluginId) { [string]$_.Source.PluginId }
    elseif ($_.PluginId) { [string]$_.PluginId }
    else { [string]$_.SearchKey }
} | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

return Invoke-ClaudeCodeBatchOperation -Shell $shell -SectionTitle $sectionTitle `
    -ReadyStatusText (Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.marketplace.statusReady') `
    -Intent configure -Items $sources `
    -GetItemLabel { param($Item) [string]$Item } `
    -InvokeItem {
        param($Item)
        Invoke-ClaudePluginMarketplaceAdd -Source ([string]$Item)
    } `
    -GetSuccessLog {
        param($Item, $Result)
        Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.marketplace.logSuccess' -Vars @{
            source = [string]$Item
        }
    } `
    -GetFailureLog {
        param($Item, $Result)
        $detail = if ($Result -is [string]) { $Result } else { [string]$Result.Output }
        if ([string]::IsNullOrWhiteSpace($detail)) {
            $detail = "exit $($Result.ExitCode)"
        }
        Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.marketplace.logFailed' -Vars @{
            source = [string]$Item
            detail = $detail
        }
    }
