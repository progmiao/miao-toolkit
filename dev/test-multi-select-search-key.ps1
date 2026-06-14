$ErrorActionPreference = 'Stop'
$lib = Join-Path (Split-Path $PSScriptRoot -Parent) 'package\core\lib'
. (Join-Path $lib 'config\Paths.ps1')
. (Join-Path $lib 'config\ListLayout.ps1')
. (Join-Path $lib 'config\I18n.ps1')
. (Join-Path $lib 'ui\console\Console-Menu.ps1')
. (Join-Path $lib 'ui\shell\SingleSelectList.ps1')
. (Join-Path $lib 'ui\shell\MultiSelectList.ps1')

if (12 -ne (Get-ShellMultiSelectSearchKeyWidth)) {
    throw 'SearchKey width should be 12'
}

$rows = ConvertTo-ShellListRows -Items @(
    [pscustomobject]@{ Version = '22.14.0' }
    [pscustomobject]@{ Version = '20.19.4' }
) -KeepSource -GetSearchKey {
    param($Item, [int]$Index)
    [string]$Item.Version
} -MapCells {
    param($Item, [int]$Index)
    @('[LTS]')
} -GetEnabled {
    param($Item, [int]$Index)
    $true
}

if ('22.14.0' -ne $rows[0].SearchKey) {
    throw 'row SearchKey should be version string'
}

$emptyTagRows = ConvertTo-ShellListRows -Items @(
    [pscustomobject]@{ Version = '18.0.0' }
) -KeepSource -GetSearchKey {
    param($Item, [int]$Index)
    [string]$Item.Version
} -MapCells {
    param($Item, [int]$Index)
    @('')
}
$normalizedEmpty = @(Normalize-ShellListRows -Rows $emptyTagRows -ColumnLayout (New-ShellListColumnLayout -Widths @(20)))
if ($normalizedEmpty.Count -ne 1 -or $normalizedEmpty[0].Cells.Count -ne 1) {
    throw 'rows with empty tag cell should normalize'
}

$idx = Resolve-ShellListRowSearchKeyPrefixIndex -Rows $rows -Prefix '22'
if ($idx -ne 0) {
    throw "prefix 22 should resolve to index 0, got $idx"
}

if (-not (Test-MenuSearchBufferPrefix -Items $rows -Buffer '20.19' -GetItemSearchKey {
        param($Row, [int]$Index) Get-ShellListRowSearchKey -Row $Row -Index $Index
    })) {
    throw 'Test-MenuSearchBufferPrefix should accept 20.19'
}

if (Test-MenuSearchBufferPrefix -Items $rows -Buffer '21' -GetItemSearchKey {
        param($Row, [int]$Index) Get-ShellListRowSearchKey -Row $Row -Index $Index
    }) {
    throw 'prefix 21 should not match any version'
}

$layout = New-ShellListColumnLayout -Widths @(24)
$built = Build-ShellMultiSelectListRowCache -Rows $rows -ColumnLayout $layout
if (-not $built.RowCache[0].SearchKey) {
    throw 'multi list row cache should carry SearchKey'
}

$spec = Build-ShellMultiSelectListRowSpec -RowCacheEntry $built.RowCache[0] -Selected $true -Checked $false `
    -NumWidth 12 -DisplayNumber 1 -Gap $built.ColGap -UseSearchKeyColumn -KeyWidth 12 -DisplayKey '22.14.0'
if ($spec.Text -notmatch '22\.14\.0') {
    throw "search key spec should show version: $($spec.Text)"
}
if ($spec.Text -notmatch '\[LTS\]') {
    throw 'search key spec should still include tags in body'
}

Write-Host 'test-multi-select-search-key: OK'
