# Build Vue UI into WPF wwwroot, then compile host
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$ui = Join-Path $PSScriptRoot 'ui'
$hostProj = Join-Path $PSScriptRoot 'src\Miao.App'
$www = Join-Path $hostProj 'wwwroot'

Push-Location $ui
try {
    if (-not (Test-Path 'node_modules')) { npm install }
    npm run build
}
finally {
    Pop-Location
}

if (Test-Path $www) { Remove-Item -Recurse -Force $www }
New-Item -ItemType Directory -Path $www | Out-Null
Copy-Item -Recurse -Force (Join-Path $ui 'dist\*') $www

dotnet build (Join-Path $hostProj 'Miao.App.csproj') -c Release
Write-Host "OK -> $hostProj\bin\Release\net10.0-windows\Miao.exe"
