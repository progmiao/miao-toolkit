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
. (Join-Path $PSScriptRoot 'claude-code-state.ps1')
. (Join-Path $PSScriptRoot 'claude-settings.ps1')
. (Join-Path $PSScriptRoot 'claude-batch.ps1')

$page = Initialize-ClaudeCodeActionPage -ToolRoot $toolRoot -ToolkitShell $ToolkitShell `
    -PageSize $PageSize -ViewHeight $ViewHeight
$shell = $page.Shell
$sectionTitle = Get-ClaudeCodeActionSectionTitle -ToolRoot $toolRoot -Action $Action `
    -ScriptLeaf 'configure-api.ps1'

$blocked = Invoke-ClaudeCodeCliRequiredNoticePage -Shell $shell -SectionTitle $sectionTitle `
    -ToolRoot $toolRoot -CacheKey 'ClaudeCodeConfigureApiNotice'
if ($blocked) {
    return $blocked
}

$modeItems = @(
    [pscustomobject]@{ Mode = 'official'; LabelKey = 'claude-code.api.modeOfficial' },
    [pscustomobject]@{ Mode = 'custom'; LabelKey = 'claude-code.api.modeCustom' },
    [pscustomobject]@{ Mode = 'clear'; LabelKey = 'claude-code.api.modeClear' }
)

$rows = @($modeItems | ForEach-Object {
    $item = $_
    $label = Get-ClaudeCodeI18n -ToolRoot $toolRoot -Key ([string]$item.LabelKey)
    New-ShellListRow -Id ([string]$item.Mode) -Cells @($label, '') -Payload $item -SearchKey $label -Enabled $true
})

Clear-ShellListCache -Shell $shell -CacheKey 'ClaudeCodeConfigureApi'
$listResult = Invoke-ToolkitShellList @{
    Mode         = 'Single'
    Shell        = $shell
    SectionTitle = $sectionTitle
    Rows         = $rows
    CacheKey     = 'ClaudeCodeConfigureApi'
    Toolbar      = (New-ShellSystemToolbarConfig)
}

if ($nav = Get-ShellListSelectNavMarker $listResult) {
    return $nav
}
if ($listResult.Action -ne 'Pick' -or @($listResult.Payloads).Count -eq 0) {
    return (Get-ShellNavMarker -Action 'back')
}
$picked = $listResult.Payloads[0]

$mode = [string]$picked.Mode
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
        param($Item, $Pump)
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
