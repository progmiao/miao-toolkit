$ErrorActionPreference = 'Stop'
function Measure-DirScan {
    param([string]$Label, [string]$Path)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $sum = (Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum
    $sw.Stop()
    Write-Host "$Label bytes=$sum ms=$($sw.ElapsedMilliseconds)"
}

Measure-DirScan 'volta-root' (Join-Path $env:LOCALAPPDATA 'Volta')
Measure-DirScan 'volta-tmp' (Join-Path $env:LOCALAPPDATA 'Volta\tmp')
