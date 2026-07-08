# 单选列表：行绘制与缓存（入口 Invoke-ToolkitShellList -Mode Single）

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
        [hashtable]$ColumnLayout,
        [scriptblock]$OnProgress = $null
    )

    if (-not (Get-Command Build-ShellListRowBodyFromCells -ErrorAction SilentlyContinue)) {
        . (Join-Path $PSScriptRoot 'ShellListScroll.ps1')
    }

    $widths = $ColumnLayout.Widths
    $colGap = ' ' * (Get-MenuColumnGap)
    $rowCache = New-Object 'object[]' $Rows.Count
    $lineColor = [System.ConsoleColor]::Gray
    $scrollColumn = -1
    if ($ColumnLayout.ContainsKey('ScrollColumn')) {
        $scrollColumn = [int]$ColumnLayout.ScrollColumn
    }
    $progressStep = 25

    for ($i = 0; $i -lt $Rows.Count; $i++) {
        if ($OnProgress -and ($i -eq 0 -or ($i % $progressStep) -eq 0 -or $i -eq ($Rows.Count - 1))) {
            & $OnProgress $i $Rows.Count
        }
        $row = $Rows[$i]
        $rawCells = @($row.Cells | ForEach-Object { [string]$_ })
        $cellColors = $null
        if ($null -ne $row.PSObject.Properties['CellColors'] -and $row.CellColors) {
            $cellColors = @($row.CellColors)
        }

        $enabled = [bool]$row.Enabled
        $enabledColor = if ($enabled) { $lineColor } else { [System.ConsoleColor]::DarkGray }
        $body = Build-ShellListRowBodyFromCells -RawCells $rawCells -Widths $widths -Gap $colGap `
            -DefaultLineColor $enabledColor -CellColors $cellColors -Enabled $enabled `
            -ScrollColumn $scrollColumn

        $source = $null
        if ($null -ne $row.PSObject.Properties['Payload']) { $source = $row.Payload }
        elseif ($null -ne $row.PSObject.Properties['Source']) { $source = $row.Source }

        $rowCache[$i] = [pscustomobject]@{
            BodyPlain      = [string]$body.BodyPlain
            BodySegments   = @($body.BodySegments)
            LineColor      = $enabledColor
            Enabled        = $enabled
            Source         = $source
            Number         = [int]$row.Number
            RawCells       = $rawCells
            Widths         = @($widths)
            CellColors     = $cellColors
            ScrollOverflow = @($body.ScrollOverflow)
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
        [string]$Gap,
        [int]$ScrollColumn = -1,
        [int]$MarqueeOffset = 0
    )

    if (-not $RowCacheEntry) { return $null }

    if (-not (Get-Command Test-ShellListRowMarqueeActive -ErrorAction SilentlyContinue)) {
        . (Join-Path $PSScriptRoot 'ShellListScroll.ps1')
    }

    $num = Format-ListDisplayNumber -Number $DisplayNumber -NumWidth $NumWidth
    $mark = if ($Selected) { '>' } else { ' ' }
    $lineColor = $RowCacheEntry.LineColor
    $enabled = [bool]$RowCacheEntry.Enabled
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

    if ($Selected -and -not $marqueeActive) {
        $prefix = " $mark $num$Gap"
        return @{
            Text       = $prefix + $RowCacheEntry.BodyPlain
            Foreground = [System.ConsoleColor]::Black
            Background = [System.ConsoleColor]::Cyan
        }
    }

    if ($Selected -and $marqueeActive) {
        $markSeg = @{ Text = "$mark "; Color = $lineColor }
        $keySeg = @{ Text = "$num$Gap"; Color = $lineColor }
        return @{
            Segments          = @($markSeg, $keySeg) + $bodySegs
            DefaultForeground = [System.ConsoleColor]::Black
            Background        = [System.ConsoleColor]::Cyan
        }
    }

    $markSeg = @{ Text = "$mark "; Color = $lineColor }
    $keySeg = @{ Text = "$num$Gap"; Color = $lineColor }
    return @{
        Segments          = @($markSeg, $keySeg) + $bodySegs
        DefaultForeground = $lineColor
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
        [int]$LayoutLineWidth = 0,
        [int]$LayoutStartColumn = 0,
        [int]$ScrollColumn = -1,
        [int]$MarqueeOffset = 0
    )

    if ($Index -lt 0 -or $Index -ge $RowCache.Count) { return }
    $part = $RowCache[$Index]
    if (-not $part) { return }

    $spec = Build-ShellSingleSelectListRowSpec -RowCacheEntry $part -Selected $Selected `
        -NumWidth $NumWidth -DisplayNumber $DisplayNumber -Gap $ColGap `
        -ScrollColumn $ScrollColumn -MarqueeOffset $MarqueeOffset
    Write-ShellSingleSelectListRow -ScreenRow $ScreenRow -DisplayNumber $DisplayNumber `
        -NumWidth $NumWidth -Gap $ColGap -Selected $Selected -Enabled $Enabled -RowSpec $spec `
        -LayoutLineWidth $LayoutLineWidth -LayoutStartColumn $LayoutStartColumn
}

