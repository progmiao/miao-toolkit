# Pack Miao for GitHub Release (bin + core + tools)
#
# From repo root:
#   .\release\pack.ps1
#   .\release\pack.ps1 -Version 0.1.0
#   .\release\pack.ps1 -OutputDir .\dist

param(
    [string]$Version = '',
    [string]$OutputDir = ''
)

$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path $PSScriptRoot -Parent
$PackageRoot = Join-Path $RepoRoot 'package'
$ManifestPath = Join-Path $PackageRoot 'core\manifest.json'

if (-not (Test-Path $ManifestPath)) {
    throw "manifest not found: $ManifestPath"
}

if ([string]::IsNullOrWhiteSpace($Version)) {
    $manifest = Get-Content -Raw -Path $ManifestPath -Encoding UTF8 | ConvertFrom-Json
    $Version = [string]$manifest.version
}

if ([string]::IsNullOrWhiteSpace($Version)) {
    throw 'version is empty; set package/core/manifest.json or use -Version'
}

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $RepoRoot 'dist'
}

$stage = Join-Path $env:TEMP "miao-pack-$Version\Miao"
$zipName = "Miao-$Version-win.zip"
$zipPath = Join-Path $OutputDir $zipName

foreach ($dir in @('bin', 'core', 'tools')) {
    $src = Join-Path $PackageRoot $dir
    if (-not (Test-Path $src)) {
        throw "missing package/$dir"
    }
}

Remove-Item -Recurse -Force (Split-Path $stage -Parent) -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path "$stage\bin", "$stage\core", "$stage\tools" | Out-Null

Copy-Item -Recurse -Force (Join-Path $PackageRoot 'bin\*')   "$stage\bin\"
Copy-Item -Recurse -Force (Join-Path $PackageRoot 'core\*')  "$stage\core\"
Copy-Item -Recurse -Force (Join-Path $PackageRoot 'tools\*') "$stage\tools\"

Get-ChildItem -Path "$stage\tools" -Recurse -Directory -Filter '_prototype' -ErrorAction SilentlyContinue |
    Remove-Item -Recurse -Force
Get-ChildItem -Path "$stage\tools" -Recurse -Filter 'DESIGN.md' -ErrorAction SilentlyContinue |
    Remove-Item -Force

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
if (Test-Path $zipPath) {
    Remove-Item -Force $zipPath
}

Compress-Archive -Path $stage -DestinationPath $zipPath -CompressionLevel Optimal

$hash = (Get-FileHash -Path $zipPath -Algorithm SHA256).Hash

Write-Host ''
Write-Host "Version : $Version"
Write-Host "ZIP     : $zipPath"
Write-Host "SHA256  : $hash"
Write-Host ''
Write-Host 'Layout: Miao\bin, Miao\core, Miao\tools -> %LOCALAPPDATA%\Miao\'
