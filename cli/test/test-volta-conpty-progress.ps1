$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'package\tools\01-node\lib\volta-conpty.ps1')
$null = Ensure-VoltaConPtyType

$ver = if ($args.Count -gt 0) { [string]$args[0] } else { '20.17.0' }
$voltaCmd = (Get-Command volta -ErrorAction Stop).Source

try { & $voltaCmd uninstall "node@$ver" 2>&1 | Out-Null } catch { }

$session = New-Object MiaoVoltaConPtySession -ArgumentList @($voltaCmd, "install node@$ver")
$percentHits = [System.Collections.Generic.List[int]]::new()
$deadline = [Environment]::TickCount + 120000

while (-not $session.HasExited -and [Environment]::TickCount -lt $deadline) {
    $line = $null
    while ($session.Queue.TryDequeue([ref]$line)) {
        $clean = Get-VoltaInstallStreamLineCleanText -Line $line
        if ([string]::IsNullOrWhiteSpace($clean)) { continue }

        Write-Host "raw | $clean"

        $pct = Get-VoltaInstallStreamLinePercent -Line $clean
        if ($pct -ge 0) {
            if ($percentHits.Count -eq 0 -or $percentHits[$percentHits.Count - 1] -ne $pct) {
                $percentHits.Add($pct)
                Write-Host "pct=$pct | $clean"
            }
            continue
        }

        if ($clean -match '(?i)^(Fetching|Unpacking|success|error)') {
            Write-Host "msg | $clean"
        }
    }
    Start-Sleep -Milliseconds 30
}

Write-Host "exit=$($session.ExitCode) distinctPercentSteps=$($percentHits.Count) max=$(
    if ($percentHits.Count -gt 0) { ($percentHits | Measure-Object -Maximum).Maximum } else { -1 }
)"
$session.Dispose()

if ($percentHits.Count -lt 3) {
    throw "expected multiple progress updates from ConPTY, got $($percentHits.Count)"
}
