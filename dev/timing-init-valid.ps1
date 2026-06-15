$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$lib = Join-Path $root 'package\core\lib'
. (Join-Path $lib 'bootstrap\Load-Core.ps1') -LibDirectory $lib
Initialize-Paths -BinDirectory (Join-Path $root 'package\bin')
. (Join-Path $lib 'config\ToolkitInit.ps1')

$sw = [Diagnostics.Stopwatch]::StartNew()
$valid = Test-ToolkitInitValid
$tValid = $sw.ElapsedMilliseconds

$sw.Restart()
$fp = New-ToolkitInitFingerprint
$tFp = $sw.ElapsedMilliseconds

$sw.Restart()
$tools = @(Get-ToolkitTools)
$tTools = $sw.ElapsedMilliseconds

$sw.Restart()
$tools2 = @(Get-ToolkitTools)
$tTools2 = $sw.ElapsedMilliseconds

$homeRowsPath = Get-ToolkitInitHomeRowsPath -Locale (Get-CurrentLocale)
$sw.Restart()
if (Test-Path $homeRowsPath) {
    $null = Get-Content -Raw -Path $homeRowsPath -Encoding UTF8 | ConvertFrom-Json
}
$tHomeJson = $sw.ElapsedMilliseconds

Write-Output "initValid=$valid"
Write-Output "Test-ToolkitInitValid=${tValid}ms"
Write-Output "New-ToolkitInitFingerprint=${tFp}ms"
Write-Output "Get-ToolkitTools(1st)=${tTools}ms count=$($tools.Count)"
Write-Output "Get-ToolkitTools(2nd)=${tTools2}ms"
Write-Output "ReadHomeRowsJson=${tHomeJson}ms"
