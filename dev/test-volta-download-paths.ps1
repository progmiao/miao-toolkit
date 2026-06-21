$ErrorActionPreference = 'Stop'
$ver = if ($args.Count -gt 0) { [string]$args[0] } else { '16.14.2' }
$volta = (Get-Command volta -ErrorAction Stop).Source

$watchPaths = @(
    (Join-Path $env:LOCALAPPDATA 'Volta\tmp')
    (Join-Path $env:LOCALAPPDATA 'Volta\cache')
    (Join-Path $env:LOCALAPPDATA 'Volta\tools\inventory\node')
    (Join-Path $env:LOCALAPPDATA 'Volta\tools\image\node')
    $env:TEMP
)

function Get-PathBytes([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return [int64]0 }
    $sum = (Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum
    if ($null -eq $sum) { return [int64]0 }
    return [int64]$sum
}

$baseline = @{}
foreach ($p in $watchPaths) { $baseline[$p] = Get-PathBytes $p }

$job = Start-Job -ScriptBlock {
    param($volta, $ver)
    & $volta install "node@$ver"
    return $LASTEXITCODE
} -ArgumentList $volta, $ver

for ($n = 0; $n -lt 120 -and ($job.State -eq 'Running'); $n++) {
    Start-Sleep -Milliseconds 500
    $parts = @()
    foreach ($p in $watchPaths) {
        $cur = Get-PathBytes $p
        $delta = $cur - $baseline[$p]
        if ($delta -ne 0) {
            $parts += "$(Split-Path $p -Leaf):$delta"
        }
    }
    if ($parts.Count -gt 0) {
        Write-Host "t=$n $($parts -join ' | ')"
    }
}

$exitCode = Receive-Job $job -Wait
Remove-Job $job -Force
Write-Host "exit=$exitCode"
