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
$rows = @($items | ForEach-Object {
    New-ShellListRow -Id ([string]$_.PluginId) -Cells @(
        [string]$_.PluginId
        [string]$_.Description
    ) -Payload $_ -Enabled $true
})
$layout = New-ShellListLayout -Widths @(36, 0)
$listResult = Invoke-ToolkitShellList @{
    Mode         = 'Multi'
    Shell        = $shell
    SectionTitle = $sectionTitle
    Rows         = $rows
    CacheKey     = 'ClaudeCodeAddMarketplace'
    Layout       = $layout
    Toolbar      = (New-ShellSystemToolbarConfig)
    CountLabel   = (Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.marketplace.countUnit')
}

$nav = Get-ShellListSelectNavMarker $listResult
if ($nav) { return $nav }
if ($listResult.Action -ne 'Pick' -or @($listResult.Ids).Count -eq 0) {
    return (Get-ShellNavMarker -Action 'back')
}

$sources = @($listResult.Ids | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

$batchSectionTitle = Extend-ClaudeCodeActionSectionTitle -BaseTitle $sectionTitle -ToolRoot $toolRoot `
    -SubPhaseKey 'claude-code.section.marketplaceAddExecute'

return Invoke-ClaudeCodeBatchOperation -Shell $shell -SectionTitle $batchSectionTitle `
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
