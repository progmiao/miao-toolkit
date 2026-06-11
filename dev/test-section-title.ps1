$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$lib = Join-Path $root 'package\core\lib'
$bin = Join-Path $root 'package\bin'
$toolRoot = Join-Path $root 'package\tools\node'

. (Join-Path $lib 'bootstrap\Load-Core.ps1') -LibDirectory $lib
. (Join-Path $lib 'config\Paths.ps1')
Initialize-Paths -BinDirectory $bin
Import-MiaoModule -Name Tool

$tool = Get-ToolFromDirectory -ToolRoot $toolRoot
. (Join-Path $lib 'domain\Invoke-ToolkitDepOperation.ps1')

$title = Get-ToolSectionTitle -Tool $tool
$unrecognized = Get-I18n -Key 'common.unrecognized'

Write-Host "tool.name=$($tool.name)"
Write-Host "sectionTitle=$title"

if ($title -eq $unrecognized) {
    throw 'Get-ToolSectionTitle returned unrecognized'
}
if ([string]::IsNullOrWhiteSpace($title)) {
    throw 'Get-ToolSectionTitle returned empty'
}

Write-Host 'test-section-title: OK'
