# 多选列表：ShellListRow + 勾选列 + 列布局 + 翻页 + 双行底栏（导航 6 列）

$script:ShellMultiSelectCheckWidth = 3
$script:ShellMultiSelectSearchKeyWidth = 8

function Get-ShellMultiSelectSearchKeyWidth {
    return [int]$script:ShellMultiSelectSearchKeyWidth
}

function Initialize-ShellMultiSelectListDependencies {
    if (Get-Command Redraw-PaginatedMenuPage -ErrorAction SilentlyContinue) {
        return
    }

    $lib = if ($global:MiaoCoreLibDir) { [string]$global:MiaoCoreLibDir } else { '' }
    if ([string]::IsNullOrWhiteSpace($lib)) {
        $lib = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    }

    if (-not (Get-Command Get-I18n -ErrorAction SilentlyContinue)) {
        . (Join-Path $lib 'config\I18n.ps1')
    }
    if (-not (Get-Command Get-ListNumberDisplayWidth -ErrorAction SilentlyContinue)) {
        . (Join-Path $lib 'config\ListLayout.ps1')
    }
    if (-not (Get-Command Resolve-ShellListScrollConfig -ErrorAction SilentlyContinue)) {
        . (Join-Path $PSScriptRoot 'ShellListScroll.ps1')
    }

    . (Join-Path $lib 'ui\console\Console-Menu.ps1')
}

function Get-ShellMultiSelectMenuCommand {
    param([string]$Name)

    Initialize-ShellMultiSelectListDependencies
    return (Get-Command -Name $Name -CommandType Function -ErrorAction Stop)
}

function Format-ShellMultiSelectCheckMark {
    param(
        [bool]$Checked,
        [bool]$Enabled = $true
    )

    if (-not $Enabled) { return '[X]' }
    if ($Checked) { return '[√]' }
    return '[ ]'
}

function Build-ShellMultiSelectListRowCache {
    param(
        [array]$Rows,
        [hashtable]$ColumnLayout,
        [scriptblock]$OnProgress = $null
    )

    $built = Build-ShellSingleSelectListRowCache -Rows $Rows -ColumnLayout $ColumnLayout `
        -OnProgress $OnProgress
    if ($Rows.Count -gt 0) {
        for ($i = 0; $i -lt $Rows.Count; $i++) {
            $searchKey = ''
            if ($null -ne $Rows[$i].PSObject.Properties['SearchKey']) {
                $searchKey = [string]$Rows[$i].SearchKey
            }
            if ([string]::IsNullOrEmpty($searchKey)) { continue }

            $entry = $built.RowCache[$i]
            $built.RowCache[$i] = [pscustomobject]@{
                BodyPlain      = $entry.BodyPlain
                BodySegments   = $entry.BodySegments
                LineColor      = $entry.LineColor
                Enabled        = $entry.Enabled
                Source         = $entry.Source
                Number         = $entry.Number
                SearchKey      = $searchKey
                RawCells       = $entry.RawCells
                Widths         = $entry.Widths
                CellColors     = $entry.CellColors
                ScrollOverflow = $entry.ScrollOverflow
            }
        }
    }

    return $built
}

function Build-ShellMultiSelectListRowSpec {
    param(
        $RowCacheEntry,
        [bool]$Selected,
        [bool]$Checked,
        [int]$NumWidth,
        [int]$DisplayNumber,
        [string]$Gap,
        [switch]$UseSearchKeyColumn,
        [int]$KeyWidth = 0,
        [string]$DisplayKey = '',
        [switch]$HideNumberColumn,
        [int]$ScrollColumn = -1,
        [int]$MarqueeOffset = 0
    )

    if (-not $RowCacheEntry) { return $null }

    if (-not (Get-Command Test-ShellListRowMarqueeActive -ErrorAction SilentlyContinue)) {
        . (Join-Path $PSScriptRoot 'ShellListScroll.ps1')
    }

    $enabled = [bool]$RowCacheEntry.Enabled
    $check = Format-ShellMultiSelectCheckMark -Checked $Checked -Enabled $enabled
    $mark = if ($Selected) { '>' } else { ' ' }
    $lineColor = if ($enabled) { $RowCacheEntry.LineColor } else { [System.ConsoleColor]::DarkGray }
    $marqueeActive = Test-ShellListRowMarqueeActive -RowCacheEntry $RowCacheEntry `
        -ScrollColumn $ScrollColumn -Selected:$Selected

    $bodySegs = @()
    if ($marqueeActive) {
        $body = Build-ShellListRowBodyFromCells -RawCells @($RowCacheEntry.RawCells) `
            -Widths @($RowCacheEntry.Widths) -Gap (' ' * (Get-MenuColumnGap)) `
            -DefaultLineColor $lineColor -CellColors $RowCacheEntry.CellColors -Enabled $enabled `
            -ScrollColumn $ScrollColumn -MarqueeOffset $MarqueeOffset -MarqueeActive `
            -Selected:$Selected
        $bodySegs = @($body.BodySegments)
    }
    elseif ($null -ne $RowCacheEntry.BodySegments) {
        $bodySegs = @($RowCacheEntry.BodySegments)
    }

    if ($UseSearchKeyColumn) {
        $keyText = Pad-DisplayText -Text $DisplayKey -TargetWidth $KeyWidth
        $keySeg = @{ Text = "$keyText$Gap"; Color = $lineColor }
    }
    elseif ($HideNumberColumn) {
        $keySeg = $null
    }
    else {
        $num = Format-ListDisplayNumber -Number $DisplayNumber -NumWidth $NumWidth
        $keySeg = @{ Text = "$num$Gap"; Color = $lineColor }
    }

    $checkSeg = if ($HideNumberColumn -and -not $UseSearchKeyColumn) {
        @{ Text = "$mark $check"; Color = $lineColor }
    }
    else {
        @{ Text = "$mark $check "; Color = $lineColor }
    }

    if ($Selected -and -not $marqueeActive) {
        $foreground = if ($enabled) { [System.ConsoleColor]::Black } else { [System.ConsoleColor]::DarkGray }
        if ($UseSearchKeyColumn) {
            $prefix = " $mark $check $keyText$Gap"
        }
        elseif ($HideNumberColumn) {
            $prefix = " $mark $check"
        }
        else {
            $num = Format-ListDisplayNumber -Number $DisplayNumber -NumWidth $NumWidth
            $prefix = " $mark $check $num$Gap"
        }
        return @{
            Text       = $prefix + $RowCacheEntry.BodyPlain
            Foreground = $foreground
            Background = [System.ConsoleColor]::Cyan
        }
    }

    if ($Selected -and $marqueeActive) {
        $segments = if ($keySeg) { @($checkSeg, $keySeg) + $bodySegs } else { @($checkSeg) + $bodySegs }
        return @{
            Segments          = $segments
            DefaultForeground = [System.ConsoleColor]::Black
            Background        = [System.ConsoleColor]::Cyan
        }
    }

    $segments = if ($keySeg) { @($checkSeg, $keySeg) + $bodySegs } else { @($checkSeg) + $bodySegs }
    return @{
        Segments          = $segments
        DefaultForeground = $lineColor
    }
}

