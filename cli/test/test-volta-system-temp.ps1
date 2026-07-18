$ErrorActionPreference = 'Stop'
$ver = if ($args.Count -gt 0) { [string]$args[0] } else { '16.11.2' }
$volta = (Get-Command volta -ErrorAction Stop).Source

function Find-NodeZipCandidates {
    $roots = @($env:TEMP, (Join-Path $env:LOCALAPPDATA 'Temp'))
    $hits = @()
    foreach ($root in $roots | Select-Object -Unique) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        $hits += @(Get-ChildItem -LiteralPath $root -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match 'node|\.zip|\.tmp|\.part' })
        $hits += @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match 'node|volta|tmp' } |
            ForEach-Object {
                Get-ChildItem -LiteralPath $_.FullName -Recurse -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.Length -gt 10000 }
            })
    }
    return @($hits | Sort-Object Length -Descending | Select-Object -First 5)
}

$job = Start-Job -ScriptBlock {
    param($volta, $ver)
    & $volta install "node@$ver" | Out-Null
} -ArgumentList $volta, $ver

$last = ''
for ($n = 0; $n -lt 200 -and ($job.State -eq 'Running'); $n++) {
    Start-Sleep -Milliseconds 300
    $cands = Find-NodeZipCandidates
    $sig = ($cands | ForEach-Object { "$($_.Length)|$($_.FullName)" }) -join ';'
    if ($sig -ne $last) {
        Write-Host "t=$n"
        foreach ($c in $cands) { Write-Host "  $($c.Length) $($c.FullName)" }
        $last = $sig
    }
}

Receive-Job $job -Wait | Out-Null
Remove-Job $job -Force
