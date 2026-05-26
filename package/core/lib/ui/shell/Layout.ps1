# Shell 布局：header / title / content / footer 行号 metrics

function Get-ShellLayoutConstants {
    return @{
        SectionCapRows    = 2
        FooterGapRows     = 1
        HomeFooterBarRows = 2
        SubFooterBarRows  = 1
        HomeDRows         = 3
        SubDRows          = 2
        ListSlotRows      = (Get-MenuPageSize)
    }
}

function Get-ShellBrandRowCount {
    param([hashtable]$Shell = $null)

    if ($Shell -and $Shell.Layout -and $Shell.Layout.ContentStartRow -ge 0) {
        return [int]$Shell.Layout.ContentStartRow
    }

    $header = New-ToolkitMenuHeader -HideSectionTitle
    return (Get-MenuHeaderRowCount -Header $header)
}

function Get-ShellHomeContentRows {
    param(
        [int]$ConsoleHeight = 0,
        [int]$BrandRowCount = 0
    )

    if ($ConsoleHeight -le 0) { $ConsoleHeight = Get-ConsoleLineHeight }
    if ($BrandRowCount -le 0) { $BrandRowCount = (Get-ShellBrandRowCount) }

    $c = Get-ShellLayoutConstants
    $homeNatural = $BrandRowCount + $c.SectionCapRows + $c.ListSlotRows + $c.HomeDRows

    if ($ConsoleHeight -ge $homeNatural) {
        return $c.ListSlotRows
    }

    return [Math]::Max(1, $ConsoleHeight - $BrandRowCount - $c.SectionCapRows - $c.HomeDRows)
}

function Get-ShellViewContentRows {
    param(
        [ValidateSet('MenuSplit', 'DefaultBar')]
        [string]$FooterTemplate,
        [int]$ConsoleHeight = 0,
        [int]$BrandRowCount = 0
    )

    $c = Get-ShellLayoutConstants
    $cHome = Get-ShellHomeContentRows -ConsoleHeight $ConsoleHeight -BrandRowCount $BrandRowCount
    $dRows = if ($FooterTemplate -eq 'MenuSplit') { $c.HomeDRows } else { $c.SubDRows }

    return $cHome + ($c.HomeDRows - $dRows)
}

