$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'package\tools\node\lib\volta-conpty.ps1')
$null = Ensure-VoltaConPtyType

$ver = if ($args.Count -gt 0) { [string]$args[0] } else { '25.1.0' }
$volta = (Get-Command volta -ErrorAction Stop).Source

Write-Host "volta=$volta"
Write-Host "install node@$ver via ConPTY..."

$session = New-Object MiaoVoltaConPtySession -ArgumentList @($volta, "install node@$ver")
$lineCount = 0
$percentHits = [System.Collections.Generic.List[int]]::new()
$deadline = [Environment]::TickCount + 180000

while (-not $session.HasExited -and [Environment]::TickCount -lt $deadline) {
    $line = $null
    while ($session.Queue.TryDequeue([ref]$line)) {
        $lineCount++
        $raw = [string]$line
        $clean = Get-VoltaInstallStreamLineCleanText -Line $raw
        $pct = Get-VoltaInstallStreamLinePercent -Line $clean
        if ($lineCount -le 50) {
            $hex = ($raw.ToCharArray() | ForEach-Object { '{0:X2}' -f [int][char]$_ }) -join ' '
            Write-Host "L$lineCount pct=$pct clean=[$clean]"
            if ($raw.Length -le 200) { Write-Host "  hex=$hex" }
        }
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

Write-Host "exit=$($session.ExitCode) lines=$lineCount distinctPercents=$($percentHits.Count) percents=$($percentHits -join ',')"
$session.Dispose()
