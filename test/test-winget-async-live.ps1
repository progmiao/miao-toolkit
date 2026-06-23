$ErrorActionPreference = 'Stop'
$lib = Join-Path (Split-Path $PSScriptRoot -Parent) 'package\core\lib'
. (Join-Path $lib 'domain\Ensure-ToolDeps.ps1')
. (Join-Path $lib 'domain\Invoke-ToolDepPackage.ps1')

$seen = New-Object System.Collections.ArrayList
$stallWarns = 0
$result = Invoke-WingetDepProcess -ArgumentList @(
    'list', '--id', 'Volta.Volta', '-e', '--disable-interactivity', '--accept-source-agreements', '--output', 'json'
) -OnOutputLine {
    param($Line)
    [void]$seen.Add([string]$Line)
} -OnStallNotify {
    $script:stallWarns++
} -StallWarnMs 3000 -StallFailMs 60000

Write-Host "Exit: $($result.ExitCode) Lines: $($result.Lines.Count) Seen: $($seen.Count) StallWarns: $stallWarns TimedOut: $($result.TimedOut)"
if ($seen.Count -eq 0) {
    throw 'expected winget async output lines'
}
if ($stallWarns -gt 0) {
    throw "unexpected stall warnings ($stallWarns) while winget was producing spinner output"
}
Write-Host 'test-winget-async-live: OK'
