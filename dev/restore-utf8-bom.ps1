param(
    [string]$Root = (Join-Path $PSScriptRoot '..\package')
)

$utf8Bom = New-Object System.Text.UTF8Encoding $true
$fixed = @()

Get-ChildItem -Path $Root -Filter '*.ps1' -Recurse | ForEach-Object {
    $path = $_.FullName
    $bytes = [System.IO.File]::ReadAllBytes($path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return
    }

    $text = [System.IO.File]::ReadAllText($path)
    if ($text -notmatch '[\u4e00-\u9fff\u2500-\u257f\u2550-\u256c]') {
        return
    }

    [System.IO.File]::WriteAllText($path, $text, $utf8Bom)
    $fixed += $path
}

if ($fixed.Count -eq 0) {
    Write-Host 'No files needed BOM restore.'
}
else {
    Write-Host "Restored UTF-8 BOM on $($fixed.Count) file(s):"
    $fixed | ForEach-Object { Write-Host "  $_" }
}
