$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$coreLib = Join-Path $root 'package\core\lib'
. (Join-Path $coreLib 'bootstrap\Load-Core.ps1') -LibDirectory $coreLib

$toolRoot = Join-Path $root 'package\tools\node'
$coreLibNode = Join-Path $toolRoot '..\..\core\lib'
. (Join-Path $toolRoot 'lib\browse-install-run.ps1')

$log = New-NodeBrowseInstallLog -ViewportRows 5 -BrandInnerWidth 60
Write-NodeBrowseInstallLogLine -Log $log -Text 'hello' -Kind 'heading' -WithTimestamp
Write-NodeBrowseInstallLogLine -Log $log -Text 'volta install node@20'

if ($log.Lines.Count -lt 2) {
    throw "expected at least 2 log lines, got $($log.Lines.Count)"
}

Write-Host "test-browse-install-log: OK ($($log.Lines.Count) lines)"
