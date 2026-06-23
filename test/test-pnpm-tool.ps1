$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$toolRoot = Join-Path $root 'package\tools\02-pnpm'
$coreLib = Join-Path $toolRoot '..\..\core\lib'

. (Join-Path $coreLib 'bootstrap\Load-Core.ps1') -LibDirectory $coreLib
Initialize-Paths -BinDirectory (Join-Path $root 'package\bin')
Initialize-PathsFromToolRoot -ToolRoot $toolRoot
. (Join-Path $toolRoot 'lib\volta-pnpm.ps1')
Set-PnpmVoltaToolRoot -ToolRoot $toolRoot

$configPath = Join-Path $toolRoot 'index.json'
$config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([int]$config.no -ne 3) { throw 'expected pnpm tool no=3' }
if ([string]$config.command -ne 'pnpm') { throw 'expected command pnpm' }

$tool = Get-ToolFromDirectory -ToolRoot $toolRoot
if (-not $tool) { throw 'Get-ToolFromDirectory failed for pnpm' }

$title = Resolve-ToolI18nLabel -ToolRoot $toolRoot -Key 'pnpm.action.pin.name' -Fallback 'pin'
if ([string]::IsNullOrWhiteSpace($title)) { throw 'expected pin action title' }

$line = Resolve-PnpmVersionFromVoltaListLine -Line 'package-manager pnpm@9.15.0 (default)'
if ($line -ne '9.15.0') { throw "unexpected parsed pnpm version: $line" }

$ctx = @{
    HasProject    = $true
    ProjectName   = 'demo-app'
    PackageJsonRel = 'package.json'
    PinnedVersion = '9.1.0'
}
$script:PnpmBrowseInstallDotSourceOnly = $true
. (Join-Path $toolRoot 'lib\browse-install.ps1')
. (Join-Path $toolRoot 'lib\pnpm-pin-select.ps1')
$script:PnpmBrowseInstallDotSourceOnly = $false

$voltaInfo = @{ Map = @{ '9.1.0' = $true }; Default = '9.1.0' }
$msg = Format-PnpmPinCatalogLineMessage -ToolRoot $toolRoot -PinContext $ctx -VoltaInfo $voltaInfo
if ([string]::IsNullOrWhiteSpace($msg)) { throw 'expected pin content line message' }

$remote = @((New-PnpmVersionMenuItem -Version '9.2.0'))
$merged = Build-PnpmPinMergedItems -BaseVersions $remote -VoltaInfo $voltaInfo -PinnedVersion '8.0.0'
$versions = @($merged | ForEach-Object { $_.Version })
if ($versions -notcontains '8.0.0') { throw 'expected pinned-not-installed version in merged list' }

Write-Host 'test-pnpm-tool: OK'
