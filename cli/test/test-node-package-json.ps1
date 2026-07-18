$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$toolRoot = Join-Path $root 'package\tools\01-node'

. (Join-Path $toolRoot 'lib\volta-node.ps1')
Set-NodeVoltaToolRoot -ToolRoot $toolRoot

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("miao-pkg-json-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempDir | Out-Null
try {
    $path = New-NodeProjectPackageJson -Directory $tempDir
    $bytes = [System.IO.File]::ReadAllBytes($path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        throw 'package.json must not contain UTF-8 BOM'
    }

    $json = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    if ([string]$json.version -ne '0.0.0') { throw 'expected version 0.0.0 in new package.json' }
    if (-not $json.private) { throw 'expected private true in new package.json' }

    $repairDir = Join-Path $tempDir 'repair'
    New-Item -ItemType Directory -Path $repairDir | Out-Null
    $repairPath = Join-Path $repairDir 'package.json'
    $bomContent = [byte[]](0xEF, 0xBB, 0xBF) + [System.Text.Encoding]::UTF8.GetBytes("{`n  `"name`": `"demo`",`n  `"private`": true`n}`n")
    [System.IO.File]::WriteAllBytes($repairPath, $bomContent)
    if (-not (Repair-NodeProjectPackageJsonEncoding -PackageJsonPath $repairPath)) {
        throw 'expected BOM repair to succeed'
    }
    $repaired = [System.IO.File]::ReadAllBytes($repairPath)
    if ($repaired.Length -ge 3 -and $repaired[0] -eq 0xEF) {
        throw 'repaired package.json still has BOM'
    }
}
finally {
    Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'test-node-package-json: OK'
