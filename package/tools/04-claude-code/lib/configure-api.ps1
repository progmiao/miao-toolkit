# claude-code — 配置 API 访问

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
    -ScriptLeaf 'configure-api.ps1'

$modeItems = @(
    [pscustomobject]@{ Mode = 'official'; LabelKey = 'claude-code.api.modeOfficial' },
    [pscustomobject]@{ Mode = 'custom'; LabelKey = 'claude-code.api.modeCustom' },
    [pscustomobject]@{ Mode = 'clear'; LabelKey = 'claude-code.api.modeClear' }
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

Clear-ShellSingleSelectListCache -Shell $shell -CacheKey 'ClaudeCodeConfigureApi'
$toolbar = New-ShellSystemToolbarConfig
$picked = Invoke-ShellSingleSelectList -Shell $shell -SectionTitle $sectionTitle `
    -Rows $rows -CacheKey 'ClaudeCodeConfigureApi' `
    -ColumnLayout (New-ShellListColumnLayout -Preset ToolList) `
    -ToolbarConfig $toolbar

if ($null -eq $picked) {
    return (Get-ShellNavMarker -Action 'back')
}

$mode = if ($picked.Source) { [string]$picked.Source.Mode } else { [string]$picked.Mode }
if ([string]::IsNullOrWhiteSpace($mode)) {
    return (Get-ShellNavMarker -Action 'back')
}

$apiConfig = @{ mode = $mode }
if ($mode -eq 'official') {
    $values = Invoke-ClaudeCodeShellLineInput -Shell $shell -Prompts @(
        (Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.api.promptApiKey')
    ) -SecretFlags @([switch]$true)
    $apiConfig['apiKey'] = [string]$values[0]
}
elseif ($mode -eq 'custom') {
    $values = Invoke-ClaudeCodeShellLineInput -Shell $shell -Prompts @(
        (Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.api.promptBaseUrl'),
        (Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.api.promptToken')
    ) -SecretFlags @([switch]$false, [switch]$true)
    $apiConfig['baseUrl'] = [string]$values[0]
    $apiConfig['authToken'] = [string]$values[1]
}

$batchItem = [pscustomobject]@{
    Mode   = $mode
    Config = $apiConfig
}

return Invoke-ClaudeCodeBatchOperation -Shell $shell -SectionTitle $sectionTitle `
    -ReadyStatusText (Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.api.statusReady') `
    -Intent configure -Items @($batchItem) `
    -GetItemLabel {
        param($Item)
        Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.api.applyLabel'
    } `
    -InvokeItem {
        param($Item)
        $path = Apply-ClaudeCodeApiSecrets -ApiConfig $Item.Config
        return [pscustomobject]@{
            Success = $true
            Path    = $path
        }
    } `
    -GetSuccessLog {
        param($Item, $Result)
        Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.api.logSuccess' -Vars @{
            path = [string]$Result.Path
        }
    } `
    -GetFailureLog {
        param($Item, $Result)
        $detail = if ($Result -is [string]) { $Result } else { [string]$Result }
        Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key 'claude-code.api.logFailed' -Vars @{ detail = $detail }
    }
