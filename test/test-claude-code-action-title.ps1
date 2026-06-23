$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$toolRoot = Join-Path $root 'package\tools\04-claude-code'
$coreLib = Join-Path $toolRoot '..\..\core\lib'

. (Join-Path $coreLib 'bootstrap\Load-Core.ps1') -LibDirectory $coreLib
Initialize-Paths -BinDirectory (Join-Path $root 'package\bin')
Initialize-PathsFromToolRoot -ToolRoot $toolRoot
. (Join-Path $toolRoot 'lib\claude-code-action-title.ps1')
Import-ClaudeCodeActionTitleCore -CoreLib $coreLib

$toolName = Get-ToolkitToolDisplayName -ToolRoot $toolRoot
$installAction = Resolve-ToolI18nLabel -ToolRoot $toolRoot -Key 'claude-code.action.install.name'
$updateAction = Resolve-ToolI18nLabel -ToolRoot $toolRoot -Key 'claude-code.action.update.name'
$initAction = Resolve-ToolI18nLabel -ToolRoot $toolRoot -Key 'claude-code.action.init.name'

$expectedInstall = "$toolName - $installAction"
$expectedUpdate = "$toolName - $updateAction"
$expectedInit = "$toolName - $initAction"

$installTitle = Get-ClaudeCodeActionSectionTitle -ToolRoot $toolRoot -ScriptLeaf 'install-cli.ps1'
$updateTitle = Get-ClaudeCodeActionSectionTitle -ToolRoot $toolRoot -ScriptLeaf 'update-cli.ps1'
$initTitle = Get-ClaudeCodeActionSectionTitle -ToolRoot $toolRoot -ScriptLeaf 'init.ps1'

if ($installTitle -ne $expectedInstall) {
    throw "unexpected install title: $installTitle (expected $expectedInstall)"
}
if ($updateTitle -ne $expectedUpdate) {
    throw "unexpected update title: $updateTitle (expected $expectedUpdate)"
}
if ($initTitle -ne $expectedInit) {
    throw "unexpected init title: $initTitle (expected $expectedInit)"
}
if ($installTitle -eq $updateTitle) {
    throw 'install and update titles must differ'
}

Write-Host 'test-claude-code-action-title: OK'
