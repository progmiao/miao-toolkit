$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$toolRoot = Join-Path $root 'package\tools\05-claude-code'
$coreLib = Join-Path $toolRoot '..\..\core\lib'

. (Join-Path $coreLib 'bootstrap\Load-Core.ps1') -LibDirectory $coreLib
Initialize-Paths -BinDirectory (Join-Path $root 'package\bin')
Initialize-PathsFromToolRoot -ToolRoot $toolRoot
. (Join-Path $toolRoot 'lib\claude-code-action-title.ps1')
Import-ClaudeCodeActionTitleCore -CoreLib $coreLib

$toolName = Get-ToolkitToolDisplayName -ToolRoot $toolRoot
$installAction = Resolve-ToolI18nLabel -ToolRoot $toolRoot -Key 'claude-code.action.install.name'
$initAction = Resolve-ToolI18nLabel -ToolRoot $toolRoot -Key 'claude-code.action.init.name'

$expectedInstall = "$toolName - $installAction"
$expectedInit = "$toolName - $initAction"

$installTitle = Get-ClaudeCodeActionSectionTitle -ToolRoot $toolRoot -ScriptLeaf 'install-cli.ps1'
$initTitle = Get-ClaudeCodeActionSectionTitle -ToolRoot $toolRoot -ScriptLeaf 'init.ps1'

if ($installTitle -ne $expectedInstall) {
    throw "unexpected install title: $installTitle (expected $expectedInstall)"
}
if ($initTitle -ne $expectedInit) {
    throw "unexpected init title: $initTitle (expected $expectedInit)"
}
if ($installTitle -eq $initTitle) {
    throw 'install and init titles must differ'
}

Write-Host 'test-claude-code-action-title: OK'
