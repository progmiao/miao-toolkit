$utf8bom = New-Object System.Text.UTF8Encoding $true
$root = Split-Path $PSScriptRoot -Parent

function Write-BomRelative {
    param([string]$FullPath, [string]$RepoRoot)
    $rel = $FullPath.Substring($RepoRoot.Length).TrimStart('\', '/')
    Write-Host "BOM: $rel"
}

Get-ChildItem -Path (Join-Path $root 'package') -Filter '*.ps1' -Recurse |
    Where-Object { $_.FullName -notmatch '_prototype' } |
    ForEach-Object {
        $text = [System.IO.File]::ReadAllText($_.FullName)
        [System.IO.File]::WriteAllText($_.FullName, $text, $utf8bom)
        Write-BomRelative -FullPath $_.FullName -RepoRoot $root
    }

Get-ChildItem -Path $PSScriptRoot -Filter '*.ps1' |
    ForEach-Object {
        $text = [System.IO.File]::ReadAllText($_.FullName)
        [System.IO.File]::WriteAllText($_.FullName, $text, $utf8bom)
        Write-BomRelative -FullPath $_.FullName -RepoRoot $root
    }

Get-ChildItem -Path (Join-Path $root 'release') -Filter '*.ps1' -ErrorAction SilentlyContinue |
    ForEach-Object {
        $text = [System.IO.File]::ReadAllText($_.FullName)
        [System.IO.File]::WriteAllText($_.FullName, $text, $utf8bom)
        Write-BomRelative -FullPath $_.FullName -RepoRoot $root
    }
