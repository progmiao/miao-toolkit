# test-shell-list-search.ps1 — 列表搜索归一化与 buffer 匹配

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$lib = Join-Path $root 'package\core\lib'
. (Join-Path $lib 'bootstrap\Load-Core.ps1') -LibDirectory $lib

if ('anthropicbuiltin' -ne (Normalize-ShellListSearchText -Text 'anthropic-builtin')) {
    throw 'Normalize-ShellListSearchText failed'
}

$row = New-ShellListRow -Id 'a' -Cells @('superpowers@official', '1.0', 'desc')
$rows = @($row)

$searchCfg = Resolve-ShellListSearchConfig -SearchConfig @{ Columns = @(0) }
$idx = Resolve-ShellListInputBufferIndex -Rows $rows -Buffer 'su' -InputMode Letter -SearchConfig $searchCfg
if ($idx -ne 0) { throw "letter prefix match failed, got $idx" }

$defaultCfg = Resolve-ShellListSearchConfig -SearchConfig @{}
$idxNum = Resolve-ShellListInputBufferIndex -Rows $rows -Buffer '1' -InputMode Number -SearchConfig $defaultCfg
if ($idxNum -ne 0) { throw "number match failed, got $idxNum" }

$slashKey = [System.ConsoleKeyInfo]::new('/', [ConsoleKey]::Oem2, $false, $false, $false)
if (-not (Test-ShellListLetterSearchToggleKey -Key $slashKey -ToggleKey 'Slash')) {
    throw 'slash Oem2 toggle key failed'
}

$slashCharKey = [System.ConsoleKeyInfo]::new('/', [ConsoleKey]::NoName, $false, $false, $false)
if (-not (Test-ShellListLetterSearchToggleKey -Key $slashCharKey -ToggleKey '/')) {
    throw 'slash char toggle key failed'
}

$numpadSlashKey = [System.ConsoleKeyInfo]::new('/', [ConsoleKey]::Divide, $false, $false, $false)
if (-not (Test-ShellListLetterSearchSlashKey -Key $numpadSlashKey)) {
    throw 'slash numpad toggle key failed'
}

$ctrlFKey = [System.ConsoleKeyInfo]::new('f', [ConsoleKey]::F, $false, $false, $true)
if (-not (Test-ShellListLetterSearchToggleKey -Key $ctrlFKey -ToggleKey 'ControlF')) {
    throw 'ControlF toggle key failed'
}
if (Test-ShellListLetterSearchToggleKey -Key $ctrlFKey -ToggleKey 'Slash') {
    throw 'ControlF should not match Slash toggle'
}

if ('/' -ne (Get-ShellListLetterSearchToggleKeyDisplay -ToggleKey 'Slash')) {
    throw 'slash toggle display failed'
}
if ('/' -ne (Get-ShellListLetterSearchToggleKeyDisplay -ToggleKey '/')) {
    throw 'slash alias toggle display failed'
}

$slashAliasCfg = Resolve-ShellListSearchConfig -SearchConfig @{ LetterToggleKey = '/' }
if ([string]$slashAliasCfg.LetterToggleKey -ne 'Slash') {
    throw 'slash alias config should normalize to Slash'
}

$config = Resolve-ShellListSearchConfig -SearchConfig $null
if ($config.Columns.Count -ne 1 -or [int]$config.Columns[0] -ne 0) {
    throw 'default search columns should be @(0)'
}
if ([string]$config.LetterToggleKey -ne 'Slash') {
    throw 'default letter toggle key should be Slash'
}

Write-Host 'test-shell-list-search: OK'
