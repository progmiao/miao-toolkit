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

    . (Join-Path $CoreLib 'ui\shell\ShellListModel.ps1')
    . (Join-Path $CoreLib 'ui\shell\ShellListLayout.ps1')

    $rows = @(
        (New-ShellListRow -Id '22.0.0' -Cells @('22.0.0') `
            -Payload ([pscustomobject]@{ Version = '22.0.0' }) -SearchKey '22.0.0' -Enabled $true)
        (New-ShellListRow -Id '20.0.0' -Cells @('20.0.0') `
            -Payload ([pscustomobject]@{ Version = '20.0.0' }) -SearchKey '20.0.0' -Enabled $false)
    )

    $listLayout = New-ShellListLayout -Widths @(20)
    $columnLayout = Resolve-ShellListLayoutColumnLayout -Layout $listLayout
    $normalized = @(Normalize-ShellListRows -Rows $rows -Layout $listLayout)
    $built = Build-ShellMultiSelectListRowCache -Rows $normalized -ColumnLayout $columnLayout

    $shell = Initialize-ToolkitShell
    $checked = Get-ShellMultiSelectCheckedSet -Shell $shell -CacheKey 'Test'
    $handlers = New-ShellMultiSelectListDrawHandlers -RowCache $built.RowCache -ColGap $built.ColGap `
        -CheckedIndexSet $checked

    Initialize-ToolkitShellBodyView -Shell $shell -SectionTitle 'test' -FooterTemplate ListWithToolbar
    $metrics = Get-ToolkitShellLayoutLineMetrics -Shell $shell
    $shell.Layout['LayoutStartColumn'] = [int]$metrics.StartColumn
    $shell.Layout['LayoutLineWidth'] = [int]$metrics.EndColumn

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

& $child $coreLib (Join-Path $root 'package\tools\01-node')
