$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$toolRoot = Join-Path $root 'package\tools\node'
$coreLib = Join-Path $toolRoot '..\..\core\lib'

. (Join-Path $coreLib 'bootstrap\Load-Core.ps1') -LibDirectory $coreLib
Initialize-Paths -BinDirectory (Join-Path $root 'package\bin')
Initialize-PathsFromToolRoot -ToolRoot $toolRoot
. (Join-Path $toolRoot 'lib\node-action-title.ps1')
Import-NodeActionTitleCore -CoreLib $coreLib

$expectedInstall = Resolve-ToolI18nLabel -ToolRoot $toolRoot -Key 'node.action.install.name'
$expectedPin = Resolve-ToolI18nLabel -ToolRoot $toolRoot -Key 'node.action.pin.name'
$installTitle = Get-NodeActionSectionTitle -ToolRoot $toolRoot -ScriptLeaf 'browse-install.ps1'
$pinTitle = Get-NodeActionSectionTitle -ToolRoot $toolRoot -ScriptLeaf 'pin-project.ps1'
if ($installTitle -ne $expectedInstall) { throw "unexpected install title: $installTitle" }
if ($pinTitle -ne $expectedPin) { throw "unexpected pin title: $pinTitle" }
if ($installTitle -eq $pinTitle) { throw 'install and pin titles must differ' }

. (Join-Path $toolRoot 'lib\volta-node.ps1')
Set-NodeVoltaToolRoot -ToolRoot $toolRoot
$script:NodeBrowseInstallDotSourceOnly = $true
. (Join-Path $toolRoot 'lib\browse-install.ps1')
$script:NodeBrowseInstallDotSourceOnly = $false
. (Join-Path $toolRoot 'lib\node-pin-select.ps1')

$voltaInfo = @{ Map = @{ '20.11.0' = $true }; Default = '20.11.0' }
$items = @((New-NodeVersionMenuItem -Version '20.11.0'), (New-NodeVersionMenuItem -Version '22.0.0'))
$rows = Build-NodePinRows -Items $items -InstalledMap $voltaInfo.Map `
    -DefaultVersion '20.11.0' -ActiveVersion '20.11.0' -PinnedVersion ''
$installedRow = $rows | Where-Object { $_.SearchKey -eq '20.11.0' } | Select-Object -First 1
$remoteRow = $rows | Where-Object { $_.SearchKey -eq '22.0.0' } | Select-Object -First 1
if ([string]::IsNullOrWhiteSpace([string]$installedRow.Cells[1])) { throw 'installed row expected tags' }
if (-not [string]::IsNullOrWhiteSpace([string]$remoteRow.Cells[1])) { throw 'remote-only row should have no installed tag' }

Write-Host 'test-node-action-title: OK'
