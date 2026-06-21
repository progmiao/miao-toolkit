$ErrorActionPreference = 'Stop'
$ver = if ($args.Count -gt 0) { [string]$args[0] } else { '16.12.0' }
$volta = (Get-Command volta -ErrorAction Stop).Source
$tmp = Join-Path $env:LOCALAPPDATA 'Volta\tmp'

$job = Start-Job -ScriptBlock {
    param($volta, $ver)
    & $volta install "node@$ver" | Out-Null
} -ArgumentList $volta, $ver

for ($n = 0; $n -lt 200 -and ($job.State -eq 'Running'); $n++) {
    Start-Sleep -Milliseconds 200
    if (-not (Test-Path -LiteralPath $tmp)) { continue }
    $files = @(Get-ChildItem -LiteralPath $tmp -Recurse -File -ErrorAction SilentlyContinue)
    $zipLike = @($files | Where-Object { $_.Extension -in @('.zip', '.tmp', '.partial', '.download') -or $_.Name -like '.tmp*' })
    $sum = [int64](($files | Measure-Object -Property Length -Sum).Sum)
    $zipSum = [int64](($zipLike | Measure-Object -Property Length -Sum).Sum)
    $top = $files | Sort-Object Length -Descending | Select-Object -First 1
    Write-Host "t=$n all=$sum zipLike=$zipSum top=$($top.Length) $($top.Name)"
}

Receive-Job $job -Wait | Out-Null
Remove-Job $job -Force
