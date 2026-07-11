# test-winget-update-check.ps1 — WinGet 更新检查网络预检与超时

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$lib = Join-Path $root 'package\core\lib'
. (Join-Path $lib 'bootstrap\Load-Core.ps1') -LibDirectory $lib
. (Join-Path $lib 'domain\Ensure-ToolDeps.ps1')

if (-not (Get-Command Resolve-WingetPackageUpdateCheck -ErrorAction SilentlyContinue)) {
    throw 'Resolve-WingetPackageUpdateCheck missing'
}
if (-not (Get-Command Test-WingetCatalogNetworkReachable -ErrorAction SilentlyContinue)) {
    throw 'Test-WingetCatalogNetworkReachable missing'
}
if ([int]$script:WingetUpdateCheckNetworkPreflightSec -ne 5) {
    throw 'expected network preflight timeout default 5s'
}
if ([int]$script:WingetUpdateCheckCommandTimeoutSec -ne 15) {
    throw 'expected update check command timeout default 15s'
}

$legacy = Test-WingetPackageUpdateAvailable -PackageId '' -InstalledVersion '1.0.0'
if ($legacy) { throw 'empty package id should not report update available' }

$offline = Resolve-WingetPackageUpdateCheck -PackageId 'Anthropic.ClaudeCode' `
    -InstalledVersion '1.0.0' -SkipNetworkPreflight:$true -CommandTimeoutSec 1 -OnPulse { }
if ($offline.Skipped -and [string]$offline.SkipReason -eq 'timeout') {
    # winget too slow in this environment; timeout path verified
}
elseif ($offline.Skipped -and [string]$offline.SkipReason -eq 'network') {
    throw 'SkipNetworkPreflight should not skip for network'
}
elseif (-not $offline.PSObject.Properties['Available']) {
    throw 'Resolve-WingetPackageUpdateCheck should return Available property'
}

$networkSkipped = Resolve-WingetPackageUpdateCheck -PackageId 'Anthropic.ClaudeCode' `
    -InstalledVersion '1.0.0' -NetworkPreflightTimeoutSec 1 `
    -CommandTimeoutSec 1 `
    -OnPulse { }
if (-not $networkSkipped.Skipped) {
    $reachable = Test-WingetCatalogNetworkReachable -TimeoutSec 2
    if (-not $reachable) {
        throw 'expected skip when winget catalog unreachable'
    }
}

Write-Host 'test-winget-update-check: OK'
