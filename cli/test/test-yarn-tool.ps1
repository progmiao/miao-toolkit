$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$toolRoot = Join-Path $root 'package\tools\04-yarn'
$coreLib = Join-Path $toolRoot '..\..\core\lib'

. (Join-Path $coreLib 'bootstrap\Load-Core.ps1') -LibDirectory $coreLib
Initialize-Paths -BinDirectory (Join-Path $root 'package\bin')
Initialize-PathsFromToolRoot -ToolRoot $toolRoot
. (Join-Path $toolRoot 'lib\volta-yarn.ps1')
Set-YarnVoltaToolRoot -ToolRoot $toolRoot

$configPath = Join-Path $toolRoot 'index.json'
$config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$config.name -ne 'yarn.name') { throw 'expected yarn.name in index.json' }

$tool = Get-ToolFromDirectory -ToolRoot $toolRoot
if (-not $tool) { throw 'Get-ToolFromDirectory failed for yarn' }
if ([int]$tool.sortOrder -ne 4) { throw "expected yarn sortOrder=4 from dir 04-yarn, got $($tool.sortOrder)" }
if ([int]$tool.no -ne 0) { throw 'Get-ToolFromDirectory should leave menu no=0 before Assign-ToolMenuNumbers' }

$discovered = @(Discover-Tools | Where-Object { [string]$_.command -eq 'yarn' })
if ($discovered.Count -ne 1) { throw 'expected single yarn in Discover-Tools' }
if ([int]$discovered[0].no -ne 4) { throw "expected yarn menu no=4, got $($discovered[0].no)" }

$title = Resolve-ToolI18nLabel -ToolRoot $toolRoot -Key 'yarn.action.pin.name' -Fallback 'pin'
if ([string]::IsNullOrWhiteSpace($title)) { throw 'expected pin action title' }

$line = Resolve-YarnVersionFromVoltaListLine -Line 'package-manager yarn@4.5.0 (default)'
if ($line -ne '4.5.0') { throw "unexpected parsed yarn version: $line" }

$ctx = @{
    HasProject    = $true
    ProjectName   = 'demo-app'
    PackageJsonRel = 'package.json'
    PinnedVersion = '4.1.0'
}
$script:YarnBrowseInstallDotSourceOnly = $true
. (Join-Path $toolRoot 'lib\browse-install.ps1')
. (Join-Path $toolRoot 'lib\yarn-pin-select.ps1')
$script:YarnBrowseInstallDotSourceOnly = $false

$voltaInfo = @{ Map = @{ '4.1.0' = $true }; Default = '4.1.0' }
$msg = Format-YarnPinCatalogLineMessage -ToolRoot $toolRoot -PinContext $ctx -VoltaInfo $voltaInfo
if ([string]::IsNullOrWhiteSpace($msg)) { throw 'expected pin content line message' }

$remote = @((New-YarnVersionMenuItem -Version '4.2.0'))
$merged = Build-YarnPinMergedItems -BaseVersions $remote -VoltaInfo $voltaInfo -PinnedVersion '3.0.0'
$versions = @($merged | ForEach-Object { $_.Version })
if ($versions -notcontains '3.0.0') { throw 'expected pinned-not-installed version in merged list' }

Write-Host 'test-yarn-tool: OK'
