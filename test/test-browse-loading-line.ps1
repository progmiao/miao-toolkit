$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$lib = Join-Path $root 'package\core\lib'
. (Join-Path $lib 'bootstrap\Load-Core.ps1') -LibDirectory $lib
Initialize-Paths -BinDirectory (Join-Path $root 'package\bin')

$toolRoot = Join-Path $root 'package\tools\01-node'
Initialize-PathsFromToolRoot -ToolRoot $toolRoot

$zh = Get-ToolI18n -ToolRoot $toolRoot -Key 'node.browse.loading' -Vars @{ spinner = '/' }
if ($zh -notmatch '^/ 正在加载') {
    throw "expected spinner-prefixed zh loading text, got: [$zh]"
}

$line = ' ' + $zh
if (-not $line.StartsWith(' / 正在加载')) {
    throw "expected list-indent loading line, got: [$line]"
}

Write-Host 'BROWSE LOADING LINE OK'
