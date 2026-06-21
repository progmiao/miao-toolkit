$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$ver = if ($args.Count -gt 0) { [string]$args[0] } else { '18.20.4' }
$volta = (Get-Command volta -ErrorAction Stop).Source
$outFile = Join-Path $root 'dev\_volta-out.txt'
$errFile = Join-Path $root 'dev\_volta-err.txt'

Remove-Item $outFile, $errFile -ErrorAction SilentlyContinue

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $volta
$psi.Arguments = "install node@$ver"
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true

$proc = [System.Diagnostics.Process]::Start($psi)
$stdout = $proc.StandardOutput.ReadToEnd()
$stderr = $proc.StandardError.ReadToEnd()
$proc.WaitForExit()

Set-Content -LiteralPath $outFile -Value $stdout -Encoding UTF8
Set-Content -LiteralPath $errFile -Value $stderr -Encoding UTF8

Write-Host "exit=$($proc.ExitCode) stdoutLen=$($stdout.Length) stderrLen=$($stderr.Length)"
if ($stderr.Length -gt 0) {
    Write-Host '--- stderr preview ---'
    $preview = if ($stderr.Length -gt 800) { $stderr.Substring(0, 800) } else { $stderr }
    Write-Host $preview
}
if ($stdout.Length -gt 0) {
    Write-Host '--- stdout preview ---'
    $preview = if ($stdout.Length -gt 800) { $stdout.Substring(0, 800) } else { $stdout }
    Write-Host $preview
}
