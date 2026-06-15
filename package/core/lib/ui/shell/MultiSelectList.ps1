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
        [hashtable]$ColumnLayout
    )

    $built = Build-ShellSingleSelectListRowCache -Rows $Rows -ColumnLayout $ColumnLayout
    if ($Rows.Count -gt 0) {
        for ($i = 0; $i -lt $Rows.Count; $i++) {
            $searchKey = ''
            if ($null -ne $Rows[$i].PSObject.Properties['SearchKey']) {
                $searchKey = [string]$Rows[$i].SearchKey
            }
            if ([string]::IsNullOrEmpty($searchKey)) { continue }

            $entry = $built.RowCache[$i]
            $built.RowCache[$i] = [pscustomobject]@{
                BodyPlain    = $entry.BodyPlain
                BodySegments = $entry.BodySegments
                LineColor    = $entry.LineColor
                Enabled      = $entry.Enabled
                Source       = $entry.Source
                Number       = $entry.Number
                SearchKey    = $searchKey
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
        [string]$DisplayKey = ''
    )

    if (-not $RowCacheEntry) { return $null }

    $enabled = [bool]$RowCacheEntry.Enabled
    $check = Format-ShellMultiSelectCheckMark -Checked $Checked -Enabled $enabled
    $mark = if ($Selected) { '>' } else { ' ' }
    if ($UseSearchKeyColumn) {
        $keyText = Pad-DisplayText -Text $DisplayKey -TargetWidth $KeyWidth
        $prefix = " $mark $check $keyText$Gap"
    }
    else {
        $num = Format-ListDisplayNumber -Number $DisplayNumber -NumWidth $NumWidth
        $prefix = " $mark $check $num$Gap"
    }
    $lineColor = if ($enabled) { $RowCacheEntry.LineColor } else { [System.ConsoleColor]::DarkGray }

    if ($Selected) {
        $foreground = if ($enabled) { [System.ConsoleColor]::Black } else { [System.ConsoleColor]::DarkGray }
        return @{
            Text       = $prefix + $RowCacheEntry.BodyPlain
            Foreground = $foreground
            Background = [System.ConsoleColor]::Cyan
        }
    }

    if ($UseSearchKeyColumn) {
        $keyText = Pad-DisplayText -Text $DisplayKey -TargetWidth $KeyWidth
        $keySeg = @{ Text = "$keyText$Gap"; Color = $lineColor }
    }
    else {
        $num = Format-ListDisplayNumber -Number $DisplayNumber -NumWidth $NumWidth
        $keySeg = @{ Text = "$num$Gap"; Color = $lineColor }
    }

    $checkSeg = @{ Text = "$mark $check "; Color = $lineColor }
    $bodySegs = @()
    if ($null -ne $RowCacheEntry.BodySegments) {
        $bodySegs = @($RowCacheEntry.BodySegments)
    }
    return @{
        Segments          = @($checkSeg, $keySeg) + $bodySegs
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
        [int]$ContentLineWidth = 0,
        [int]$ContentStartColumn = 0
    )

    if (-not $RowSpec) { return }

    if (Test-UseConsoleListBufferDraw) {
        try {
            $highlightWidth = if ($Selected) { $ContentLineWidth } else { 0 }
            $highlightStart = if ($Selected) { $ContentStartColumn } else { 0 }
            Write-ListRowFromSpec -ScreenRow $ScreenRow -Spec $RowSpec -ContentLineWidth $highlightWidth `
                -ContentStartColumn $highlightStart
            return
        }
        catch { }
    }

    Prepare-ConsoleRowWrite -Row $ScreenRow
    try { [Console]::SetCursorPosition(0, $ScreenRow) } catch { return }

    $width = Get-SafeWriteLineWidth -Row $ScreenRow
    if ($Selected) {
        $region = Resolve-ConsoleContentHighlightRegion -Row $ScreenRow `
            -ContentStartColumn $ContentStartColumn -ContentLineWidth $ContentLineWidth
        Write-ConsoleRowHighlightText -Text ([string]$RowSpec.Text) -Region $region
        Set-ConsoleCursorAfterRowWrite -Row $ScreenRow
        return
    }

    $used = 0
    foreach ($seg in $RowSpec.Segments) {
        if (-not $seg) { continue }
        if ($used -ge $width) { break }
        $partWidth = Get-DisplayWidth $seg.Text
        $remaining = $width - $used
        $text = if ($partWidth -gt $remaining) { Truncate-DisplayText $seg.Text $remaining } else { $seg.Text }
        if ([string]::IsNullOrEmpty($text)) { break }
        Write-Host $text -NoNewline -ForegroundColor $seg.Color
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
        [int]$ContentLineWidth = 0,
        [int]$ContentStartColumn = 0,
        [switch]$UseSearchKeyColumn,
        [int]$KeyWidth = 0,
        [string]$DisplayKey = ''
    )

    if ($Index -lt 0 -or $Index -ge $RowCache.Count) { return }
    $part = $RowCache[$Index]
    if (-not $part) { return }

    $spec = Build-ShellMultiSelectListRowSpec -RowCacheEntry $part -Selected $Selected -Checked $Checked `
        -NumWidth $NumWidth -DisplayNumber $DisplayNumber -Gap $ColGap `
        -UseSearchKeyColumn:$UseSearchKeyColumn -KeyWidth $KeyWidth -DisplayKey $DisplayKey
    Write-ShellMultiSelectListRow -ScreenRow $ScreenRow -DisplayNumber $DisplayNumber `
        -NumWidth $NumWidth -Gap $ColGap -Selected $Selected -Checked $Checked -Enabled $Enabled `
        -RowSpec $spec -ContentLineWidth $ContentLineWidth -ContentStartColumn $ContentStartColumn
}

function New-ShellMultiSelectListDrawHandlers {
    param(
        [array]$RowCache,
        [string]$ColGap,
        [System.Collections.Generic.HashSet[int]]$CheckedIndexSet = $null,
        [int]$ContentLineWidth = 0,
        [int]$ContentStartColumn = 0,
        [switch]$SearchKeyMode,
        [int]$SearchKeyWidth = 0
    )

    $cacheSnapshot = @($RowCache)
    $gapSnapshot = [string]$ColGap
    $contentWidthSnapshot = [int]$ContentLineWidth
    $contentStartSnapshot = [int]$ContentStartColumn
    $checkedSetSnapshot = $CheckedIndexSet
    $searchKeyModeSnapshot = [bool]$SearchKeyMode
    $searchKeyWidthSnapshot = if ($SearchKeyWidth -gt 0) { [int]$SearchKeyWidth } else { (Get-ShellMultiSelectSearchKeyWidth) }

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
        return (Build-ShellMultiSelectListRowSpec -RowCacheEntry $part -Selected $Selected `
            -Checked $checked -NumWidth $NumWidth -DisplayNumber $DisplayNumber -Gap $gapSnapshot `
            -UseSearchKeyColumn:$searchKeyModeSnapshot -KeyWidth $searchKeyWidthSnapshot -DisplayKey $displayKey)
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
        Invoke-ShellMultiSelectListDrawRow -ScreenRow $ScreenRow -Index $Index `
            -RowCache $cacheSnapshot -ColGap $gapSnapshot -Selected $Selected `
            -Checked $checked -NumWidth $NumWidth -DisplayNumber $DisplayNumber `
            -Enabled $Enabled -ContentLineWidth $contentWidthSnapshot -ContentStartColumn $contentStartSnapshot `
            -UseSearchKeyColumn:$searchKeyModeSnapshot -KeyWidth $searchKeyWidthSnapshot -DisplayKey $displayKey
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
        [hashtable]$ColumnLayout
    )

    $locale = Get-CurrentLocale
    $layoutKey = if ($ColumnLayout.Preset) { $ColumnLayout.Preset } else { ($ColumnLayout.Widths -join ',') }
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

    $built = Build-ShellMultiSelectListRowCache -Rows $Rows -ColumnLayout $ColumnLayout
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

function Resolve-ShellMultiSelectListPick {
    param($Picked)

    if ($null -eq $Picked) { return @() }
    if (Test-ShellNavMarker $Picked) { return $Picked }
    if ($Picked -is [array]) {
        return @($Picked | ForEach-Object {
            if ($null -ne $_.Source) { $_.Source } else { $_ }
        })
    }
    if ($null -ne $Picked.Source) { return @($Picked.Source) }
    return @($Picked)
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
        [string]$FlashItemDisabled = ''
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
    if (-not $layout.ContentLineWidth -or -not $layout.ContentStartColumn) {
        $metrics = if ($ToolkitShell.ContentMetrics) {
            $ToolkitShell.ContentMetrics
        }
        else {
            Get-ToolkitShellContentMetrics -Shell $ToolkitShell
        }
        $layout['ContentStartColumn'] = [int]$metrics.StartColumn
        $layout['ContentLineWidth'] = [int]$metrics.EndColumn
    }

    $resolveNumberFn = $ResolveMenuNumber
    if (-not $resolveNumberFn) {
        $resolveNumberFn = ${function:Resolve-ListNumberIndexDefault}
    }

    if ($SearchKeyMode -and -not $GetItemSearchKey) {
        $GetItemSearchKey = {
            param($Item, [int]$Index)
            Get-ShellListRowSearchKey -Row $Item -Index $Index
        }
    }

    if ($SearchKeyMode) {
        $keyWidth = if ($SearchKeyWidth -gt 0) { $SearchKeyWidth } else { (Get-ShellMultiSelectSearchKeyWidth) }
        $numWidth = $keyWidth
        $singleDigitSelect = $false
    }
    else {
        $maxDisplayNumber = Get-MenuMaxDisplayNumber -Items $Items -GetItemDisplayNumber $GetItemDisplayNumber
        if ($NumberDisplayWidth -gt 0) {
            $numWidth = $NumberDisplayWidth
        }
        else {
            $numWidth = Get-ListNumberDisplayWidth -MaxNumber $maxDisplayNumber
        }
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

    $contentLineWidth = [int]$layout.ContentLineWidth
    $contentStartColumn = [int]$layout.ContentStartColumn
    $handlers = New-ShellMultiSelectListDrawHandlers -RowCache $RowCache -ColGap $ColGap `
        -CheckedIndexSet $checkedIndexSet -ContentLineWidth $contentLineWidth `
        -ContentStartColumn $contentStartColumn -SearchKeyMode:$SearchKeyMode `
        -SearchKeyWidth $(if ($SearchKeyMode) { $numWidth } else { 0 })

    function Apply-MultiSelectInputBuffer {
        param([string]$Buffer)
        if ([string]::IsNullOrEmpty($Buffer)) { return }
        if ($Items.Count -eq 0) { return }

        $idx = -1
        if ($SearchKeyMode) {
            $idx = Resolve-ShellListRowSearchKeyPrefixIndex -Rows $Items -Prefix $Buffer `
                -SearchKeyDigitsOnly
        }
        else {
            $num = [int]$Buffer
            $idx = & $resolveNumberFn $Items $num
        }
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
            $flashMessage = ''
            $checkToggled = $false

            if ($ToolkitShell) {
                Prepare-ToolkitShellBodyDraw -Shell $ToolkitShell
            }
            $key = [Console]::ReadKey($true)
            if ($ToolkitShell) {
                Set-CursorVisible $false
            }

            if ($key.Key -eq 'Backspace') {
                if (-not [string]::IsNullOrEmpty($numberBuffer)) {
                    if ($SearchKeyMode -or -not $singleDigitSelect) {
                        $numberBuffer = $numberBuffer.Substring(0, $numberBuffer.Length - 1)
                        if (-not [string]::IsNullOrEmpty($numberBuffer)) {
                            Apply-MultiSelectInputBuffer -Buffer $numberBuffer
                        }
                    }
                }
            }
            elseif ($SearchKeyMode -and $key.KeyChar -match '^[0-9]$') {
                $candidate = $numberBuffer + [string]$key.KeyChar
                if (& $fnTestSearchPrefix -Items $Items -Buffer $candidate `
                        -GetItemSearchKey $GetItemSearchKey -SearchKeyDigitsOnly) {
                    $numberBuffer = $candidate
                    Apply-MultiSelectInputBuffer -Buffer $numberBuffer
                }
            }
            elseif (-not $SearchKeyMode -and $key.KeyChar -match '^[0-9]$') {
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
                if ($LetterKeys -and $LetterKeys.ContainsKey($letter)) {
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
                        if ($selectedIndex -gt 0) {
                            $selectedIndex--
                            $newPage = [Math]::Floor($selectedIndex / [double]$PageSize)
                            if ($newPage -ne $pageIndex) {
                                $pageIndex = $newPage
                                $listScrollOffset = 0
                            }
                            & $fnSetListScroll -ScrollOffset ([ref]$listScrollOffset) `
                                -SelectedIndex $selectedIndex -PageIndex $pageIndex -PageSize $PageSize `
                                -ItemCount $Items.Count -ViewportHeight $layout.ListViewportHeight
                        }
                    }
                    'DownArrow' {
                        $numberBuffer = ''
                        if ($selectedIndex -lt ($Items.Count - 1)) {
                            $selectedIndex++
                            $newPage = [Math]::Floor($selectedIndex / [double]$PageSize)
                            if ($newPage -ne $pageIndex) {
                                $pageIndex = $newPage
                                $listScrollOffset = 0
                            }
                            & $fnSetListScroll -ScrollOffset ([ref]$listScrollOffset) `
                                -SelectedIndex $selectedIndex -PageIndex $pageIndex -PageSize $PageSize `
                                -ItemCount $Items.Count -ViewportHeight $layout.ListViewportHeight
                        }
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
            $checkChanged = $checkToggled
            $bufferChanged = ($oldNumberBuffer -ne $numberBuffer)
            $footerChanged = $pageChanged -or $flashMessage -or $bufferChanged
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
                    -GetListRowSpec $handlers['GetListRowSpec'] -ContentLineWidth $contentLineWidth `
                    -ContentStartColumn $contentStartColumn
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

function Invoke-ShellMultiSelectList {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Shell,
        [Parameter(Mandatory)]
        [string]$SectionTitle,
        [Parameter(Mandatory)]
        [array]$Rows,
        [Parameter(Mandatory)]
        [string]$CacheKey,
        [Parameter(Mandatory)]
        [hashtable]$ColumnLayout,
        [Parameter(Mandatory)]
        [hashtable]$ToolbarConfig,
        [string]$CountLabel = '',
        [switch]$SkipBodyInit,
        [string]$FlashNothingSelectedKey = 'common.nothingSelected',
        [string]$FlashItemDisabledKey = 'message.disabledItem',
        [string]$FlashNothingSelected = '',
        [string]$FlashItemDisabled = '',
        [switch]$SearchKeyMode,
        [int]$SearchKeyWidth = 0
    )

    if ([string]::IsNullOrWhiteSpace($CountLabel)) {
        $CountLabel = Get-I18n -Key 'common.piece'
    }

    Sync-MiaoLocaleFromShell -Shell $Shell

    Initialize-ShellMultiSelectListDependencies

    $normalized = @(Normalize-ShellListRows -Rows $Rows -ColumnLayout $ColumnLayout)

    if (-not $SkipBodyInit) {
        Initialize-ToolkitShellBodyView -Shell $Shell `
            -SectionTitle $SectionTitle `
            -FooterTemplate ListWithToolbar
    }

    $header = New-ToolkitMenuHeader -HideSectionTitle
    $built = Get-ShellMultiSelectListRowCache -Shell $Shell -CacheKey $CacheKey `
        -Rows $normalized -ColumnLayout $ColumnLayout
    $rowCache = $built.RowCache
    $gapField = "${CacheKey}MultiListColGap"
    $colGap = if ($Shell[$gapField]) { $Shell[$gapField] } else { $built.ColGap }

    $contentMetrics = Get-ToolkitShellContentMetrics -Shell $Shell
    $null = Get-ShellMultiSelectCheckedSet -Shell $Shell -CacheKey $CacheKey

    $getDisplayNumber = {
        param($Row, [int]$Index)
        Get-ShellListRowDisplayNumber -Row $Row -Index $Index
    }

    $getSearchKey = {
        param($Row, [int]$Index)
        Get-ShellListRowSearchKey -Row $Row -Index $Index
    }

    $resolveMenuNumber = {
        param([array]$Items, [int]$Number)
        Resolve-ShellListRowNumberIndex -Rows $Items -Number $Number
    }

    $testRowEnabled = {
        param($Row, [int]$Index)
        Test-ShellListRowEnabled -Row $Row -Index $Index
    }

    $letterKeys = if ($ToolbarConfig.LetterKeys) { $ToolbarConfig.LetterKeys } else { @{} }

    $numberWidth = 0
    if (-not $SearchKeyMode) {
        $maxNumber = 0
        for ($i = 0; $i -lt $normalized.Count; $i++) {
            $n = [int](Get-ShellListRowDisplayNumber -Row $normalized[$i] -Index $i)
            if ($n -gt $maxNumber) { $maxNumber = $n }
        }
        if ($maxNumber -lt 1) { $maxNumber = $normalized.Count }
        $numberWidth = Get-ListNumberDisplayWidth -MaxNumber $maxNumber
    }

    $picked = Show-ShellMultiSelectListMenu -Header $header -Items $normalized -CountLabel $CountLabel `
        -TestItemEnabled $testRowEnabled -GetItemDisplayNumber $getDisplayNumber `
        -GetItemSearchKey $getSearchKey -ResolveMenuNumber $resolveMenuNumber `
        -NumberDisplayWidth $numberWidth -SearchKeyMode:$SearchKeyMode `
        -SearchKeyWidth $SearchKeyWidth -RowCache $rowCache -ColGap $colGap -CheckedCacheKey $CacheKey `
        -MenuSplitActionSegments @($ToolbarConfig.Segments) -LetterKeys $letterKeys `
        -ToolkitShell $Shell -AllowBack:($ToolbarConfig.AllowBack) `
        -FlashNothingSelectedKey $FlashNothingSelectedKey -FlashItemDisabledKey $FlashItemDisabledKey `
        -FlashNothingSelected $FlashNothingSelected -FlashItemDisabled $FlashItemDisabled

    return Resolve-ShellMultiSelectListPick -Picked $picked
}