function New-ShellSingleSelectListDrawHandlers {
    param(
        [array]$RowCache,
        [string]$ColGap,
        [int]$LayoutLineWidth = 0,
        [int]$LayoutStartColumn = 0,
        [int]$ScrollColumn = -1,
        [scriptblock]$GetMarqueeOffset = $null
    )

    $cacheSnapshot = @($RowCache)
    $gapSnapshot = [string]$ColGap
    $contentWidthSnapshot = [int]$LayoutLineWidth
    $contentStartSnapshot = [int]$LayoutStartColumn
    $scrollColumnSnapshot = [int]$ScrollColumn
    $getOffset = $GetMarqueeOffset

    $getLabel = {
        param($Item, [int]$Index)
        if ($Index -lt 0 -or $Index -ge $cacheSnapshot.Count) { return '' }
        $part = $cacheSnapshot[$Index]
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

        if ($Index -lt 0 -or $Index -ge $cacheSnapshot.Count -or -not $cacheSnapshot[$Index]) {
            return $null
        }
        $offset = 0
        if ($getOffset) { $offset = [int](& $getOffset) }
        return (Build-ShellSingleSelectListRowSpec -RowCacheEntry $cacheSnapshot[$Index] -Selected $Selected `
            -NumWidth $NumWidth -DisplayNumber $DisplayNumber -Gap $gapSnapshot `
            -ScrollColumn $scrollColumnSnapshot -MarqueeOffset $offset)
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

        $offset = 0
        if ($getOffset) { $offset = [int](& $getOffset) }
        Invoke-ShellSingleSelectListDrawRow -ScreenRow $ScreenRow -Index $Index `
            -RowCache $cacheSnapshot -ColGap $gapSnapshot -Selected $Selected `
            -NumWidth $NumWidth -DisplayNumber $DisplayNumber -Enabled $Enabled `
            -LayoutLineWidth $contentWidthSnapshot -LayoutStartColumn $contentStartSnapshot `
            -ScrollColumn $scrollColumnSnapshot -MarqueeOffset $offset
    }.GetNewClosure()

    return @{
        GetLabel       = $getLabel
        GetListRowSpec = $getListRowSpec
        DrawListRow    = $drawListRow
    }
}

function Get-ShellSingleSelectListRowCache {
    param(
        [hashtable]$Shell,
        [string]$CacheKey,
        [array]$Rows,
        [hashtable]$ColumnLayout,
        [scriptblock]$OnProgress = $null
    )

    $locale = Get-CurrentLocale
    $layoutKey = if ($ColumnLayout.Preset) {
        "$($ColumnLayout.Preset)|$($ColumnLayout.Widths -join ',')"
    }
    else {
        ($ColumnLayout.Widths -join ',')
    }
    if ($ColumnLayout.ContainsKey('ScrollColumn')) {
        $layoutKey += "|sc$($ColumnLayout.ScrollColumn)"
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

    $built = Build-ShellSingleSelectListRowCache -Rows $Rows -ColumnLayout $ColumnLayout `
        -OnProgress $OnProgress
    if ($Shell) {
        $Shell[$cacheField] = $built.RowCache
        $Shell[$localeField] = $locale
        $Shell[$keyField] = "$layoutKey|$rowsKey"
        $Shell[$gapField] = $built.ColGap
    }

    return $built
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

function Invoke-ShellSingleSelectListRedrawMarqueeRow {
    param(
        [hashtable]$Layout,
        [int]$SelectedIndex,
        [int]$PageIndex,
        [int]$PageSize,
        [int]$ListScrollOffset,
        [array]$RowCache,
        [scriptblock]$GetListRowSpec,
        [int]$NumWidth,
        [scriptblock]$GetItemDisplayNumber,
        [scriptblock]$TestItemEnabled,
        [array]$Items,
        [int]$LayoutLineWidth,
        [int]$LayoutStartColumn
    )

    $pageStart = $PageIndex * $PageSize
    $local = $SelectedIndex - $pageStart - $ListScrollOffset
    $viewport = $Layout.ListViewportHeight
    if ($local -lt 0 -or $local -ge $viewport) { return }

    $displayNumber = & $GetItemDisplayNumber $Items[$SelectedIndex] $SelectedIndex
    $enabled = & $TestItemEnabled $Items[$SelectedIndex] $SelectedIndex
    $spec = & $GetListRowSpec $SelectedIndex $true $NumWidth $displayNumber $enabled
    if (-not $spec) { return }

    Write-ListRowFromSpec -ScreenRow ($Layout.ListStartRow + $local) -Spec $spec `
        -LayoutLineWidth $LayoutLineWidth -LayoutStartColumn $LayoutStartColumn
}