function Write-ShellMultiSelectListRow {
    param(
        [int]$ScreenRow,
        [int]$DisplayNumber,
        [int]$NumWidth,
        [string]$Gap,
        [bool]$Selected,
        [bool]$Checked,
        [bool]$Enabled,
        [hashtable]$RowSpec = $null,
        [int]$LayoutLineWidth = 0,
        [int]$LayoutStartColumn = 0
    )

    if (-not $RowSpec) { return }

    if (Test-UseConsoleListBufferDraw) {
        try {
            $highlightWidth = if ($Selected) { $LayoutLineWidth } else { 0 }
            $highlightStart = if ($Selected) { $LayoutStartColumn } else { 0 }
            Write-ListRowFromSpec -ScreenRow $ScreenRow -Spec $RowSpec -LayoutLineWidth $highlightWidth `
                -LayoutStartColumn $highlightStart
            return
        }
        catch { }
    }

    Prepare-ConsoleRowWrite -Row $ScreenRow
    try { [Console]::SetCursorPosition(0, $ScreenRow) } catch { return }

    $width = Get-SafeWriteLineWidth -Row $ScreenRow
    if ($Selected -and $RowSpec.Text -and -not $RowSpec.Segments) {
        $region = Resolve-ConsoleContentHighlightRegion -Row $ScreenRow `
            -LayoutStartColumn $LayoutStartColumn -LayoutLineWidth $LayoutLineWidth
        Write-ConsoleRowHighlightText -Text ([string]$RowSpec.Text) -Region $region
        Set-ConsoleCursorAfterRowWrite -Row $ScreenRow
        return
    }

    $used = 0
    $segments = if ($RowSpec.Segments) { @($RowSpec.Segments) } else { @() }
    foreach ($seg in $segments) {
        if (-not $seg) { continue }
        if ($used -ge $width) { break }
        $partWidth = Get-DisplayWidth $seg.Text
        $remaining = $width - $used
        $text = if ($partWidth -gt $remaining) { Truncate-DisplayText $seg.Text $remaining } else { $seg.Text }
        if ([string]::IsNullOrEmpty($text)) { break }
        $fg = if ($seg.Color) { $seg.Color } else { $RowSpec.DefaultForeground }
        $bg = if ($Selected -and $RowSpec.Background) { $RowSpec.Background } else { (Get-ConsoleSurfaceBackground) }
        Write-Host $text -NoNewline -ForegroundColor $fg -BackgroundColor $bg
        $used += Get-DisplayWidth $text
    }
    if ($used -lt $width) {
        Write-Host (' ' * ($width - $used)) -NoNewline
    }
    Set-ConsoleCursorAfterRowWrite -Row $ScreenRow
}

function Invoke-ShellMultiSelectListDrawRow {
    param(
        [int]$ScreenRow,
        [int]$Index,
        [array]$RowCache,
        [string]$ColGap,
        [bool]$Selected,
        [bool]$Checked,
        [int]$NumWidth,
        [int]$DisplayNumber,
        [bool]$Enabled,
        [int]$LayoutLineWidth = 0,
        [int]$LayoutStartColumn = 0,
        [switch]$UseSearchKeyColumn,
        [int]$KeyWidth = 0,
        [string]$DisplayKey = '',
        [switch]$HideNumberColumn,
        [int]$ScrollColumn = -1,
        [int]$MarqueeOffset = 0
    )

    if ($Index -lt 0 -or $Index -ge $RowCache.Count) { return }
    $part = $RowCache[$Index]
    if (-not $part) { return }

    $spec = Build-ShellMultiSelectListRowSpec -RowCacheEntry $part -Selected $Selected -Checked $Checked `
        -NumWidth $NumWidth -DisplayNumber $DisplayNumber -Gap $ColGap `
        -UseSearchKeyColumn:$UseSearchKeyColumn -KeyWidth $KeyWidth -DisplayKey $DisplayKey `
        -HideNumberColumn:$HideNumberColumn -ScrollColumn $ScrollColumn -MarqueeOffset $MarqueeOffset
    Write-ShellMultiSelectListRow -ScreenRow $ScreenRow -DisplayNumber $DisplayNumber `
        -NumWidth $NumWidth -Gap $ColGap -Selected $Selected -Checked $Checked -Enabled $Enabled `
        -RowSpec $spec -LayoutLineWidth $LayoutLineWidth -LayoutStartColumn $LayoutStartColumn
}

function New-ShellMultiSelectListDrawHandlers {
    param(
        [array]$RowCache,
        [string]$ColGap,
        [System.Collections.Generic.HashSet[int]]$CheckedIndexSet = $null,
        [int]$LayoutLineWidth = 0,
        [int]$LayoutStartColumn = 0,
        [switch]$SearchKeyMode,
        [int]$SearchKeyWidth = 0,
        [switch]$HideNumberColumn,
        [int]$ScrollColumn = -1,
        [scriptblock]$GetMarqueeOffset = $null
    )

    $cacheSnapshot = @($RowCache)
    $gapSnapshot = [string]$ColGap
    $contentWidthSnapshot = [int]$LayoutLineWidth
    $contentStartSnapshot = [int]$LayoutStartColumn
    $checkedSetSnapshot = $CheckedIndexSet
    $searchKeyModeSnapshot = [bool]$SearchKeyMode
    $searchKeyWidthSnapshot = if ($SearchKeyWidth -gt 0) { [int]$SearchKeyWidth } else { (Get-ShellMultiSelectSearchKeyWidth) }
    $hideNumberColumnSnapshot = [bool]$HideNumberColumn
    $scrollColumnSnapshot = [int]$ScrollColumn
    $getOffset = $GetMarqueeOffset

    Initialize-ShellMultiSelectListDependencies

    $getLabel = {
        param($Item, [int]$Index)
        if ($Index -lt 0 -or $Index -ge $cacheSnapshot.Count) { return '' }
        $part = $cacheSnapshot[$Index]
        if (-not $part) { return '' }
        $rowEnabled = [bool]$part.Enabled
        $checked = $false
        if ($checkedSetSnapshot) { $checked = $checkedSetSnapshot.Contains($Index) }
        $check = Format-ShellMultiSelectCheckMark -Checked $checked -Enabled $rowEnabled
        if ($searchKeyModeSnapshot) {
            $key = if ($null -ne $part.PSObject.Properties['SearchKey']) { [string]$part.SearchKey } else { '' }
            return "$check  $key  $([string]$part.BodyPlain)"
        }
        return "$check  $([string]$part.BodyPlain)"
    }.GetNewClosure()

    $getListRowSpec = {
        param(
            [int]$Index,
            [bool]$Selected,
            [int]$NumWidth,
            [int]$DisplayNumber,
            [bool]$Enabled
        )

        if ($Index -lt 0 -or $Index -ge $cacheSnapshot.Count -or -not $cacheSnapshot[$Index]) {
            return $null
        }
        $checked = $false
        if ($checkedSetSnapshot) { $checked = $checkedSetSnapshot.Contains($Index) }
        $part = $cacheSnapshot[$Index]
        $displayKey = ''
        if ($searchKeyModeSnapshot -and $null -ne $part.PSObject.Properties['SearchKey']) {
            $displayKey = [string]$part.SearchKey
        }
        $offset = 0
        if ($getOffset) { $offset = [int](& $getOffset) }
        return (Build-ShellMultiSelectListRowSpec -RowCacheEntry $part -Selected $Selected `
            -Checked $checked -NumWidth $NumWidth -DisplayNumber $DisplayNumber -Gap $gapSnapshot `
            -UseSearchKeyColumn:$searchKeyModeSnapshot -KeyWidth $searchKeyWidthSnapshot -DisplayKey $displayKey `
            -HideNumberColumn:$hideNumberColumnSnapshot -ScrollColumn $scrollColumnSnapshot -MarqueeOffset $offset)
    }.GetNewClosure()

    $drawListRow = {
        param(
            [int]$ScreenRow,
            $Item,
            [int]$Index,
            [bool]$Selected,
            [int]$NumWidth,
            [int]$DisplayNumber,
            [bool]$Enabled
        )

        $checked = $false
        if ($checkedSetSnapshot) { $checked = $checkedSetSnapshot.Contains($Index) }
        $part = $cacheSnapshot[$Index]
        $displayKey = ''
        if ($searchKeyModeSnapshot -and $part -and $null -ne $part.PSObject.Properties['SearchKey']) {
            $displayKey = [string]$part.SearchKey
        }
        $offset = 0
        if ($getOffset) { $offset = [int](& $getOffset) }
        Invoke-ShellMultiSelectListDrawRow -ScreenRow $ScreenRow -Index $Index `
            -RowCache $cacheSnapshot -ColGap $gapSnapshot -Selected $Selected `
            -Checked $checked -NumWidth $NumWidth -DisplayNumber $DisplayNumber `
            -Enabled $Enabled -LayoutLineWidth $contentWidthSnapshot -LayoutStartColumn $contentStartSnapshot `
            -UseSearchKeyColumn:$searchKeyModeSnapshot -KeyWidth $searchKeyWidthSnapshot -DisplayKey $displayKey `
            -HideNumberColumn:$hideNumberColumnSnapshot -ScrollColumn $scrollColumnSnapshot -MarqueeOffset $offset
    }.GetNewClosure()

    return @{
        GetLabel       = $getLabel
        GetListRowSpec = $getListRowSpec
        DrawListRow    = $drawListRow
    }
}

function Get-ShellMultiSelectListRowCache {
    param(
        [hashtable]$Shell,
        [string]$CacheKey,
        [array]$Rows,
        [hashtable]$ColumnLayout,
        [scriptblock]$OnProgress = $null
    )

    $locale = Get-CurrentLocale
    $layoutKey = if ($ColumnLayout.Preset) { $ColumnLayout.Preset } else { ($ColumnLayout.Widths -join ',') }
    if ($ColumnLayout.ContainsKey('ScrollColumn')) {
        $layoutKey += "|sc$($ColumnLayout.ScrollColumn)"
    }
    $rowsKey = Get-ShellListRowsCacheKey -Rows $Rows
    $cacheField = "${CacheKey}MultiListRowCache"
    $localeField = "${CacheKey}MultiListRowCacheLocale"
    $keyField = "${CacheKey}MultiListRowCacheKey"
    $gapField = "${CacheKey}MultiListColGap"

    if ($Shell -and $Shell[$cacheField] -and $Shell[$localeField] -eq $locale `
        -and $Shell[$keyField] -eq "$layoutKey|$rowsKey") {
        $cachedRows = @($Shell[$cacheField])
        if ($cachedRows.Count -eq $Rows.Count) {
            return @{
                RowCache = $Shell[$cacheField]
                ColGap   = $Shell[$gapField]
            }
        }
        Clear-ShellMultiSelectListCache -Shell $Shell -CacheKey $CacheKey
    }

    $built = Build-ShellMultiSelectListRowCache -Rows $Rows -ColumnLayout $ColumnLayout `
        -OnProgress $OnProgress
    if ($Shell) {
        $Shell[$cacheField] = $built.RowCache
        $Shell[$localeField] = $locale
        $Shell[$keyField] = "$layoutKey|$rowsKey"
        $Shell[$gapField] = $built.ColGap
    }

    return $built
}

function Clear-ShellMultiSelectListCache {
    param(
        [hashtable]$Shell,
        [string]$CacheKey
    )

    if (-not $Shell) { return }
    $Shell.Remove("${CacheKey}MultiListRowCache")
    $Shell.Remove("${CacheKey}MultiListRowCacheLocale")
    $Shell.Remove("${CacheKey}MultiListRowCacheKey")
    $Shell.Remove("${CacheKey}MultiListColGap")
    $Shell.Remove("${CacheKey}MultiListChecked")
}

function Get-ShellMultiSelectCheckedFieldName {
    param([string]$CacheKey)

    return "${CacheKey}MultiListChecked"
}

function Get-ShellMultiSelectCheckedSet {
    param(
        [hashtable]$Shell,
        [string]$CacheKey
    )

    if (-not $Shell) {
        return ,([System.Collections.Generic.HashSet[int]]::new())
    }

    $field = Get-ShellMultiSelectCheckedFieldName -CacheKey $CacheKey
    $set = $Shell[$field]
    if ($null -eq $set) {
        $set = [System.Collections.Generic.HashSet[int]]::new()
        $Shell[$field] = $set
    }
    return ,$set
}

function Test-ShellMultiSelectIndexChecked {
    param(
        [hashtable]$Shell,
        [string]$CacheKey,
        [int]$Index
    )

    $set = Get-ShellMultiSelectCheckedSet -Shell $Shell -CacheKey $CacheKey
    return $set.Contains($Index)
}

function Find-ShellMultiSelectFirstFocusIndex {
    param([array]$Rows)

    if ($Rows.Count -eq 0) { return -1 }
    return 0
}

function Show-ShellMultiSelectListMenu {
    param(
        [hashtable]$Header,
        [array]$Items,
        [int]$PageSize = 0,
        [scriptblock]$TestItemEnabled = { param($Item, $Index) $true },
        [string]$CountLabel = '',
        [hashtable]$LetterKeys = @{},
        [string[]]$MenuSplitActionSegments = $null,
        [scriptblock]$GetItemDisplayNumber = $null,
        [scriptblock]$GetItemSearchKey = $null,
        [scriptblock]$ResolveMenuNumber = $null,
        [int]$NumberDisplayWidth = 0,
        [switch]$SearchKeyMode,
        [int]$SearchKeyWidth = 0,
        [hashtable]$ToolkitShell = $null,
        [switch]$AllowBack,
        [array]$RowCache = @(),
        [string]$ColGap = '',
        [string]$CheckedCacheKey = '',
        [string]$FlashNothingSelectedKey = 'common.nothingSelected',
        [string]$FlashItemDisabledKey = 'message.disabledItem',
        [string]$FlashNothingSelected = '',
        [string]$FlashItemDisabled = '',
        [hashtable]$SearchConfig = $null,
        [switch]$HideNumberColumn,
        [hashtable]$ListScrollConfig = $null
    )

    if (-not $CountLabel) {
        $CountLabel = Get-I18n -Key 'common.item'
    }

    if ($PageSize -le 0) {
        $PageSize = Get-MenuPageSize
    }

    if (-not $ToolkitShell) {
        throw 'Show-ShellMultiSelectListMenu requires ToolkitShell.'
    }

    Initialize-ShellMultiSelectListDependencies
    $fnRedrawPage = Get-ShellMultiSelectMenuCommand 'Redraw-PaginatedMenuPage'
    $fnUpdateSelection = Get-ShellMultiSelectMenuCommand 'Update-PaginatedMenuSelection'
    $fnSelectPageIndex = Get-ShellMultiSelectMenuCommand 'Select-MenuPageSelectionIndex'
    $fnSetListScroll = Get-ShellMultiSelectMenuCommand 'Set-MenuListScrollOffset'
    $fnTestNumPrefix = Get-ShellMultiSelectMenuCommand 'Test-MenuNumberBufferPrefix'
    $fnTestSearchPrefix = Get-ShellMultiSelectMenuCommand 'Test-MenuSearchBufferPrefix'
    $fnSetMenuCursor = Get-ShellMultiSelectMenuCommand 'Set-MenuInputCursorPosition'

    $layout = $ToolkitShell.Layout
    if ($PageSize -le 0) {
        $PageSize = $layout.ListViewportHeight
    }
    if (-not $layout.LayoutLineWidth -or -not $layout.LayoutStartColumn) {
        $metrics = if ($ToolkitShell.LayoutLineMetrics) {
            $ToolkitShell.LayoutLineMetrics
        }
        else {
            Get-ToolkitShellLayoutLineMetrics -Shell $ToolkitShell
        }
        $layout['LayoutStartColumn'] = [int]$metrics.StartColumn
        $layout['LayoutLineWidth'] = [int]$metrics.EndColumn
    }

    $resolveNumberFn = $ResolveMenuNumber
    if (-not $resolveNumberFn) {
        $resolveNumberFn = ${function:Resolve-ListNumberIndexDefault}
    }

    $resolvedSearchConfig = Resolve-ShellListSearchConfig -SearchConfig $SearchConfig
    $letterInputMode = $false
    $listScrollConfig = if ($ListScrollConfig) {
        $ListScrollConfig
    }
    else {
        Resolve-ShellListScrollConfig -Layout $null
    }
    $marqueeOffset = 0
    $marqueeLastTick = [Environment]::TickCount
    $getMarqueeOffset = { return $marqueeOffset }.GetNewClosure()

    $maxDisplayNumber = Get-MenuMaxDisplayNumber -Items $Items -GetItemDisplayNumber $GetItemDisplayNumber
    if ($HideNumberColumn) {
        $numWidth = 0
        $singleDigitSelect = $false
    }
    elseif ($NumberDisplayWidth -gt 0) {
        $numWidth = $NumberDisplayWidth
        $singleDigitSelect = ($maxDisplayNumber -le 9)
    }
    else {
        $numWidth = Get-ListNumberDisplayWidth -MaxNumber $maxDisplayNumber
        $singleDigitSelect = ($maxDisplayNumber -le 9)
    }
    $pageCount = [Math]::Max(1, [Math]::Ceiling($Items.Count / [double]$PageSize))

    $checkedIndexSet = Get-ShellMultiSelectCheckedSet -Shell $ToolkitShell -CacheKey $CheckedCacheKey
    $flashNothingSelectedText = if (-not [string]::IsNullOrWhiteSpace($FlashNothingSelected)) {
        [string]$FlashNothingSelected
    }
    else {
        Get-I18n -Key $FlashNothingSelectedKey
    }
    $pageIndex = 0
    $selectedIndex = Find-ShellMultiSelectFirstFocusIndex -Rows $Items
    $numberBuffer = ''
    $flashMessage = ''
    $listScrollOffset = 0

    if ($selectedIndex -ge 0) {
        $pageIndex = [Math]::Floor($selectedIndex / [double]$PageSize)
    }

    $layoutLineWidth = [int]$layout.LayoutLineWidth
    $contentStartColumn = [int]$layout.LayoutStartColumn
    $handlers = New-ShellMultiSelectListDrawHandlers -RowCache $RowCache -ColGap $ColGap `
        -CheckedIndexSet $checkedIndexSet -LayoutLineWidth $layoutLineWidth `
        -LayoutStartColumn $contentStartColumn -SearchKeyMode:$false `
        -SearchKeyWidth 0 -HideNumberColumn:$HideNumberColumn `
        -ScrollColumn ([int]$listScrollConfig.ScrollColumn) -GetMarqueeOffset $getMarqueeOffset

    function Apply-MultiSelectInputBuffer {
        param([string]$Buffer)
        if ([string]::IsNullOrEmpty($Buffer)) { return }
        if ($Items.Count -eq 0) { return }

        $inputMode = if ($letterInputMode) { 'Letter' } else { 'Number' }
        $idx = Resolve-ShellListInputBufferIndex -Rows $Items -Buffer $Buffer -InputMode $inputMode `
            -SearchConfig $resolvedSearchConfig -GetItemDisplayNumber $GetItemDisplayNumber `
            -TestItemEnabled $TestItemEnabled -ResolveMenuNumber $resolveNumberFn
        if ($idx -ge 0 -and $idx -lt $Items.Count) {
            Set-Variable -Name selectedIndex -Value $idx -Scope 1
            Set-Variable -Name pageIndex -Value ([Math]::Floor($idx / [double]$PageSize)) -Scope 1
            & $fnSetListScroll -ScrollOffset ([ref]$listScrollOffset) `
                -SelectedIndex $idx -PageIndex $pageIndex -PageSize $PageSize `
                -ItemCount $Items.Count -ViewportHeight $layout.ListViewportHeight
        }
    }

    $redrawPage = {
        & $fnRedrawPage -Items $Items -Layout $layout -PageIndex $pageIndex `
            -SelectedIndex $selectedIndex -NumWidth $numWidth `
            -GetItemLabel $handlers['GetLabel'] -TestItemEnabled $TestItemEnabled -PageSize $PageSize `
            -GetItemDisplayNumber $GetItemDisplayNumber -ListScrollOffset $listScrollOffset `
            -DrawListRow $handlers['DrawListRow'] -GetListRowSpec $handlers['GetListRowSpec']
    }

    $invokeFooter = {
        param([string]$FlashMessage = '')

        Write-ToolkitShellFooter -Shell $ToolkitShell -Template ListWithToolbar -MenuFooter @{
            PageIndex               = $pageIndex
            PageCount               = $pageCount
            ItemCount               = $Items.Count
            SelectedIndex           = $selectedIndex
            NumberBuffer            = $numberBuffer
            CountLabel              = $CountLabel
            FlashMessage            = $FlashMessage
            MenuSplitActionSegments = $MenuSplitActionSegments
            MultiSelectNav          = $true
            CompactNavStatus        = $true
            LetterSearchActive      = [bool]$letterInputMode
            LetterSearchEnabled     = [bool]$resolvedSearchConfig.Enabled
            LetterSearchToggleKey   = [string]$resolvedSearchConfig.LetterToggleKey
        }
    }

    & $fnSetListScroll -ScrollOffset ([ref]$listScrollOffset) `
        -SelectedIndex $selectedIndex -PageIndex $pageIndex -PageSize $PageSize `
        -ItemCount $Items.Count -ViewportHeight $layout.ListViewportHeight
    $useShellBatch = Test-ShellConsoleBatchDraw
    if ($useShellBatch) { Enter-ConsoleDrawBatch }
    & $redrawPage
    & $invokeFooter
    Register-ToolkitShellFooter -Shell $ToolkitShell -Renderer {
        param([hashtable]$FooterState = @{})
        $flash = if ($FooterState.FlashMessage) { [string]$FooterState.FlashMessage } else { '' }
        & $invokeFooter -FlashMessage $flash
    }
    if ($useShellBatch) { $null = Complete-ConsoleDrawBatch -ToolkitShell $ToolkitShell }

    try {
        while ($true) {
            $confirmResult = Read-ShellExitIfActive -Shell $ToolkitShell
            if ($confirmResult -eq 'exitCancel') { continue }
            if ($confirmResult -eq 'exitConfirmed') {
                return (Get-ShellNavMarker -Action 'quit')
            }

            $oldIndex = $selectedIndex
            $oldPage = $pageIndex
            $oldScroll = $listScrollOffset
            $oldNumberBuffer = $numberBuffer
            $oldLetterInputMode = $letterInputMode
            $flashMessage = ''
            $checkToggled = $false

            if ($ToolkitShell) {
                Prepare-ToolkitShellBodyDraw -Shell $ToolkitShell
            }
            $key = Read-ShellListMenuKey -ScrollConfig $listScrollConfig
            if ($null -eq $key) {
                if (Invoke-ShellListMenuMarqueeTick -SelectedIndex $selectedIndex -RowCache $RowCache `
                        -ScrollConfig $listScrollConfig -MarqueeOffset ([ref]$marqueeOffset) `
                        -MarqueeLastTick ([ref]$marqueeLastTick) -LetterInputMode:$letterInputMode) {
                    $marqueeBatch = Test-ShellConsoleBatchDraw
                    if ($marqueeBatch) { Enter-ConsoleDrawBatch }
                    Invoke-ShellSingleSelectListRedrawMarqueeRow -Layout $layout -SelectedIndex $selectedIndex `
                        -PageIndex $pageIndex -PageSize $PageSize -ListScrollOffset $listScrollOffset `
                        -RowCache $RowCache -GetListRowSpec $handlers['GetListRowSpec'] -NumWidth $numWidth `
                        -GetItemDisplayNumber $GetItemDisplayNumber -TestItemEnabled $TestItemEnabled `
                        -Items $Items -LayoutLineWidth $layoutLineWidth -LayoutStartColumn $contentStartColumn
                    if ($marqueeBatch) { $null = Complete-ConsoleDrawBatch -ToolkitShell $ToolkitShell }
                }
                Start-Sleep -Milliseconds 25
                continue
            }
            if ($ToolkitShell) {
                Set-CursorVisible $false
            }

            if ($resolvedSearchConfig.Enabled -and (Test-ShellListLetterSearchToggleKey -Key $key `
                    -ToggleKey $resolvedSearchConfig.LetterToggleKey)) {
                $letterInputMode = -not $letterInputMode
                $numberBuffer = ''
            }
            elseif ($key.Key -eq 'Backspace') {
                if (-not [string]::IsNullOrEmpty($numberBuffer)) {
                    if (-not $singleDigitSelect -or $letterInputMode) {
                        $numberBuffer = $numberBuffer.Substring(0, $numberBuffer.Length - 1)
                        if (-not [string]::IsNullOrEmpty($numberBuffer)) {
                            Apply-MultiSelectInputBuffer -Buffer $numberBuffer
                        }
                    }
                }
            }
            elseif ($letterInputMode -and $key.KeyChar -match '^[a-zA-Z0-9]$') {
                $candidate = $numberBuffer + [string]$key.KeyChar
                if (Test-ShellListInputBufferPrefixValid -Rows $Items -Buffer $candidate -InputMode Letter `
                        -SearchConfig $resolvedSearchConfig -TestItemEnabled $TestItemEnabled) {
                    $numberBuffer = $candidate
                    Apply-MultiSelectInputBuffer -Buffer $numberBuffer
                }
            }
            elseif (-not $HideNumberColumn -and -not $letterInputMode -and $key.KeyChar -match '^[0-9]$') {
                if ($singleDigitSelect) {
                    $digit = [string]$key.KeyChar
                    if (& $fnTestNumPrefix -Items $Items -Buffer $digit `
                        -GetItemDisplayNumber $GetItemDisplayNumber) {
                        $numberBuffer = $digit
                        Apply-MultiSelectInputBuffer -Buffer $numberBuffer
                    }
                }
                else {
                    $candidate = $numberBuffer + $key.KeyChar
                    if (& $fnTestNumPrefix -Items $Items -Buffer $candidate `
                        -GetItemDisplayNumber $GetItemDisplayNumber) {
                        $numberBuffer = $candidate
                        Apply-MultiSelectInputBuffer -Buffer $numberBuffer
                    }
                }
            }
            elseif ($key.KeyChar -match '^[qQ]$') {
                if ($AllowBack) {
                    & $fnSetMenuCursor -Layout $layout -ToolkitShell $ToolkitShell
                    return (Get-ShellNavMarker -Action 'back')
                }
            }
            elseif ($key.KeyChar -match '^[a-zA-Z]$') {
                $letter = $key.KeyChar.ToString().ToLowerInvariant()
                $effectiveLetterKeys = Get-ShellListEffectiveLetterKeys -LetterKeys $LetterKeys `
                    -LetterInputMode:$letterInputMode
                if ($effectiveLetterKeys -and $effectiveLetterKeys.ContainsKey($letter)) {
                    & $fnSetMenuCursor -Layout $layout -ToolkitShell $ToolkitShell
                    return $LetterKeys[$letter]
                }
            }
            else {
                switch ($key.Key) {
                    'LeftArrow' {
                        $numberBuffer = ''
                        if ($pageCount -gt 1) {
                            $oldPage = $pageIndex
                            $oldSelected = $selectedIndex
                            if ($pageIndex -gt 0) { $pageIndex-- }
                            else { $pageIndex = $pageCount - 1 }
                            $selectedIndex = & $fnSelectPageIndex -NewPageIndex $pageIndex `
                                -OldSelectedIndex $oldSelected -OldPageIndex $oldPage `
                                -PageSize $PageSize -ItemCount $Items.Count
                            $listScrollOffset = 0
                            & $fnSetListScroll -ScrollOffset ([ref]$listScrollOffset) `
                                -SelectedIndex $selectedIndex -PageIndex $pageIndex -PageSize $PageSize `
                                -ItemCount $Items.Count -ViewportHeight $layout.ListViewportHeight
                        }
                    }
                    'RightArrow' {
                        $numberBuffer = ''
                        if ($pageCount -gt 1) {
                            $oldPage = $pageIndex
                            $oldSelected = $selectedIndex
                            if ($pageIndex -lt ($pageCount - 1)) { $pageIndex++ }
                            else { $pageIndex = 0 }
                            $selectedIndex = & $fnSelectPageIndex -NewPageIndex $pageIndex `
                                -OldSelectedIndex $oldSelected -OldPageIndex $oldPage `
                                -PageSize $PageSize -ItemCount $Items.Count
                            $listScrollOffset = 0
                            & $fnSetListScroll -ScrollOffset ([ref]$listScrollOffset) `
                                -SelectedIndex $selectedIndex -PageIndex $pageIndex -PageSize $PageSize `
                                -ItemCount $Items.Count -ViewportHeight $layout.ListViewportHeight
                        }
                    }
                    'UpArrow' {
                        $numberBuffer = ''
                        $pageStart = $pageIndex * $PageSize
                        $itemsOnPage = [Math]::Min($PageSize, $Items.Count - $pageStart)
                        $local = $selectedIndex - $pageStart

                        if ($local -gt 0) {
                            $selectedIndex--
                        }
                        elseif ($pageIndex -gt 0) {
                            $pageIndex--
                            $prevStart = $pageIndex * $PageSize
                            $prevItemsOnPage = [Math]::Min($PageSize, $Items.Count - $prevStart)
                            $selectedIndex = $prevStart + $prevItemsOnPage - 1
                            $listScrollOffset = 0
                        }
                        elseif ($Items.Count -gt 1) {
                            $pageIndex = $pageCount - 1
                            $selectedIndex = $Items.Count - 1
                            $listScrollOffset = 0
                        }
                        & $fnSetListScroll -ScrollOffset ([ref]$listScrollOffset) `
                            -SelectedIndex $selectedIndex -PageIndex $pageIndex -PageSize $PageSize `
                            -ItemCount $Items.Count -ViewportHeight $layout.ListViewportHeight
                    }
                    'DownArrow' {
                        $numberBuffer = ''
                        $pageStart = $pageIndex * $PageSize
                        $itemsOnPage = [Math]::Min($PageSize, $Items.Count - $pageStart)
                        $local = $selectedIndex - $pageStart

                        if ($local -lt ($itemsOnPage - 1)) {
                            $selectedIndex++
                        }
                        elseif ($pageIndex -lt ($pageCount - 1)) {
                            $pageIndex++
                            $selectedIndex = $pageIndex * $PageSize
                            $listScrollOffset = 0
                        }
                        elseif ($Items.Count -gt 1) {
                            $pageIndex = 0
                            $selectedIndex = 0
                            $listScrollOffset = 0
                        }
                        & $fnSetListScroll -ScrollOffset ([ref]$listScrollOffset) `
                            -SelectedIndex $selectedIndex -PageIndex $pageIndex -PageSize $PageSize `
                            -ItemCount $Items.Count -ViewportHeight $layout.ListViewportHeight
                    }
                    'Spacebar' {
                        if ($selectedIndex -ge 0 -and $selectedIndex -lt $Items.Count) {
                            if (& $TestItemEnabled $Items[$selectedIndex] $selectedIndex) {
                                if ($checkedIndexSet.Contains($selectedIndex)) {
                                    [void]$checkedIndexSet.Remove($selectedIndex)
                                }
                                else {
                                    [void]$checkedIndexSet.Add($selectedIndex)
                                }
                                $checkToggled = $true
                            }
                        }
                    }
                    'Enter' {
                        $numberBuffer = ''
                        if ($checkedIndexSet.Count -eq 0) {
                            $flashMessage = $flashNothingSelectedText
                            break
                        }

                        $picked = @($checkedIndexSet | Sort-Object | ForEach-Object { $Items[$_] })
                        & $fnSetMenuCursor -Layout $layout -ToolkitShell $ToolkitShell
                        return $picked
                    }
                    'Escape' {
                        & $fnSetMenuCursor -Layout $layout -ToolkitShell $ToolkitShell
                        Request-ShellExit -Shell $ToolkitShell
                        continue
                    }
                }
            }

            $scrollChanged = ($oldScroll -ne $listScrollOffset)
            $pageChanged = ($oldPage -ne $pageIndex)
            $selectionChanged = ($oldIndex -ne $selectedIndex)
            if ($selectionChanged) {
                $marqueeOffset = 0
            }
            $checkChanged = $checkToggled
            $bufferChanged = ($oldNumberBuffer -ne $numberBuffer)
            $letterModeChanged = ($oldLetterInputMode -ne $letterInputMode)
            $footerChanged = $pageChanged -or $flashMessage -or $bufferChanged -or $letterModeChanged
            $fullRowRedraw = $pageChanged -or $scrollChanged -or $checkChanged
            $batchNeeded = $fullRowRedraw -or $footerChanged

            if ($useShellBatch -and $batchNeeded) {
                if ($script:ConsoleDrawBatchDepth -le 0) { Enter-ConsoleDrawBatch }
            }

            if ($fullRowRedraw) {
                & $redrawPage
            }
            elseif ($selectionChanged) {
                & $fnUpdateSelection -Items $Items -Layout $layout -PageIndex $pageIndex `
                    -PageSize $PageSize -OldIndex $oldIndex -NewIndex $selectedIndex `
                    -ScrollOffset $listScrollOffset -NumWidth $numWidth `
                    -GetItemLabel $handlers['GetLabel'] -TestItemEnabled $TestItemEnabled `
                    -GetItemDisplayNumber $GetItemDisplayNumber -DrawListRow $handlers['DrawListRow'] `
                    -GetListRowSpec $handlers['GetListRowSpec'] -LayoutLineWidth $layoutLineWidth `
                    -LayoutStartColumn $contentStartColumn
            }

            if ($footerChanged) {
                & $invokeFooter -FlashMessage $flashMessage
            }

            $needsShellCursor = $fullRowRedraw -or $footerChanged -or $selectionChanged
            if ($needsShellCursor -and (-not ($useShellBatch -and $batchNeeded))) {
                Set-ToolkitShellInputCursor -Shell $ToolkitShell
                if ((Get-ConsoleViewportTop) -gt 0) { $null = Sync-ConsoleViewportTop }
            }

            if ($useShellBatch -and $batchNeeded) {
                $null = Complete-ConsoleDrawBatch -ToolkitShell $ToolkitShell
            }
        }
    }
    finally {
        if (-not $ToolkitShell) {
            Set-CursorVisible $true
        }
    }
}
