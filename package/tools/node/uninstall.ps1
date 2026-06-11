# node — 第三方依赖卸载（CLI 薄入口；Shell 内由 core 直接编排）

$ErrorActionPreference = 'Stop'

$toolRoot = Split-Path $PSScriptRoot -Parent
$coreLib = Join-Path $toolRoot '..\..\core\lib'

. (Join-Path $coreLib 'config\Paths.ps1')
. (Join-Path $coreLib 'config\I18n.ps1')
. (Join-Path $coreLib 'domain\Discover-Tools.ps1')
. (Join-Path $coreLib 'domain\Check-Update.ps1')
. (Join-Path $coreLib 'domain\Ensure-ToolDeps.ps1')
. (Join-Path $coreLib 'config\Deps-State.ps1')
. (Join-Path $coreLib 'domain\Invoke-ToolDepPackage.ps1')
. (Join-Path $coreLib 'domain\Invoke-ToolkitDepOperation.ps1')
. (Join-Path $coreLib 'ui\shell\DepOperationView.ps1')

Initialize-PathsFromToolRoot -ToolRoot $toolRoot
$tool = Get-ToolFromDirectory -ToolRoot $toolRoot

$ok = Start-ToolkitDepOperation -Tool $tool -Intent uninstall
exit $(if ($ok) { 0 } else { 1 })
