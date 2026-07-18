$ErrorActionPreference = 'Stop'
$env:MIAO_DEV = '1'
$env:MIAO_SKIP_DEPS = '1'

$root = Split-Path $PSScriptRoot -Parent
$lib = Join-Path $root 'package\core\lib'
. (Join-Path $lib 'bootstrap\Load-Core.ps1') -LibDirectory $lib
Initialize-Paths -BinDirectory (Join-Path $root 'package\bin')

if (Test-ToolkitInitValid) { throw 'expected invalid init before first build' }

# 首页不再承担跳转；由 Session ToolList 在初始化无效时压入 Init
$stack = @(Get-ShellInitialViewStack -InitialView 'ToolList')
if ($stack.Count -ne 1 -or $stack[0] -ne 'ToolList') { throw 'unexpected initial stack' }

Write-Host 'HOME INIT GATE OK'
