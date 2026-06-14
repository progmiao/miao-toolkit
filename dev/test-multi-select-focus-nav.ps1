$ErrorActionPreference = 'Stop'
$lib = Join-Path (Split-Path $PSScriptRoot -Parent) 'package\core\lib'
. (Join-Path $lib 'config\ListLayout.ps1')
. (Join-Path $lib 'config\Paths.ps1')
. (Join-Path $lib 'config\I18n.ps1')
. (Join-Path $lib 'ui\console\Console-Menu.ps1')
. (Join-Path $lib 'ui\shell\SingleSelectList.ps1')
. (Join-Path $lib 'ui\shell\MultiSelectList.ps1')

function Test-RedrawClosureReadsLiveIndex {
    $selectedIndex = 0
    $redraw = {
        return $selectedIndex
    }
    $selectedIndex = 1
    $result = & $redraw
    if ($result -ne 1) {
        throw "redraw closure should read live selectedIndex=1, got $result"
    }
}

Test-RedrawClosureReadsLiveIndex

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

if ((Find-ShellMultiSelectFirstFocusIndex -Rows $rows) -ne 0) {
    throw 'initial focus should be first row'
}

$layout = New-ShellListColumnLayout -Widths @(20)
$built = Build-ShellMultiSelectListRowCache -Rows $rows -ColumnLayout $layout
$shell = @{}
$checked = Get-ShellMultiSelectCheckedSet -Shell $shell -CacheKey 'Nav'
$handlers = New-ShellMultiSelectListDrawHandlers -RowCache $built.RowCache -ColGap $built.ColGap `
    -CheckedIndexSet $checked

$specDisabledFocused = Build-ShellMultiSelectListRowSpec -RowCacheEntry $built.RowCache[1] `
    -Selected $true -Checked $false -NumWidth 2 -DisplayNumber 2 -Gap $built.ColGap
if ($specDisabledFocused.Background -ne [System.ConsoleColor]::Cyan) {
    throw 'disabled row should still show focus highlight when selected'
}
if ($specDisabledFocused.Text -notmatch '\[X\]') {
    throw 'disabled focused row should show [X] mark'
}

Write-Host 'test-multi-select-focus-nav: OK'
