$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$coreLib = Join-Path $root 'package\core\lib'
$toolRoot = Join-Path $root 'package\tools\05-claude-code'

. (Join-Path $coreLib 'bootstrap\Load-Core.ps1') -LibDirectory $coreLib
. (Join-Path $coreLib 'ui\shell\BatchExecution.ps1')
Initialize-PathsFromToolRoot -ToolRoot $toolRoot
. (Join-Path $toolRoot 'lib\claude-code-action-title.ps1')
Import-ClaudeCodeActionTitleCore -CoreLib $coreLib

$ui = @{
    ProgressCurrent      = 0
    ItemInFlight         = $true
    StatusSpinnerActive  = $true
    StatusMainText       = 'x'
    StatusPlain          = $false
    StatusText           = ''
    StatusSegments       = @()
}
Set-ToolkitBatchExecutionCompleteUi -Ui $ui -Intent configure -TotalCount 2 -SuccessCount 2 `
    -FailedCount 0 -ProgressCurrent 2

$pluginSection = Get-ClaudeCodePluginSectionTitle -ToolRoot $toolRoot
$installBatch = Get-ClaudeCodePluginBatchSectionTitle -ToolRoot $toolRoot `
    -SubPhaseKey 'claude-code.section.pluginInstallExecute'
$pluginLabel = Resolve-ToolI18nLabel -ToolRoot $toolRoot -Key 'claude-code.action.installPlugin.name'
$installLabel = Resolve-ToolI18nLabel -ToolRoot $toolRoot -Key 'claude-code.section.pluginInstallExecute'

$expectedInstall = "$pluginSection - $installLabel"
if ($installBatch -ne $expectedInstall) {
    throw "unexpected plugin install batch title: [$installBatch] (expected [$expectedInstall])"
}
if ($pluginSection -notmatch [regex]::Escape($pluginLabel)) {
    throw "plugin section title missing label: $pluginSection"
}

Write-Host 'test-claude-code-batch-title: OK'
