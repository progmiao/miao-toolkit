# Shell 列表：焦点列滚动（marquee）与单元格渲染

function Resolve-ShellListScrollConfig {
    param([hashtable]$Layout)

    $scrollColumn = -1
    $intervalMs = 300
    if ($Layout) {
        if ($null -ne $Layout.PSObject.Properties['ScrollColumn'] -or $Layout.ContainsKey('ScrollColumn')) {
            $scrollColumn = [int]$Layout.ScrollColumn
        }
        if ($null -ne $Layout.PSObject.Properties['ScrollIntervalMs'] -or $Layout.ContainsKey('ScrollIntervalMs')) {
            $intervalMs = [int]$Layout.ScrollIntervalMs
        }
    }
    if ($intervalMs -lt 100) { $intervalMs = 100 }

    return @{
        ScrollColumn     = $scrollColumn
        ScrollIntervalMs = $intervalMs
    }
}

function Test-ShellListCellTextOverflow {
    param(
        [string]$Text,
        [int]$Width
    )

    if ($Width -le 0) { return $false }
    return (Get-DisplayWidth ([string]$Text)) -gt $Width
}

function Get-ShellListMarqueeMaxOffset {
    param(
        [string]$Text,
        [int]$Width
    )

    if ($Width -le 0) { return 0 }
    $overflow = (Get-DisplayWidth ([string]$Text)) - $Width
    if ($overflow -le 0) { return 0 }
    return $overflow + 2
}

function Format-ShellListTableCellText {
    param(
        [string]$Text,
        [int]$Width,
        [int]$MarqueeOffset = 0,
        [switch]$MarqueeActive
    )

    if ($Width -le 0) { return '' }
    $value = if ($null -eq $Text) { '' } else { [string]$Text }
    if ($MarqueeActive -and (Test-ShellListCellTextOverflow -Text $value -Width $Width)) {
        $scrolled = Skip-DisplayTextColumns -Text $value -SkipWidth $MarqueeOffset
        return Pad-DisplayText -Text $scrolled -TargetWidth $Width
    }
    return Pad-DisplayText (Truncate-DisplayText $value $Width) $Width
}

function Get-ShellListRowCellColor {
    param(
        [int]$ColumnIndex,
        [System.ConsoleColor]$DefaultColor,
        [System.ConsoleColor[]]$CellColors,
        [bool]$Enabled,
        [bool]$Selected
    )

    if (-not $Enabled) {
        return [System.ConsoleColor]::DarkGray
    }
    if ($Selected) {
        return [System.ConsoleColor]::Black
    }
    if ($CellColors -and $ColumnIndex -lt $CellColors.Count) {
        $custom = $CellColors[$ColumnIndex]
        if ($custom) {
            return $custom
        }
    }
    return $DefaultColor
}

function Build-ShellListRowBodyFromCells {
    param(
        [string[]]$RawCells,
        [int[]]$Widths,
        [string]$Gap,
        [System.ConsoleColor]$DefaultLineColor,
        [System.ConsoleColor[]]$CellColors = $null,
        [bool]$Enabled = $true,
        [int]$ScrollColumn = -1,
        [int]$MarqueeOffset = 0,
        [switch]$MarqueeActive,
        [switch]$Selected
    )

    $lineColor = if ($Enabled) { $DefaultLineColor } else { [System.ConsoleColor]::DarkGray }
    $scrollOverflow = New-Object 'bool[]' $Widths.Count
    $formatted = New-Object 'string[]' $Widths.Count
    $segments = New-Object 'System.Collections.Generic.List[object]'

    for ($c = 0; $c -lt $Widths.Count; $c++) {
        $raw = if ($c -lt $RawCells.Count) { [string]$RawCells[$c] } else { '' }
        $width = [int]$Widths[$c]
        $scrollOverflow[$c] = Test-ShellListCellTextOverflow -Text $raw -Width $width
        $useMarquee = $MarqueeActive -and ($c -eq $ScrollColumn) -and $scrollOverflow[$c]
        $formatted[$c] = Format-ShellListTableCellText -Text $raw -Width $width `
            -MarqueeOffset $MarqueeOffset -MarqueeActive:$useMarquee

        if ($c -gt 0) {
            $segments.Add(@{ Text = $Gap; Color = $lineColor })
        }
        $segColor = Get-ShellListRowCellColor -ColumnIndex $c -DefaultColor $lineColor `
            -CellColors $CellColors -Enabled $Enabled -Selected:$Selected
        $segments.Add(@{ Text = $formatted[$c]; Color = $segColor })
    }

    return @{
        BodyPlain      = ($formatted -join $Gap)
        BodySegments   = @($segments.ToArray())
        ScrollOverflow = $scrollOverflow
    }
}

function Test-ShellListRowMarqueeActive {
    param(
        $RowCacheEntry,
        [int]$ScrollColumn,
        [bool]$Selected,
        [switch]$LetterInputMode
    )

    if ($LetterInputMode) { return $false }
    if (-not $Selected) { return $false }
    if ($ScrollColumn -lt 0) { return $false }
    if (-not $RowCacheEntry) { return $false }
    if (-not $RowCacheEntry.PSObject.Properties['ScrollOverflow']) { return $false }
    $overflow = @($RowCacheEntry.ScrollOverflow)
    if ($ScrollColumn -ge $overflow.Count) { return $false }
    return [bool]$overflow[$ScrollColumn]
}

function Invoke-ShellListMenuMarqueeTick {
    param(
        [int]$SelectedIndex,
        [array]$RowCache,
        [hashtable]$ScrollConfig,
        [ref]$MarqueeOffset,
        [ref]$MarqueeLastTick,
        [bool]$LetterInputMode
    )

    if ($LetterInputMode) { return $false }
    if ($SelectedIndex -lt 0 -or $SelectedIndex -ge $RowCache.Count) { return $false }

    $scrollColumn = [int]$ScrollConfig.ScrollColumn
    if ($scrollColumn -lt 0) { return $false }

    $entry = $RowCache[$SelectedIndex]
    if (-not (Test-ShellListRowMarqueeActive -RowCacheEntry $entry -ScrollColumn $scrollColumn `
            -Selected $true)) {
        if ([int]$MarqueeOffset.Value -ne 0) {
            $MarqueeOffset.Value = 0
            return $true
        }
        return $false
    }

    $now = [Environment]::TickCount
    if (($now - [int]$MarqueeLastTick.Value) -lt [int]$ScrollConfig.ScrollIntervalMs) {
        return $false
    }

    $MarqueeLastTick.Value = $now
    $rawCells = @($entry.RawCells)
    $widths = @($entry.Widths)
    $text = if ($scrollColumn -lt $rawCells.Count) { [string]$rawCells[$scrollColumn] } else { '' }
    $width = if ($scrollColumn -lt $widths.Count) { [int]$widths[$scrollColumn] } else { 0 }
    $maxOffset = Get-ShellListMarqueeMaxOffset -Text $text -Width $width
    if ($maxOffset -le 0) {
        $MarqueeOffset.Value = 0
        return $false
    }

    if ([int]$MarqueeOffset.Value -ge $maxOffset) {
        $MarqueeOffset.Value = 0
    }
    else {
        $MarqueeOffset.Value = [int]$MarqueeOffset.Value + 1
    }
    return $true
}

function Read-ShellListMenuKey {
    param([hashtable]$ScrollConfig)

    if ([int]$ScrollConfig.ScrollColumn -lt 0) {
        return [Console]::ReadKey($true)
    }

    if (Test-ConsoleKeyAvailable) {
        return [Console]::ReadKey($true)
    }
    return $null
}
