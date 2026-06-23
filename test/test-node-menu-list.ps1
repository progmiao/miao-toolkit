$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$lib = Join-Path $root 'package\core\lib'
. (Join-Path $lib 'bootstrap\Load-Core.ps1') -LibDirectory $lib
Initialize-Paths -BinDirectory (Join-Path $root 'package\bin')

$env:MIAO_CACHE = '1'
if (Test-Path (Join-Path $env:APPDATA 'Miao\cache\manifest.json')) {
    # use existing cache
}
else {
    Invoke-ToolkitCacheBuild | Out-Null
}

Import-MiaoModule -Name Tool
$shell = Initialize-ToolkitShell
$toolRoot = Join-Path $root 'package\tools\01-node'
$config = Get-Content (Join-Path $toolRoot 'index.json') -Raw -Encoding UTF8 | ConvertFrom-Json

$mainParams = @{
    Config       = $config
    ToolRoot     = $toolRoot
    ToolkitShell = $shell
}
& (Join-Path $toolRoot 'lib\main.ps1') @mainParams
