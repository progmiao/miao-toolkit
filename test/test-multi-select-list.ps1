$ErrorActionPreference = 'Stop'
$lib = Join-Path (Split-Path $PSScriptRoot -Parent) 'package\core\lib'
. (Join-Path $lib 'config\Paths.ps1')
. (Join-Path $lib 'config\ListLayout.ps1')
. (Join-Path $lib 'config\I18n.ps1')
. (Join-Path $lib 'ui\console\Console-Menu.ps1')
. (Join-Path $lib 'ui\shell\SingleSelectList.ps1')
. (Join-Path $lib 'ui\shell\MultiSelectList.ps1')

$rows = ConvertTo-ShellListRows -Items @(
    [pscustomobject]@{ Version = '22.0.0' }
    [pscustomobject]@{ Version = '20.0.0' }
) -KeepSource -MapCells {
    param($Item, [int]$Index)
    @([string]$Item.Version)
} -GetEnabled {
    param($Item, [int]$Index)
    $Index -eq 0
}

$layout = New-ShellListColumnLayout -Widths @(20)
$built = Build-ShellMultiSelectListRowCache -Rows $rows -ColumnLayout $layout
$shell = @{ TestMultiListChecked = [System.Collections.Generic.HashSet[int]]::new() }
$checked = Get-ShellMultiSelectCheckedSet -Shell $shell -CacheKey 'Test'
$checked.Add(0) | Out-Null
$handlers = New-ShellMultiSelectListDrawHandlers -RowCache $built.RowCache -ColGap $built.ColGap `
    -CheckedIndexSet $checked

$specFromHandler = & $handlers['GetListRowSpec'] 0 $true 2 1 $true
if (-not $specFromHandler -or $specFromHandler.Text -notmatch '22\.0\.0') {
    throw 'GetListRowSpec handler closure should survive after New-ShellMultiSelectListDrawHandlers returns'
}

$spec = Build-ShellMultiSelectListRowSpec -RowCacheEntry $built.RowCache[0] -Selected $true -Checked $true `
    -NumWidth 2 -DisplayNumber 1 -Gap $built.ColGap
if ($spec.Text -notmatch '\[√\]' -or $spec.Text -notmatch '22\.0\.0') {
    throw 'multi-select row spec should include check mark and cell text'
}

$specDisabled = Build-ShellMultiSelectListRowSpec -RowCacheEntry $built.RowCache[1] -Selected $false -Checked $false `
    -NumWidth 2 -DisplayNumber 2 -Gap $built.ColGap
if ($specDisabled.Segments[0].Text -notmatch '\[X\]') {
    throw 'disabled row should use [X] check mark'
}

if ('[ ]' -ne (Format-ShellMultiSelectCheckMark -Checked $false -Enabled $true)) { throw 'unchecked mark' }
if ('[√]' -ne (Format-ShellMultiSelectCheckMark -Checked $true -Enabled $true)) { throw 'checked mark' }
if ('[X]' -ne (Format-ShellMultiSelectCheckMark -Checked $false -Enabled $false)) { throw 'disabled mark' }

$specOff = Build-ShellMultiSelectListRowSpec -RowCacheEntry $built.RowCache[0] -Selected $false -Checked $true `
    -NumWidth 2 -DisplayNumber 1 -Gap $built.ColGap
if ($specOff.Segments.Count -lt 2) {
    throw 'unselected multi-select row should use segments'
}

if (-not (Get-Command Invoke-ShellMultiSelectList -ErrorAction SilentlyContinue)) {
    throw 'Invoke-ShellMultiSelectList should be defined'
}

# null BodySegments should not produce null segment entries
$specNullBody = Build-ShellMultiSelectListRowSpec -RowCacheEntry @{
    BodyPlain    = 'test              '
    BodySegments = $null
    LineColor    = [System.ConsoleColor]::Gray
    Enabled      = $true
} -Selected $false -Checked $false -NumWidth 2 -DisplayNumber 1 -Gap $built.ColGap
foreach ($seg in $specNullBody.Segments) {
    if (-not $seg) { throw 'null BodySegments must not add null segment' }
}

Write-Host 'test-multi-select-list: OK'
