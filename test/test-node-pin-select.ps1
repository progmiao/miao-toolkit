$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$toolRoot = Join-Path $root 'package\tools\01-node'
$coreLib = Join-Path $toolRoot '..\..\core\lib'

. (Join-Path $coreLib 'bootstrap\Load-Core.ps1') -LibDirectory $coreLib
Initialize-Paths -BinDirectory (Join-Path $root 'package\bin')
Initialize-PathsFromToolRoot -ToolRoot $toolRoot
. (Join-Path $toolRoot 'lib\volta-node.ps1')
Set-NodeVoltaToolRoot -ToolRoot $toolRoot

$script:NodeBrowseInstallDotSourceOnly = $true
. (Join-Path $toolRoot 'lib\browse-install.ps1')
$script:NodeBrowseInstallDotSourceOnly = $false
. (Join-Path $toolRoot 'lib\node-pin-select.ps1')

$voltaInfo = @{ Map = @{ '20.11.0' = $true; '18.19.0' = $true }; Default = '20.11.0' }
$base = @(
    (New-NodeVersionMenuItem -Version '22.0.0')
    (New-NodeVersionMenuItem -Version '20.11.0')
    (New-NodeVersionMenuItem -Version '18.19.0')
)

$merged = Build-NodePinMergedItems -BaseVersions $base -VoltaInfo $voltaInfo -PinnedVersion '21.7.3'
$versions = @($merged | ForEach-Object { $_.Version })
if ($versions -notcontains '21.7.3') { throw 'expected pinned-not-installed version in merged list' }
if ($versions -notcontains '22.0.0') { throw 'expected remote version in merged list' }

$rows = Build-NodePinRows -Items $merged -InstalledMap $voltaInfo.Map `
    -DefaultVersion '20.11.0' -ActiveVersion '20.11.0' -PinnedVersion '21.7.3'
$pinnedRow = $rows | Where-Object { $_.SearchKey -eq '21.7.3' } | Select-Object -First 1
if (-not $pinnedRow) { throw 'missing pinned row' }
$tagText = [string]$pinnedRow.Cells[1]
if ([string]::IsNullOrWhiteSpace($tagText)) {
    throw "expected pinned tag on pinned-not-installed row, got empty tags"
}

$ctx = @{
    HasProject       = $true
    ProjectName      = 'demo-app'
    PackageJsonRel   = 'package.json'
    PinnedVersion    = '20.11.0'
    WorkingDirectory = 'C:\work\demo-app'
}
$msg = Format-NodePinCatalogLineMessage -ToolRoot $toolRoot -PinContext $ctx -VoltaInfo $voltaInfo
if ([string]::IsNullOrWhiteSpace($msg)) { throw 'expected context content line message' }

$noProject = @{ HasProject = $false; ProjectName = 'demo'; PackageJsonRel = '' }
$warn = Format-NodePinMessageLineMessage -ToolRoot $toolRoot -PinContext $noProject -VoltaInfo $voltaInfo
if ([string]::IsNullOrWhiteSpace($warn)) { throw 'expected no-project warning on message line' }

Write-Host 'test-node-pin-select: OK'
