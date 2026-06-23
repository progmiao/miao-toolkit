# claude-code — 配置代理

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
. (Join-Path $PSScriptRoot 'claude-settings.ps1')
. (Join-Path $PSScriptRoot 'claude-batch.ps1')

$page = Initialize-ClaudeCodeActionPage -ToolRoot $toolRoot -ToolkitShell $ToolkitShell `
    -PageSize $PageSize -ViewHeight $ViewHeight
$shell = $page.Shell
$sectionTitle = Get-ClaudeCodeActionSectionTitle -ToolRoot $toolRoot -Action $Action `
    -ScriptLeaf 'configure-proxy.ps1'

$modeItems = @(
    [pscustomobject]@{ Mode = 'set'; LabelKey = 'claude-code.proxy.modeSet' },
    [pscustomobject]@{ Mode = 'clear'; LabelKey = 'claude-code.proxy.modeClear' }
)

$rows = ConvertTo-ShellListRows -Items $modeItems -KeepSource -GetSearchKey {
    param($Item, [int]$Index)
    Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key ([string]$Item.LabelKey)
} -MapCells {
    param($Item, [int]$Index)
    @(
        (Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key ([string]$Item.LabelKey))
        ''
    )
} -GetEnabled { param($Item, [int]$Index) $true }

Clear-ShellSingleSelectListCache -Shell $shell -CacheKey 'ClaudeCodeConfigureProxy'
$toolbar = New-ShellSystemToolbarConfig
$picked = Invoke-ShellSingleSelectList -Shell $shell -SectionTitle $sectionTitle `
    -Rows $rows -CacheKey 'ClaudeCodeConfigureProxy' `
    -ColumnLayout (New-ShellListColumnLayout -Preset ToolList) `
    -ToolbarConfig $toolbar

if ($null -eq $picked) {
    return (Get-ShellNavMarker -Action 'back')
}

$mode = if ($picked.Source) { [string]$picked.Source.Mode } else { [string]$picked.Mode }
if ([string]::IsNullOrWhiteSpace($mode)) {
    return (Get-ShellNavMarker -Action 'back')
}

$proxyConfig = @{ mode = $mode }
if ($mode -eq 'set') {
    $values = Invoke-ClaudeCodeShellLineInput -Shell $shell -Prompts @(
        (Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.proxy.promptHttp'),
        (Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.proxy.promptHttps')
    )
    $proxyConfig['httpProxy'] = [string]$values[0]
    $proxyConfig['httpsProxy'] = [string]$values[1]
}

$batchItem = [pscustomobject]@{
    Mode   = $mode
    Config = $proxyConfig
}

return Invoke-ClaudeCodeBatchOperation -Shell $shell -SectionTitle $sectionTitle `
    -ReadyStatusText (Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.proxy.statusReady') `
    -Intent configure -Items @($batchItem) `
    -GetItemLabel {
        param($Item)
        Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.proxy.applyLabel'
    } `
    -InvokeItem {
        param($Item)
        $path = Apply-ClaudeCodeProxySecrets -ProxyConfig $Item.Config
        return [pscustomobject]@{
            Success = $true
            Path    = $path
        }
    } `
    -GetSuccessLog {
        param($Item, $Result)
        Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.proxy.logSuccess' -Vars @{
            path = [string]$Result.Path
        }
    } `
    -GetFailureLog {
        param($Item, $Result)
        $detail = if ($Result -is [string]) { $Result } else { [string]$Result }
        Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.proxy.logFailed' -Vars @{ detail = $detail }
    }
