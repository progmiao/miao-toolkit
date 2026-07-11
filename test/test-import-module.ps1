$ErrorActionPreference = 'Stop'
$lib = Join-Path (Split-Path $PSScriptRoot -Parent) 'package\core\lib'
. (Join-Path $lib 'bootstrap\Load-Core.ps1') -LibDirectory $lib

Import-MiaoModule -Name Lang
if (-not (Get-Command Invoke-LangCommand -ErrorAction SilentlyContinue)) {
    Write-Host 'FAIL: Invoke-LangCommand'
    exit 1
}
Write-Host 'OK: Lang'

Import-MiaoModule -Name Install
if (-not (Get-Command Get-ToolDepInstalled -ErrorAction SilentlyContinue)) {
    Write-Host 'FAIL: Get-ToolDepInstalled'
    exit 1
}
Write-Host 'OK: Install'

Import-MiaoModule -Name Tool
if (-not (Get-Command Invoke-Tool -ErrorAction SilentlyContinue)) {
    Write-Host 'FAIL: Invoke-Tool'
    exit 1
}
Write-Host 'OK: Tool'

Write-Host 'ALL OK'
