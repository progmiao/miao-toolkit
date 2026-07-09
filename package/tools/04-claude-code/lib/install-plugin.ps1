# claude-code — 安装/更新插件（多选）

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
. (Join-Path $PSScriptRoot 'claude-plugin-state.ps1')
. (Join-Path $PSScriptRoot 'claude-plugin-list-load.ps1')
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

$loadResult = Invoke-ClaudePluginMenuItemsWithLoading -Shell $shell -ToolRoot $toolRoot `
    -SectionTitle $sectionTitle -LoadMode install
if ($loadResult.Nav) {
    return $loadResult.Nav
}
if ($loadResult.Error) {
    return Invoke-ClaudeCodeNoticePage -Shell $shell -SectionTitle $sectionTitle `
        -Message (Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.plugin.loadFailed' -Vars @{
            detail = $loadResult.Error.Exception.Message
        }) -CacheKey 'ClaudeCodeInstallPluginLoadFailed'
}

$items = @($loadResult.Items)
$progress = $loadResult.Progress

if ($items.Count -eq 0) {
    return Invoke-ClaudeCodeNoticePage -Shell $shell -SectionTitle $sectionTitle `
        -Message (Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.plugin.noAvailable') `
        -CacheKey 'ClaudeCodeInstallPluginEmpty'
}

$null = Ensure-ToolkitShellLayoutBrandInnerWidth -Shell $shell
$rows = Build-ClaudePluginManageRows -Items $items -ToolRoot $toolRoot
$listResult = Invoke-ToolkitShellList @{
    Mode               = 'Multi'
    Shell              = $shell
    SectionTitle       = $sectionTitle
    Rows               = $rows
    CacheKey           = 'ClaudeCodeInstallPlugin'
    Layout             = (New-ClaudePluginManageListLayout -Shell $shell)
    InitialCatalogLine = ''
    Toolbar            = (New-ShellSystemToolbarConfig)
    CountLabel         = (Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.plugin.countUnit')
    Search             = @{ Columns = @(0, 1) }
    LoadingProgress    = $progress
}

if ($nav = Get-ShellListSelectNavMarker $listResult) {
    return $nav
}
if ($listResult.Action -ne 'Pick') {
    return (Get-ShellNavMarker -Action 'back')
}

$pickedItems = @($listResult.Payloads)

$batchSectionTitle = Get-ClaudeCodePluginBatchSectionTitle -ToolRoot $toolRoot `
    -SubPhaseKey 'claude-code.section.pluginInstallExecute'

return Invoke-ClaudeCodeBatchOperation -Shell $shell -SectionTitle $batchSectionTitle `
    -ReadyStatusText (Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.plugin.manageStatusReady') `
    -Intent install -Items $pickedItems `
    -GetItemLabel {
        param($Item)
        Get-ClaudePluginDisplayName -PluginId ([string]$Item.PluginId)
    } `
    -InvokeItem {
        param($Item, $Pump)
        $pluginId = [string]$Item.PluginId
        if ($Item.PSObject.Properties['HasUpdate'] -and [bool]$Item.HasUpdate) {
            $result = Invoke-ClaudePluginUpdate -PluginId $pluginId -OnUiPoll $Pump -OnChromePulse $Pump
            if ($result -and [int]$result.ExitCode -eq 0) {
                Register-ClaudePluginUpdateSuccess -PluginId $pluginId
            }
            return $result
        }

        $result = Invoke-ClaudePluginInstall -PluginId $pluginId -OnUiPoll $Pump -OnChromePulse $Pump
        if ($result -and [int]$result.ExitCode -eq 0) {
            Register-ClaudePluginInstallSuccess -PluginId $pluginId
        }
        return $result
    } `
    -GetSuccessLog {
        param($Item, $Result)
        if ($Item.PSObject.Properties['HasUpdate'] -and [bool]$Item.HasUpdate) {
            $output = if ($Result -is [string]) { $Result } else { [string]$Result.Output }
            return (Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.plugin.updateSuccess' -Vars @{
                plugin = [string]$Item.PluginId
                detail = ($output.Trim() -replace '\s+', ' ')
            })
        }
        return (Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.plugin.installSuccess' -Vars @{
            plugin = [string]$Item.PluginId
        })
    } `
    -GetFailureLog {
        param($Item, $Result)
        if ($Item.PSObject.Properties['HasUpdate'] -and [bool]$Item.HasUpdate) {
            return (Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.plugin.updateFailed' -Vars @{
                plugin = [string]$Item.PluginId
                detail = (Get-ClaudeCodeCliFailureDetail -Result $Result)
            })
        }
        return (Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.plugin.installFailed' -Vars @{
            plugin = [string]$Item.PluginId
            detail = (Get-ClaudeCodeCliFailureDetail -Result $Result)
        })
    }
