# 单选列表：ShellListRow + 列布局 + 行号/选中/翻页 + 列表导航底栏行

function New-ShellListColumnLayout {
    param(
        [ValidateSet('', 'ToolList', 'MenuList')]
        [string]$Preset = '',
        [int[]]$Widths = @()
    )

    if ($Preset -eq 'ToolList' -or $Preset -eq 'MenuList') {
        $cols = Get-ToolListColumnWidths
        $Widths = @([int]$cols.command, [int]$cols.name, [int]$cols.description)
    }

    if ($Widths.Count -lt 1) {
        throw 'New-ShellListColumnLayout requires -Preset or -Widths.'
    }

    return @{
        Preset = $Preset
        Widths = @($Widths)
    }
}

function ConvertTo-ShellListRows {
    param(
        [array]$Items,
        [Parameter(Mandatory)]
        [scriptblock]$MapCells,
        [scriptblock]$GetNumber = $null,
        [scriptblock]$GetSearchKey = $null,
        [scriptblock]$GetEnabled = $null,
        [switch]$KeepSource
    )

    $rows = New-Object 'System.Collections.Generic.List[object]'
    $index = 0
    foreach ($item in $Items) {
        $cells = @(& $MapCells $item $index)
        if ($null -eq $cells) { $cells = @() }
        $cells = @($cells | ForEach-Object { [string]$_ })

        $number = $index + 1
        if ($GetNumber) {
            $number = [int](& $GetNumber $item $index)
        }

        $searchKey = ''
        if ($GetSearchKey) {
            $searchKey = [string](& $GetSearchKey $item $index)
        }

        $enabled = $true
        if ($GetEnabled) {
            $enabled = [bool](& $GetEnabled $item $index)
        }

        $row = [ordered]@{
            Number    = $number
            Cells     = $cells
            Enabled   = $enabled
            SearchKey = $searchKey
        }
        if ($KeepSource) {
            $row['Source'] = $item
        }

        $rows.Add([pscustomobject]$row)
        $index++
    }

    return @($rows.ToArray())
}

function Normalize-ShellListRows {
    param(
        [array]$Rows,
        [hashtable]$ColumnLayout
    )

    $widthCount = $ColumnLayout.Widths.Count
    $normalized = New-Object 'System.Collections.Generic.List[object]'
    $index = 0

    foreach ($row in $Rows) {
        if ($null -eq $row.Cells) {
            throw 'ShellListRow requires Cells.'
        }
        $cells = @($row.Cells | ForEach-Object { [string]$_ })
        if ($cells.Count -ne $widthCount) {
            throw "ShellListRow.Cells count ($($cells.Count)) does not match column layout ($widthCount)."
        }

        $number = $index + 1
        if ($null -ne $row.Number -and [int]$row.Number -gt 0) {
            $number = [int]$row.Number
        }

        $enabled = $true
        if ($null -ne $row.PSObject.Properties['Enabled']) {
            $enabled = [bool]$row.Enabled
        }

        $searchKey = ''
        if ($null -ne $row.PSObject.Properties['SearchKey']) {
            $searchKey = [string]$row.SearchKey
        }

        $normalizedRow = [pscustomobject]@{
            Number    = $number
            Cells     = $cells
            Enabled   = $enabled
            SearchKey = $searchKey
            Source    = $row.Source
        }
        $normalized.Add($normalizedRow)
        $index++
    }

    return @($normalized.ToArray())
}

function Get-ShellListRowsCacheKey {
    param([array]$Rows)

    if ($Rows.Count -eq 0) { return '' }
    return (($Rows | ForEach-Object {
        $src = if ($null -ne $_.Source) { Get-ShellListItemCommand $_.Source } else { '' }
        $key = if ($null -ne $_.PSObject.Properties['SearchKey']) { [string]$_.SearchKey } else { '' }
        "$($_.Number):${key}:$($_.Cells -join '|'):$($_.Enabled):$src"
    }) -join ';')
}

function New-ShellListRowBodySegments {
    param(
        [string[]]$FormattedCells,
        [string]$Gap,
        [System.ConsoleColor]$LineColor
    )

    $segments = New-Object 'System.Collections.Generic.List[object]'
    for ($i = 0; $i -lt $FormattedCells.Count; $i++) {
        if ($i -gt 0) {
            $segments.Add(@{ Text = $Gap; Color = $LineColor })
        }
        $segments.Add(@{ Text = $FormattedCells[$i]; Color = $LineColor })
    }

    return @($segments.ToArray())
}

