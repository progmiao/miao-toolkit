$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'package\tools\01-node\lib\volta-conpty.ps1')
$null = Ensure-VoltaConPtyType

$ver = if ($args.Count -gt 0) { [string]$args[0] } else { '14.21.3' }
$volta = (Get-Command volta -ErrorAction Stop).Source
$argsLine = if ($args.Count -gt 1) { [string]$args[1] } else { "install --verbose node@$ver" }

Write-Host "cmd: volta $argsLine"
$session = New-Object MiaoVoltaConPtySession -ArgumentList @($volta, $argsLine)
$lineCount = 0
$percentHits = [System.Collections.Generic.List[int]]::new()
$deadline = [Environment]::TickCount + 180000

while (-not $session.HasExited -and [Environment]::TickCount -lt $deadline) {
    $line = $null
    while ($session.Queue.TryDequeue([ref]$line)) {
        $lineCount++
        $clean = Get-VoltaInstallStreamLineCleanText -Line $line
        $pct = Get-VoltaInstallStreamLinePercent -Line $clean
        if ($lineCount -le 80) { Write-Host "L$lineCount pct=$pct [$clean]" }
        if ($pct -ge 0 -and ($percentHits.Count -eq 0 -or $percentHits[$percentHits.Count - 1] -ne $pct)) {
            $percentHits.Add($pct)
        }
    }
    Start-Sleep -Milliseconds 30
}

while ($session.Queue.TryDequeue([ref]$line)) {
    $lineCount++
    $clean = Get-VoltaInstallStreamLineCleanText -Line $line
    $pct = Get-VoltaInstallStreamLinePercent -Line $clean
    if ($pct -ge 0 -and ($percentHits.Count -eq 0 -or $percentHits[$percentHits.Count - 1] -ne $pct)) {
        $percentHits.Add($pct)
    }
}

Write-Host "exit=$($session.ExitCode) lines=$lineCount percents=$($percentHits -join ',')"
$session.Dispose()
