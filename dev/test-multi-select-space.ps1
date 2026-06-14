$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$coreLib = Join-Path $root 'package\core\lib'
. (Join-Path $coreLib 'bootstrap\Load-Core.ps1') -LibDirectory $coreLib
Initialize-Paths -BinDirectory (Join-Path $root 'package\bin')

# Simulate browse-install child script scope
$child = {
    param($CoreLib, $ToolRoot)

    . (Join-Path $CoreLib 'ui\console\Console-Menu.ps1')
    . (Join-Path $CoreLib 'ui\shell\Nav.ps1')
    . (Join-Path $CoreLib 'ui\shell\SystemToolbar.ps1')
    . (Join-Path $CoreLib 'ui\shell\SingleSelectList.ps1')
    . (Join-Path $CoreLib 'ui\shell\MultiSelectList.ps1')
    . (Join-Path $CoreLib 'ui\shell\Draw.ps1')
    . (Join-Path $CoreLib 'ui\shell\Footer.ps1')
    . (Join-Path $CoreLib 'ui\shell\Layout.ps1')

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
    $normalized = @(Normalize-ShellListRows -Rows $rows -ColumnLayout $layout)
    $built = Build-ShellMultiSelectListRowCache -Rows $normalized -ColumnLayout $layout

    $shell = Initialize-ToolkitShell
    $checked = Get-ShellMultiSelectCheckedSet -Shell $shell -CacheKey 'Test'
    $handlers = New-ShellMultiSelectListDrawHandlers -RowCache $built.RowCache -ColGap $built.ColGap `
        -CheckedIndexSet $checked

    Initialize-ToolkitShellBodyView -Shell $shell -SectionTitle 'test' -FooterTemplate ListWithToolbar
    $metrics = Get-ToolkitShellContentMetrics -Shell $shell
    $shell.Layout['ContentStartColumn'] = [int]$metrics.StartColumn
    $shell.Layout['ContentLineWidth'] = [int]$metrics.EndColumn

    $fnUpdate = Get-ShellMultiSelectMenuCommand 'Update-PaginatedMenuSelection'
    $testEnabled = { param($Row, [int]$Index) Test-ShellListRowEnabled -Row $Row -Index $Index }
    $getNum = { param($Row, [int]$Index) Get-ShellListRowDisplayNumber -Row $Row -Index $Index }

    [void]$checked.Add(0)
    & $fnUpdate -Items $normalized -Layout $shell.Layout -PageIndex 0 -PageSize 10 `
        -OldIndex 0 -NewIndex 0 -ScrollOffset 0 -NumWidth 2 `
        -GetItemLabel $handlers['GetLabel'] -TestItemEnabled $testEnabled `
        -GetItemDisplayNumber $getNum -DrawListRow $handlers['DrawListRow'] `
        -GetListRowSpec $handlers['GetListRowSpec']

    Write-Host 'MULTI SELECT SPACE OK'
}.GetNewClosure()

& $child $coreLib (Join-Path $root 'package\tools\node')