function Build-ShellSingleSelectListRowCache {
    param(
        [array]$Rows,
        [hashtable]$ColumnLayout
    )

    $widths = $ColumnLayout.Widths
    $colGap = ' ' * (Get-MenuColumnGap)
    $rowCache = New-Object 'object[]' $Rows.Count
    $lineColor = [System.ConsoleColor]::Gray

    for ($i = 0; $i -lt $Rows.Count; $i++) {
        $row = $Rows[$i]
        $formatted = New-Object 'string[]' $widths.Count
        for ($c = 0; $c -lt $widths.Count; $c++) {
            $formatted[$c] = Format-MenuTableCell -Text $row.Cells[$c] -Width $widths[$c]
        }

        $bodyPlain = ($formatted -join $colGap)
        $enabledColor = if ($row.Enabled) { $lineColor } else { [System.ConsoleColor]::DarkGray }
        $bodySegments = New-ShellListRowBodySegments -FormattedCells $formatted -Gap $colGap -LineColor $enabledColor

        $rowCache[$i] = [pscustomobject]@{
            BodyPlain    = $bodyPlain
            BodySegments = $bodySegments
            LineColor    = $enabledColor
            Enabled      = [bool]$row.Enabled
            Source       = $row.Source
            Number       = [int]$row.Number
        }
    }

    return @{
        RowCache = $rowCache
        ColGap   = $colGap
    }
}

function Build-ShellSingleSelectListRowSpec {
    param(
        $RowCacheEntry,
        [bool]$Selected,
        [int]$NumWidth,
        [int]$DisplayNumber,
        [string]$Gap
    )

    if (-not $RowCacheEntry) { return $null }

    $num = Format-ListDisplayNumber -Number $DisplayNumber -NumWidth $NumWidth
    $mark = if ($Selected) { '>' } else { ' ' }
    $lead = ' ' * (Get-ShellSingleSelectListLeadingSpaces)
    $prefix = "$lead$mark $num$Gap"

    if ($Selected) {
        return @{
            Text       = $prefix + $RowCacheEntry.BodyPlain
            Foreground = [System.ConsoleColor]::Black
            Background = [System.ConsoleColor]::Cyan
        }
    }

    return @{
        Segments          = @(@{ Text = $prefix; Color = $RowCacheEntry.LineColor }) + $(if ($null -ne $RowCacheEntry.BodySegments) { @($RowCacheEntry.BodySegments) } else { @() })
        DefaultForeground = $RowCacheEntry.LineColor
    }
}