function Get-ShellLayoutMetrics {
    param(
        [ValidateSet('MenuSplit', 'DefaultBar')]
        [string]$FooterTemplate = 'MenuSplit',
        [int]$ConsoleHeight = 0,
        [hashtable]$Shell = $null
    )

    if ($ConsoleHeight -le 0) { $ConsoleHeight = Get-ConsoleLineHeight }

    $c = Get-ShellLayoutConstants
    $brandRowCount = Get-ShellBrandRowCount -Shell $Shell
    $dRows = if ($FooterTemplate -eq 'MenuSplit') { $c.HomeDRows } else { $c.SubDRows }
    $footerBarRows = if ($FooterTemplate -eq 'MenuSplit') { $c.HomeFooterBarRows } else { $c.SubFooterBarRows }
    $listViewport = Get-ShellViewContentRows -FooterTemplate $FooterTemplate `
        -ConsoleHeight $ConsoleHeight -BrandRowCount $brandRowCount
    $homeNatural = $brandRowCount + $c.SectionCapRows + $c.ListSlotRows + $c.HomeDRows
    $expanded = ($ConsoleHeight -ge $homeNatural)

    $listStart = $brandRowCount + $c.SectionCapRows
    $listEnd = $listStart + $listViewport - 1

    $metrics = @{
        BrandRowCount     = $brandRowCount
        SectionCapRows    = $c.SectionCapRows
        ListSlotRows      = $c.ListSlotRows
        HomeContentRows   = (Get-ShellHomeContentRows -ConsoleHeight $ConsoleHeight -BrandRowCount $brandRowCount)
        ListViewportRows  = $listViewport
        FooterGapRows     = $c.FooterGapRows
        FooterBarRows     = $footerBarRows
        FooterDRows       = $dRows
        HomeNaturalHeight = $homeNatural
        LayoutMode        = if ($expanded) { 'Expanded' } else { 'Compressed' }
        ListStartRow      = $listStart
        ListEndRow        = $listEnd
        SectionTitleRow   = $brandRowCount
        SectionGapRow     = ($brandRowCount + 1)
        GapRow            = -1
        HintRow           = -1
        StatusRow         = -1
        ToolbarRow        = -1
        BottomRow         = -1
    }

    if ($expanded) {
        $metrics.GapRow = $listEnd + 1
        if ($FooterTemplate -eq 'MenuSplit') {
            $metrics.HintRow = $listEnd + 2
            $metrics.StatusRow = $listEnd + 3
            $metrics.ToolbarRow = $metrics.StatusRow
        }
        else {
            $metrics.ToolbarRow = $listEnd + 2
            $metrics.StatusRow = $metrics.ToolbarRow
        }
        $metrics.BottomRow = $metrics.StatusRow
    }
    else {
        $metrics.StatusRow = $ConsoleHeight - 1
        $metrics.ToolbarRow = $ConsoleHeight - 1
        if ($FooterTemplate -eq 'MenuSplit') {
            $metrics.HintRow = $ConsoleHeight - 2
            $metrics.GapRow = $ConsoleHeight - 3
            $metrics.ListEndRow = [Math]::Max($listStart, $ConsoleHeight - 4)
        }
        else {
            $metrics.HintRow = -1
            $metrics.GapRow = $ConsoleHeight - 2
            $metrics.ListEndRow = [Math]::Max($listStart, $ConsoleHeight - 3)
        }
        $metrics.ListViewportRows = [Math]::Max(1, $metrics.ListEndRow - $listStart + 1)
        $metrics.BottomRow = $metrics.StatusRow
    }

    return $metrics
}

function Update-ToolkitShellViewLayout {
    param(
        [hashtable]$Shell,
        [ValidateSet('MenuSplit', 'DefaultBar')]
        [string]$FooterTemplate,
        [switch]$WithSectionTitle
    )

    $layout = $Shell.Layout
    $contentStart = $layout.ContentStartRow
    if ($contentStart -lt 0) {
        $header = New-ToolkitMenuHeader -HideSectionTitle
        $contentStart = Get-MenuHeaderRowCount -Header $header
        $layout['ContentStartRow'] = $contentStart
        $layout['TopRows'] = $contentStart
        if (-not $layout.BrandInnerWidth) {
            $layout['BrandInnerWidth'] = Get-BrandInnerWidth -Header $header
        }
    }

    $metrics = Get-ShellLayoutMetrics -FooterTemplate $FooterTemplate -Shell $Shell
    $c = Get-ShellLayoutConstants

    if ($WithSectionTitle) {
        $layout['SectionTitleRow'] = $metrics.SectionTitleRow
        $layout['SectionGapRow'] = $metrics.SectionGapRow
    }
    else {
        $layout['SectionTitleRow'] = -1
        $layout['SectionGapRow'] = -1
    }

    $layout['ListStartRow'] = $metrics.ListStartRow
    $layout['ListEndRow'] = $metrics.ListEndRow
    $layout['ListViewportHeight'] = $metrics.ListViewportRows
    $layout['GapRow'] = $metrics.GapRow
    $layout['HintRow'] = $metrics.HintRow
    $layout['StatusRow'] = $metrics.StatusRow
    $layout['ToolbarRow'] = $metrics.ToolbarRow
    $layout['BottomRow'] = $metrics.BottomRow
    $layout['BodyEndRow'] = $metrics.ListEndRow

    $layout['LayoutMode'] = $metrics.LayoutMode
    $layout['PinFooterToBottom'] = ($metrics.LayoutMode -eq 'Compressed')
    $layout['FooterGapRows'] = $c.FooterGapRows
    $layout['HideColHeader'] = $true
    $layout['ShellMode'] = $true
    $layout['FooterTemplate'] = $FooterTemplate
    $layout['HomeContentRows'] = $metrics.HomeContentRows
    $layout['ListSlotRows'] = $metrics.ListSlotRows
}

function Get-ToolkitShellLayoutSnapshot {
    param([hashtable]$Layout)

    if (-not $Layout) { return $null }

    return @{
        ListEndRow = $Layout.ListEndRow
        GapRow     = $Layout.GapRow
        HintRow    = $Layout.HintRow
        StatusRow  = $Layout.StatusRow
        ToolbarRow = $Layout.ToolbarRow
    }
}

function Clear-ToolkitShellBelowFooter {
    param([hashtable]$Shell)

    if (-not $Shell -or -not $Shell.Layout) { return }
    if ($Shell.Layout.LayoutMode -eq 'Compressed' -or $Shell.Layout.PinFooterToBottom) {
        return
    }

    $fromRow = $Shell.Layout.BottomRow + 1
    if ($fromRow -lt 0) { return }

    $endRow = Get-ConsoleLineHeight - 1
    for ($row = $fromRow; $row -le $endRow; $row++) {
        Write-FixedLine $row '' -Color DarkGray
    }
}

function Clear-ToolkitShellOrphanRows {
    param(
        [hashtable]$Shell,
        [hashtable]$PreviousLayout
    )

    if (-not $PreviousLayout) { return }

    $layout = $Shell.Layout
    $contentStart = $layout.ContentStartRow
    $newListEnd = $layout.ListEndRow

    $prevListEnd = $PreviousLayout.ListEndRow
    if ($null -ne $prevListEnd -and $prevListEnd -gt $newListEnd) {
        for ($row = $newListEnd + 1; $row -le $prevListEnd; $row++) {
            if ($row -ge $contentStart) {
                Write-FixedLine $row '' -Color DarkGray
            }
        }
    }

    foreach ($rowKey in @('GapRow', 'HintRow', 'StatusRow', 'ToolbarRow')) {
        $prevRow = $PreviousLayout[$rowKey]
        if ($null -eq $prevRow -or $prevRow -lt 0) { continue }

        $newRow = $layout[$rowKey]
        if ($prevRow -ne $newRow) {
            Write-FixedLine $prevRow '' -Color DarkGray
        }
    }
}
