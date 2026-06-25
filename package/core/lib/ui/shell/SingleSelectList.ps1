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

        $source = $null
        if ($null -ne $row.PSObject.Properties['Payload']) { $source = $row.Payload }
        elseif ($null -ne $row.PSObject.Properties['Source']) { $source = $row.Source }

        $rowCache[$i] = [pscustomobject]@{
            BodyPlain    = $bodyPlain
            BodySegments = $bodySegments
            LineColor    = $enabledColor
            Enabled      = [bool]$row.Enabled
            Source       = $source
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
    $lineColor = $RowCacheEntry.LineColor

    if ($Selected) {
        $prefix = " $mark $num$Gap"
        return @{
            Text       = $prefix + $RowCacheEntry.BodyPlain
            Foreground = [System.ConsoleColor]::Black
            Background = [System.ConsoleColor]::Cyan
        }
    }

    # 与多选 checkSeg 一致：未选中不加前导空格，选中时 " $mark" 才插入 > 并右移内容
    $markSeg = @{ Text = "$mark "; Color = $lineColor }
    $keySeg = @{ Text = "$num$Gap"; Color = $lineColor }
    $bodySegs = @()
    if ($null -ne $RowCacheEntry.BodySegments) {
        $bodySegs = @($RowCacheEntry.BodySegments)
    }

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
    if ($Selected) {
        $region = Resolve-ConsoleContentHighlightRegion -Row $ScreenRow `
            -LayoutStartColumn $LayoutStartColumn -LayoutLineWidth $LayoutLineWidth
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
        [int]$LayoutLineWidth = 0,
        [int]$LayoutStartColumn = 0
    )

    if ($Index -lt 0 -or $Index -ge $RowCache.Count) { return }
    $part = $RowCache[$Index]
    if (-not $part) { return }

    $spec = Build-ShellSingleSelectListRowSpec -RowCacheEntry $part -Selected $Selected `
        -NumWidth $NumWidth -DisplayNumber $DisplayNumber -Gap $ColGap
    Write-ShellSingleSelectListRow -ScreenRow $ScreenRow -DisplayNumber $DisplayNumber `
        -NumWidth $NumWidth -Gap $ColGap -Selected $Selected -Enabled $Enabled -RowSpec $spec `
        -LayoutLineWidth $LayoutLineWidth -LayoutStartColumn $LayoutStartColumn
}

function New-ShellSingleSelectListDrawHandlers {
    param(
        [array]$RowCache,
        [string]$ColGap,
        [int]$LayoutLineWidth = 0,
        [int]$LayoutStartColumn = 0
    )

    $cacheSnapshot = @($RowCache)
    $gapSnapshot = [string]$ColGap
    $contentWidthSnapshot = [int]$LayoutLineWidth
    $contentStartSnapshot = [int]$LayoutStartColumn

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
            -LayoutLineWidth $contentWidthSnapshot -LayoutStartColumn $contentStartSnapshot
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