function Write-ShellSingleSelectListRow {
    param(
        [int]$ScreenRow,
        [int]$DisplayNumber,
        [int]$NumWidth,
        [string]$Gap,
        [bool]$Selected,
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

function Invoke-ShellSingleSelectListDrawRow {
    param(
        [int]$ScreenRow,
        [int]$Index,
        [array]$RowCache,
        [string]$ColGap,
        [bool]$Selected,
        [int]$NumWidth,
        [int]$DisplayNumber,
        [bool]$Enabled,
        [int]$ContentLineWidth = 0,
        [int]$ContentStartColumn = 0
    )

    if ($Index -lt 0 -or $Index -ge $RowCache.Count) { return }
    $part = $RowCache[$Index]
    if (-not $part) { return }

    $spec = Build-ShellSingleSelectListRowSpec -RowCacheEntry $part -Selected $Selected `
        -NumWidth $NumWidth -DisplayNumber $DisplayNumber -Gap $ColGap
    Write-ShellSingleSelectListRow -ScreenRow $ScreenRow -DisplayNumber $DisplayNumber `
        -NumWidth $NumWidth -Gap $ColGap -Selected $Selected -Enabled $Enabled -RowSpec $spec `
        -ContentLineWidth $ContentLineWidth -ContentStartColumn $ContentStartColumn
}

function New-ShellSingleSelectListDrawHandlers {
    param(
        [array]$RowCache,
        [string]$ColGap,
        [int]$ContentLineWidth = 0,
        [int]$ContentStartColumn = 0
    )

    $cacheSnapshot = @($RowCache)
    $gapSnapshot = [string]$ColGap
    $contentWidthSnapshot = [int]$ContentLineWidth
    $contentStartSnapshot = [int]$ContentStartColumn

    $getLabel = {
        param($Item, [int]$Index)
        if ($Index -lt 0 -or $Index -ge $RowCache.Count) { return '' }
        $part = $RowCache[$Index]
        if (-not $part) { return '' }
        return [string]$part.BodyPlain
    }.GetNewClosure()

    $getListRowSpec = {
        param(
            [int]$Index,
            [bool]$Selected,
            [int]$NumWidth,
            [int]$DisplayNumber,
            [bool]$Enabled
        )

        if ($Index -lt 0 -or $Index -ge $RowCache.Count -or -not $RowCache[$Index]) {
            return $null
        }
        return (Build-ShellSingleSelectListRowSpec -RowCacheEntry $RowCache[$Index] -Selected $Selected `
            -NumWidth $NumWidth -DisplayNumber $DisplayNumber -Gap $ColGap)
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

        Invoke-ShellSingleSelectListDrawRow -ScreenRow $ScreenRow -Index $Index `
            -RowCache $cacheSnapshot -ColGap $gapSnapshot -Selected $Selected `
            -NumWidth $NumWidth -DisplayNumber $DisplayNumber -Enabled $Enabled `
            -ContentLineWidth $contentWidthSnapshot -ContentStartColumn $contentStartSnapshot
    }.GetNewClosure()

    return @{
        GetLabel       = $getLabel
        GetListRowSpec = $getListRowSpec
        DrawListRow    = $drawListRow
    }
}

function Get-ShellListRowDisplayNumber {
    param(
        $Row,
        [int]$Index
    )

    if ($null -eq $Row) { return $Index + 1 }
    if ($null -ne $Row.PSObject.Properties['Number'] -and [int]$Row.Number -gt 0) {
        return [int]$Row.Number
    }
    return $Index + 1
}

function Resolve-ShellListRowNumberIndex {
    param(
        [array]$Rows,
        [int]$Number
    )

    if ($Number -lt 1) { return -1 }
    for ($i = 0; $i -lt $Rows.Count; $i++) {
        if ([int](Get-ShellListRowDisplayNumber -Row $Rows[$i] -Index $i) -eq $Number) {
            return $i
        }
    }
    return -1
}

function Get-ShellListRowSearchKey {
    param(
        $Row,
        [int]$Index
    )

    if ($null -eq $Row) { return '' }
    if ($null -ne $Row.PSObject.Properties['SearchKey'] -and -not [string]::IsNullOrEmpty([string]$Row.SearchKey)) {
        return [string]$Row.SearchKey
    }
    return [string](Get-ShellListRowDisplayNumber -Row $Row -Index $Index)
}

function Normalize-ShellListSearchKeyDigits {
    param([string]$Text)

    if ([string]::IsNullOrEmpty($Text)) { return '' }
    return ($Text -replace '\D', '')
}

function Test-ShellListSearchKeyPrefixMatch {
    param(
        [string]$SearchKey,
        [string]$Buffer,
        [switch]$DigitsOnly
    )

    if ([string]::IsNullOrEmpty($Buffer)) { return $true }

    if ($DigitsOnly) {
        if ($Buffer -notmatch '^[0-9]+$') { return $false }
        return (Normalize-ShellListSearchKeyDigits $SearchKey).StartsWith($Buffer)
    }

    if ($Buffer -notmatch '^[0-9.]+$') { return $false }
    return $SearchKey.StartsWith($Buffer)
}

function Resolve-ShellListRowSearchKeyPrefixIndex {
    param(
        [array]$Rows,
        [string]$Prefix,
        [scriptblock]$TestItemEnabled = $null,
        [switch]$SearchKeyDigitsOnly
    )

    if ([string]::IsNullOrEmpty($Prefix)) { return -1 }
    for ($i = 0; $i -lt $Rows.Count; $i++) {
        if ($TestItemEnabled -and -not (& $TestItemEnabled $Rows[$i] $i)) { continue }
        $key = Get-ShellListRowSearchKey -Row $Rows[$i] -Index $i
        if (Test-ShellListSearchKeyPrefixMatch -SearchKey $key -Buffer $Prefix -DigitsOnly:$SearchKeyDigitsOnly) {
            return $i
        }
    }
    return -1
}

function Get-ShellSingleSelectListRowCache {
    param(
        [hashtable]$Shell,
        [string]$CacheKey,
        [array]$Rows,
        [hashtable]$ColumnLayout
    )

    $locale = Get-CurrentLocale
    $layoutKey = if ($ColumnLayout.Preset) {
        "$($ColumnLayout.Preset)|$($ColumnLayout.Widths -join ',')"
    }
    else {
        ($ColumnLayout.Widths -join ',')
    }
    $rowsKey = Get-ShellListRowsCacheKey -Rows $Rows
    $cacheField = "${CacheKey}ListRowCache"
    $localeField = "${CacheKey}ListRowCacheLocale"
    $keyField = "${CacheKey}ListRowCacheKey"
    $gapField = "${CacheKey}ListColGap"

    if ($Shell -and $Shell[$cacheField] -and $Shell[$localeField] -eq $locale `
        -and $Shell[$keyField] -eq "$layoutKey|$rowsKey") {
        $cachedRows = @($Shell[$cacheField])
        if ($cachedRows.Count -eq $Rows.Count) {
            return @{
                RowCache = $Shell[$cacheField]
                ColGap   = $Shell[$gapField]
            }
        }
        Clear-ShellSingleSelectListCache -Shell $Shell -CacheKey $CacheKey
    }

    $diskBuilt = $null
    if (Get-Command Get-ToolkitDiskListRowCache -ErrorAction SilentlyContinue) {
        $diskBuilt = Get-ToolkitDiskListRowCache -CacheKey $CacheKey -Locale $locale `
            -LayoutKey $layoutKey -RowsKey $rowsKey
    }
    if ($diskBuilt) {
        if ($Shell) {
            $Shell[$cacheField] = $diskBuilt.RowCache
            $Shell[$localeField] = $locale
            $Shell[$keyField] = "$layoutKey|$rowsKey"
            $Shell[$gapField] = $diskBuilt.ColGap
        }
        return $diskBuilt
    }

    $built = Build-ShellSingleSelectListRowCache -Rows $Rows -ColumnLayout $ColumnLayout
    if ($Shell) {
        $Shell[$cacheField] = $built.RowCache
        $Shell[$localeField] = $locale
        $Shell[$keyField] = "$layoutKey|$rowsKey"
        $Shell[$gapField] = $built.ColGap
    }

    return $built
}

function Resolve-ShellSingleSelectListPick {
    param($Picked)

    if (-not $Picked) { return $null }
    if (Test-ShellNavMarker $Picked) { return $Picked }
    if ($null -ne $Picked.Source) { return $Picked.Source }
    return $Picked
}

function Test-ShellListRowEnabled {
    param($Row, [int]$Index)

    if ($null -eq $Row) { return $false }
    if ($null -eq $Row.PSObject.Properties['Enabled']) { return $true }
    return [bool]$Row.Enabled
}

function Invoke-ShellSingleSelectList {
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
        [switch]$SkipBodyInit
    )

    if ([string]::IsNullOrWhiteSpace($CountLabel)) {
        $CountLabel = Get-I18n -Key 'common.piece'
    }

    Sync-MiaoLocaleFromShell -Shell $Shell

    $maxNumberPreview = 0
    for ($i = 0; $i -lt $Rows.Count; $i++) {
        $row = $Rows[$i]
        $n = if ($null -ne $row.PSObject.Properties['Number'] -and [int]$row.Number -gt 0) {
            [int]$row.Number
        }
        elseif ($null -ne $row.PSObject.Properties['Source'] -and $row.Source) {
            [int](Get-ListItemDisplayNumberDefault -Item $row.Source -Index $i)
        }
        else {
            $i + 1
        }
        if ($n -gt $maxNumberPreview) { $maxNumberPreview = $n }
    }
    if ($maxNumberPreview -lt $Rows.Count) { $maxNumberPreview = $Rows.Count }
    if ($maxNumberPreview -lt 1) { $maxNumberPreview = 1 }
    $numWidthPreview = Get-ListNumberDisplayWidth -MaxNumber $maxNumberPreview
    if ($ColumnLayout.Preset -eq 'ToolList' -or $ColumnLayout.Preset -eq 'MenuList') {
        $ColumnLayout = Resolve-ShellToolListColumnLayout -Shell $Shell -NumWidth $numWidthPreview `
            -Preset $ColumnLayout.Preset
    }

    $normalized = @(Normalize-ShellListRows -Rows $Rows -ColumnLayout $ColumnLayout)

    if (-not $SkipBodyInit) {
        Initialize-ToolkitShellBodyView -Shell $Shell `
            -SectionTitle $SectionTitle `
            -FooterTemplate ListWithToolbar
    }

    $header = New-ToolkitMenuHeader -HideSectionTitle
    $built = Get-ShellSingleSelectListRowCache -Shell $Shell -CacheKey $CacheKey `
        -Rows $normalized -ColumnLayout $ColumnLayout
    $rowCache = $built.RowCache
    $gapField = "${CacheKey}ListColGap"
    $colGap = if ($Shell[$gapField]) { $Shell[$gapField] } else { $built.ColGap }
    $maxNumber = 0
    for ($i = 0; $i -lt $normalized.Count; $i++) {
        $n = [int](Get-ShellListRowDisplayNumber -Row $normalized[$i] -Index $i)
        if ($n -gt $maxNumber) { $maxNumber = $n }
    }
    if ($maxNumber -lt 1) { $maxNumber = $normalized.Count }
    $numWidth = Get-ListNumberDisplayWidth -MaxNumber $maxNumber
    $contentMetrics = Get-ToolkitShellContentMetrics -Shell $Shell
    $handlers = New-ShellSingleSelectListDrawHandlers -RowCache $rowCache -ColGap $colGap `
        -ContentLineWidth ([int]$contentMetrics.EndColumn) `
        -ContentStartColumn ([int]$contentMetrics.StartColumn)
    if (-not $handlers['GetLabel'] -or -not $handlers['DrawListRow']) {
        throw 'Invoke-ShellSingleSelectList: list draw handlers are not available.'
    }

    $getDisplayNumber = {
        param($Row, [int]$Index)
        if ($null -eq $Row) { return $Index + 1 }
        if ($null -ne $Row.PSObject.Properties['Number'] -and [int]$Row.Number -gt 0) {
            return [int]$Row.Number
        }
        return $Index + 1
    }

    $resolveMenuNumber = {
        param([array]$Items, [int]$Number)
        if ($Number -lt 1) { return -1 }
        for ($i = 0; $i -lt $Items.Count; $i++) {
            $row = $Items[$i]
            $displayNumber = if ($null -ne $row.PSObject.Properties['Number'] -and [int]$row.Number -gt 0) {
                [int]$row.Number
            }
            else {
                $i + 1
            }
            if ($displayNumber -eq $Number) { return $i }
        }
        return -1
    }

    $testRowEnabled = {
        param($Row, [int]$Index)
        if ($null -eq $Row) { return $false }
        if ($null -eq $Row.PSObject.Properties['Enabled']) { return $true }
        return [bool]$Row.Enabled
    }

    $letterKeys = if ($ToolbarConfig.LetterKeys) { $ToolbarConfig.LetterKeys } else { @{} }

    $picked = Show-PaginatedMenu -Header $header -Items $normalized -CountLabel $CountLabel `
        -GetItemLabel $handlers['GetLabel'] `
        -TestItemEnabled $testRowEnabled `
        -HideColHeader -FooterLayout Split `
        -GetItemDisplayNumber $getDisplayNumber `
        -ResolveMenuNumber $resolveMenuNumber `
        -NumberDisplayWidth $numWidth `
        -DrawListRow $handlers['DrawListRow'] `
        -GetListRowSpec $handlers['GetListRowSpec'] `
        -MenuSplitActionSegments @($ToolbarConfig.Segments) `
        -LetterKeys $letterKeys `
        -ToolkitShell $Shell `
        -AllowBack:($ToolbarConfig.AllowBack) `
        -CompactNavStatus:($ColumnLayout.Preset -eq 'ToolList') `
        -AllowSpaceConfirm:($ColumnLayout.Preset -eq 'ToolList')

    return Resolve-ShellSingleSelectListPick -Picked $picked
}

function Clear-ShellSingleSelectListCache {
    param(
        [hashtable]$Shell,
        [string]$CacheKey
    )

    if (-not $Shell) { return }
    $Shell.Remove("${CacheKey}ListRowCache")
    $Shell.Remove("${CacheKey}ListRowCacheLocale")
    $Shell.Remove("${CacheKey}ListRowCacheKey")
    $Shell.Remove("${CacheKey}ListColGap")
}
