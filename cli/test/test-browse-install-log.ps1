$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$coreLib = Join-Path $root 'package\core\lib'
. (Join-Path $coreLib 'bootstrap\Load-Core.ps1') -LibDirectory $coreLib

$toolRoot = Join-Path $root 'package\tools\01-node'
$coreLibNode = Join-Path $toolRoot '..\..\core\lib'
. (Join-Path $toolRoot 'lib\browse-install-run.ps1')

$log = New-NodeBrowseInstallLog -ViewportRows 5 -BrandInnerWidth 60
Write-NodeBrowseInstallLogLine -Log $log -Text 'hello' -Kind 'heading' -WithTimestamp
Write-NodeBrowseInstallLogLine -Log $log -Text 'volta install node@20' -WithTimestamp
Write-NodeBrowseInstallLogLine -Log $log -Text ('下载 node@24.11.1：https://nodejs.org/dist/v24.11.1/node-v24.11.1-win-x64.zip') -Kind 'text' -WithTimestamp

if ($log.Lines.Count -lt 3) {
    throw "expected at least 3 log lines, got $($log.Lines.Count)"
}
if ([string]::IsNullOrWhiteSpace($log.Lines[2].Timestamp)) {
    throw 'download log should keep timestamp column'
}
if ($log.Lines[2].Text -match '^https://') {
    throw 'long download log should wrap with timestamp on first line only'
}

Write-Host "test-browse-install-log: OK ($($log.Lines.Count) lines)"
