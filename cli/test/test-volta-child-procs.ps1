$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'package\tools\01-node\lib\volta-conpty.ps1')
$null = Ensure-VoltaConPtyType

$ver = if ($args.Count -gt 0) { [string]$args[0] } else { '14.19.0' }
$volta = (Get-Command volta -ErrorAction Stop).Source

$session = New-Object MiaoVoltaConPtySession -ArgumentList @($volta, "install node@$ver")
$seen = @{}
$deadline = [Environment]::TickCount + 120000

while (-not $session.HasExited -and [Environment]::TickCount -lt $deadline) {
    Get-CimInstance Win32_Process -Filter "Name='volta.exe' OR Name='node.exe' OR CommandLine LIKE '%volta%'" |
        ForEach-Object {
            $key = "$($_.ProcessId)|$($_.CommandLine)"
            if (-not $seen.ContainsKey($key)) {
                $seen[$key] = $true
                Write-Host "PID=$($_.ProcessId) $($_.CommandLine)"
            }
        }
    Start-Sleep -Milliseconds 300
}

Write-Host "exit=$($session.ExitCode) lines=$($session.Queue.Count)"
$session.Dispose()
