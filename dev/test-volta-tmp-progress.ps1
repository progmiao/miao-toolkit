$ErrorActionPreference = 'Stop'
$ver = if ($args.Count -gt 0) { [string]$args[0] } else { '16.13.2' }
$volta = (Get-Command volta -ErrorAction Stop).Source
$tmp = Join-Path $env:LOCALAPPDATA 'Volta\tmp'

function Get-TmpBytes {
    if (-not (Test-Path -LiteralPath $tmp)) { return [int64]0 }
    $sum = (Get-ChildItem -LiteralPath $tmp -Recurse -File -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum
    if ($null -eq $sum) { return [int64]0 }
    return [int64]$sum
}

$url = "https://nodejs.org/dist/v$ver/node-v$ver-win-x64.zip"
$resp = Invoke-WebRequest -Uri $url -Method Head -UseBasicParsing -TimeoutSec 8
$total = [int64]$resp.Headers['Content-Length']
Write-Host "zipBytes=$total"

$baseline = Get-TmpBytes
Write-Host "baseline=$baseline"

$job = Start-Job -ScriptBlock {
    param($volta, $ver)
    & $volta install "node@$ver" | Out-Null
    return $LASTEXITCODE
} -ArgumentList $volta, $ver

$lastPct = -1
for ($n = 0; $n -lt 120 -and ($job.State -eq 'Running'); $n++) {
    Start-Sleep -Milliseconds 200
    $delta = (Get-TmpBytes) - $baseline
    $pct = if ($total -gt 0 -and $delta -gt 0) {
        [Math]::Max(0, [Math]::Min(99, [int][Math]::Round(100.0 * $delta / [double]$total)))
    }
    else { 0 }
    if ($pct -ne $lastPct) {
        Write-Host "t=$n delta=$delta pct=$pct"
        $lastPct = $pct
    }
}

$exitCode = Receive-Job $job -Wait
Remove-Job $job -Force
Write-Host "exit=$exitCode steps=$($lastPct + 1)"
