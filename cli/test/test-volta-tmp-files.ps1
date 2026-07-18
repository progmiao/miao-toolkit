$ErrorActionPreference = 'Stop'
$ver = if ($args.Count -gt 0) { [string]$args[0] } else { '16.13.1' }
$volta = (Get-Command volta -ErrorAction Stop).Source
$tmp = Join-Path $env:LOCALAPPDATA 'Volta\tmp'

function Get-TmpSnapshot {
    if (-not (Test-Path -LiteralPath $tmp)) { return @() }
    return @(Get-ChildItem -LiteralPath $tmp -Recurse -File -ErrorAction SilentlyContinue |
        ForEach-Object { [pscustomobject]@{ Path = $_.FullName; Length = [int64]$_.Length } })
}

$job = Start-Job -ScriptBlock {
    param($volta, $ver)
    & $volta install "node@$ver" | Out-Null
    return $LASTEXITCODE
} -ArgumentList $volta, $ver

$lastSig = ''
for ($n = 0; $n -lt 600 -and ($job.State -eq 'Running'); $n++) {
    Start-Sleep -Milliseconds 250
    $files = Get-TmpSnapshot
    $sum = [int64](($files | Measure-Object -Property Length -Sum).Sum)
    $sig = ($files | Sort-Object Path | ForEach-Object { "$($_.Length)" }) -join ','
    if ($sig -ne $lastSig) {
        Write-Host "t=$n sum=$sum files=$($files.Count)"
        foreach ($f in ($files | Sort-Object Length -Descending | Select-Object -First 3)) {
            Write-Host "  $($f.Length) $($f.Path)"
        }
        $lastSig = $sig
    }
}

$exitCode = Receive-Job $job -Wait
Remove-Job $job -Force
Write-Host "exit=$exitCode"
