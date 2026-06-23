$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$coreLib = Join-Path $root 'package\core\lib'
$toolRoot = Join-Path $root 'package\tools\01-node'

. (Join-Path $coreLib 'bootstrap\Load-Core.ps1') -LibDirectory $coreLib
Initialize-Paths -BinDirectory (Join-Path $root 'package\bin')
Initialize-PathsFromToolRoot -ToolRoot $toolRoot

$shell = Initialize-ToolkitShell
$env:MIAO_BUFFER_DRAW = '1'

# Simulate Invoke-NodeAction & script (child scope)
$child = {
    param($ToolRoot, $Shell)

    $browse = Join-Path $ToolRoot 'lib\browse-install.ps1'
    # Skip network: patch after load by dot-sourcing internals

    $coreLib = Join-Path $ToolRoot '..\..\core\lib'
    . (Join-Path $coreLib 'ui\console\Console-Menu.ps1')
    . (Join-Path $coreLib 'ui\shell\Nav.ps1')
    . (Join-Path $coreLib 'ui\shell\SystemToolbar.ps1')
    . (Join-Path $coreLib 'ui\shell\SingleSelectList.ps1')
    . (Join-Path $coreLib 'ui\shell\MultiSelectList.ps1')
    . (Join-Path $coreLib 'ui\shell\Draw.ps1')
    . (Join-Path $coreLib 'ui\shell\Footer.ps1')
    . (Join-Path $coreLib 'ui\shell\Layout.ps1')
    . (Join-Path (Join-Path $ToolRoot 'lib') 'volta-node.ps1')

    $remote = @(
        [PSCustomObject]@{ Version = '22.0.0'; Lts = 'Iron'; Date = '2024-01-01' }
        [PSCustomObject]@{ Version = '20.0.0'; Lts = $false; Date = '2023-01-01' }
    )
    $voltaInfo = @{ Map = @{}; Default = $null }
    $sorted = $remote
    $nameWidth = 40

    $rows = ConvertTo-ShellListRows -Items $sorted -KeepSource -MapCells {
        param($Item, [int]$Index)
        @([string]$Item.Version)
    } -GetEnabled { param($Item, [int]$Index) $true }

    Clear-ShellMultiSelectListCache -Shell $Shell -CacheKey 'NodeBrowse'
    $toolbar = New-ShellSystemToolbarConfig
    $invokeMultiSelect = Get-Command Invoke-ShellMultiSelectList -CommandType Function -ErrorAction Stop

  # Build row cache timing
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $built = Build-ShellMultiSelectListRowCache -Rows $rows -ColumnLayout (New-ShellListColumnLayout -Widths @($nameWidth))
    $sw.Stop()
    Write-Host "RowCache ms=$($sw.ElapsedMilliseconds)"

    $handlers = New-ShellMultiSelectListDrawHandlers -RowCache $built.RowCache -ColGap $built.ColGap `
        -CheckedIndexSet (Get-ShellMultiSelectCheckedSet -Shell $Shell -CacheKey 'NodeBrowse')

    # Test GetListRowSpec from Redraw context
    $spec = & $handlers['GetListRowSpec'] 0 $true 2 1 $true
    if (-not $spec) { throw 'GetListRowSpec returned null' }
    if ($spec.Text -notmatch '22') { throw "spec text wrong: $($spec.Text)" }

    $fnRedraw = Get-Command Redraw-PaginatedMenuPage -CommandType Function
    $layout = $Shell.Layout
    Update-ToolkitShellViewLayout -Shell $Shell -FooterTemplate ListWithToolbar -WithSectionTitle
    Sync-ToolkitShellLayoutLineMetrics -Shell $Shell

    Enter-ConsoleDrawBatch
    & $fnRedraw -Items $rows -Layout $layout -PageIndex 0 -SelectedIndex 0 -NumWidth 2 `
        -GetItemLabel $handlers['GetLabel'] -TestItemEnabled { param($i, $x) $true } `
        -GetItemDisplayNumber { param($r, $i) $i + 1 } -DrawListRow $handlers['DrawListRow'] `
        -GetListRowSpec $handlers['GetListRowSpec']
    Complete-ConsoleDrawBatch -ToolkitShell $Shell

    Write-Host 'BROWSE MULTI REDRAW OK'
}.GetNewClosure()

& $child $toolRoot $shell
