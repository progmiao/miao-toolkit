$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'package\tools\node\lib\volta-conpty.ps1')
$null = Ensure-VoltaConPtyType

$ver = if ($args.Count -gt 0) { [string]$args[0] } else { '18.20.4' }
$volta = (Get-Command volta -ErrorAction Stop).Source

$voltaRoot = Join-Path $env:LOCALAPPDATA 'Volta'
$tempRoot = $env:TEMP

function Get-TreeBytes([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return [int64]0 }
    $sum = (Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum
    if ($null -eq $sum) { return [int64]0 }
    return [int64]$sum
}

$baseVolta = Get-TreeBytes $voltaRoot
$baseTemp = Get-TreeBytes $tempRoot
Write-Host "baseline volta=$baseVolta temp=$baseTemp"

$session = New-Object MiaoVoltaConPtySession -ArgumentList @($volta, "install node@$ver")
$lineCount = 0
$deadline = [Environment]::TickCount + 120000
$sample = 0

while (-not $session.HasExited -and [Environment]::TickCount -lt $deadline) {
    $line = $null
    while ($session.Queue.TryDequeue([ref]$line)) {
        $lineCount++
        if ($lineCount -le 20) {
            Write-Host "line$lineCount | $(Get-VoltaInstallStreamLineCleanText -Line $line)"
        }
    }

    if ($sample -lt 20) {
        $v = Get-TreeBytes $voltaRoot
        $t = Get-TreeBytes $tempRoot
        Write-Host "t=$sample voltaDelta=$($v - $baseVolta) tempDelta=$($t - $baseTemp)"
        $sample++
        Start-Sleep -Milliseconds 500
    }
    else {
        Start-Sleep -Milliseconds 50
    }
}

while ($session.Queue.TryDequeue([ref]$line)) {
    $lineCount++
    if ($lineCount -le 30) {
        Write-Host "line$lineCount | $(Get-VoltaInstallStreamLineCleanText -Line $line)"
    }
}

Write-Host "exit=$($session.ExitCode) lines=$lineCount"
$session.Dispose()
