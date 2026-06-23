$ErrorActionPreference = 'Stop'
$ver = '16.20.0'
$voltaRoot = Join-Path $env:LOCALAPPDATA 'Volta'

function Get-DirBytes([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return [int64]0 }
    return [int64]((Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum)
}

$baseline = Get-DirBytes $voltaRoot
Write-Host "baseline=$baseline"

$url = "https://nodejs.org/dist/v$ver/node-v$ver-win-x64.zip"
try {
    $resp = Invoke-WebRequest -Uri $url -Method Head -UseBasicParsing -TimeoutSec 10
    $len = $resp.Headers['Content-Length']
    Write-Host "HEAD Content-Length=$len type=$($len.GetType().FullName)"
}
catch {
    Write-Host "HEAD failed: $($_.Exception.Message)"
}

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = (Get-Command volta).Source
$psi.Arguments = "install node@$ver"
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.UseShellExecute = $false
$p = [System.Diagnostics.Process]::Start($psi)

for ($n = 0; $n -lt 60 -and -not $p.HasExited; $n++) {
    Start-Sleep -Milliseconds 500
    $sum = Get-DirBytes $voltaRoot
    $tmp = Get-DirBytes (Join-Path $voltaRoot 'tmp')
    Write-Host "t=$n total=$sum delta=$($sum - $baseline) tmp=$tmp"
}

$p.WaitForExit()
Write-Host "exit=$($p.ExitCode)"
