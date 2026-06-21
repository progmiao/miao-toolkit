# Shell 布局：header / title / content / footer 行号 metrics

function Get-ToolkitShellStandardBrandInnerWidth {
    if ($global:ToolkitShellStandardBrandInnerWidth -gt 0) {
        $script:ToolkitShellStandardBrandInnerWidth = [int]$global:ToolkitShellStandardBrandInnerWidth
        return [int]$global:ToolkitShellStandardBrandInnerWidth
    }

    if ($script:ToolkitShellStandardBrandInnerWidth -gt 0) {
        $global:ToolkitShellStandardBrandInnerWidth = [int]$script:ToolkitShellStandardBrandInnerWidth
        return [int]$script:ToolkitShellStandardBrandInnerWidth
    }

    $width = 0
    if (Get-Command Test-ToolkitSessionInitReady -ErrorAction SilentlyContinue) {
        if (Test-ToolkitSessionInitReady) {
            $brand = $null
            if ($script:ToolkitHomeBrandSnapshot -and `
                [string]$script:ToolkitHomeBrandSnapshotLocale -eq 'zh') {
                $brand = $script:ToolkitHomeBrandSnapshot
            }
            if (-not $brand) {
                $brand = Get-ToolkitBrandSnapshot -Locale 'zh'
            }
            if ($brand -and [int]$brand.brandInnerWidth -gt 0) {
                $width = [int]$brand.brandInnerWidth
            }
        }
    }

    if ($width -le 0) {
        $width = Measure-ToolkitShellBrandInnerWidthForLocale -Locale 'zh'
    }

    $script:ToolkitShellStandardBrandInnerWidth = [int]$width
    $global:ToolkitShellStandardBrandInnerWidth = [int]$width
    return [int]$width
}

function Measure-ToolkitShellBrandInnerWidthForLocale {
    param([string]$Locale = 'zh')

    $prev = Get-CurrentLocale
    try {
        $script:CurrentLocale = $Locale
        return (Get-BrandInnerWidth -Header (New-ToolkitMenuHeader -HideSectionTitle))
    }
    finally {
        $script:CurrentLocale = $prev
    }
}

function Apply-ToolkitShellLayoutBrandInnerWidth {
    param(
        [hashtable]$Shell,
        [int]$Width = 0
    )

    if (-not $Shell) { return }

    if ($Width -le 0) {
        $Width = Get-ToolkitShellStandardBrandInnerWidth
    }

    $Shell['LayoutBrandInnerWidth'] = $Width
    $Shell['BrandInnerWidth'] = $Width
    if ($Shell.Layout) {
        $Shell.Layout['BrandInnerWidth'] = $Width
    }
    $null = Sync-ToolkitShellContentMetrics -Shell $Shell
}

function Get-ToolkitShellLayoutBarInnerWidth {
    param([hashtable]$Shell = $null)

    if ($Shell -and [int]$Shell.LayoutBrandInnerWidth -gt 0) {
        return [int]$Shell.LayoutBrandInnerWidth
    }
    if ($Shell -and [int]$Shell.BrandInnerWidth -gt 0) {
        return [int]$Shell.BrandInnerWidth
    }
    if ($Shell -and $Shell.Layout -and [int]$Shell.Layout.BrandInnerWidth -gt 0) {
        return [int]$Shell.Layout.BrandInnerWidth
    }

    return Get-ToolkitShellStandardBrandInnerWidth
}

function Ensure-ToolkitShellLayoutBrandInnerWidth {
    param([hashtable]$Shell)

    if (-not $Shell) { return 0 }

    $width = Get-ToolkitShellLayoutBarInnerWidth -Shell $Shell
    if ([int]$Shell.LayoutBrandInnerWidth -ne $width) {
        $null = Apply-ToolkitShellLayoutBrandInnerWidth -Shell $Shell -Width $width
    }
    return $width
}

function Get-ToolkitShellContentMetrics {
    param(
        [hashtable]$Shell = $null,
        [int]$BrandInnerWidth = 0
    )

    $inner = [int]$BrandInnerWidth
    if ($inner -le 0 -and $Shell) {
        if ([int]$Shell.LayoutBrandInnerWidth -gt 0) {
            $inner = [int]$Shell.LayoutBrandInnerWidth
        }
        elseif ($Shell.BrandInnerWidth -gt 0) {
            $inner = [int]$Shell.BrandInnerWidth
        }
        elseif ($Shell.Layout -and $Shell.Layout.BrandInnerWidth -gt 0) {
            $inner = [int]$Shell.Layout.BrandInnerWidth
        }
    }
    if ($inner -le 0) {
        $inner = Get-ToolkitShellStandardBrandInnerWidth
    }

    $lineWidth = Get-BrandSeparatorLineWidth -BrandInnerWidth $inner
    return @{
        StartColumn = 1
        InnerWidth  = $inner
        LineWidth   = $lineWidth
        EndColumn   = 1 + $lineWidth
    }
}

function Get-ToolkitShellContentLineWidth {
    param(
        [hashtable]$Shell = $null,
        [int]$BrandInnerWidth = 0
    )

    if ($Shell -and $Shell.ContentMetrics -and [int]$Shell.ContentMetrics.EndColumn -gt 0) {
        return [int]$Shell.ContentMetrics.EndColumn
    }

    if ($BrandInnerWidth -le 0 -and $Shell) {
        if ([int]$Shell.LayoutBrandInnerWidth -gt 0) {
            $BrandInnerWidth = [int]$Shell.LayoutBrandInnerWidth
        }
        elseif ([int]$Shell.BrandInnerWidth -gt 0) {
            $BrandInnerWidth = [int]$Shell.BrandInnerWidth
        }
        elseif ($Shell.Layout -and [int]$Shell.Layout.BrandInnerWidth -gt 0) {
            $BrandInnerWidth = [int]$Shell.Layout.BrandInnerWidth
        }
    }

    if ($BrandInnerWidth -le 0) { return 0 }
    return 1 + (Get-BrandSeparatorLineWidth -BrandInnerWidth $BrandInnerWidth)
}

function Sync-ToolkitShellContentMetrics {
    param([hashtable]$Shell)

    if (-not $Shell) { return $null }

    $metrics = Get-ToolkitShellContentMetrics -Shell $Shell
    $Shell['ContentMetrics'] = $metrics
    if ($Shell.Layout) {
        $Shell.Layout['ContentMetrics'] = $metrics
        $Shell.Layout['BrandInnerWidth'] = $metrics.InnerWidth
        $Shell.Layout['ContentStartColumn'] = $metrics.StartColumn
        $Shell.Layout['ContentLineWidth'] = $metrics.EndColumn
    }
    $Shell['BrandInnerWidth'] = $metrics.InnerWidth
    return $metrics
}

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
        [ValidateSet('ListWithToolbar', 'SystemToolbarOnly')]
        [string]$FooterTemplate,
        [int]$ConsoleHeight = 0,
        [int]$BrandRowCount = 0
    )

    $c = Get-ShellLayoutConstants
    $cHome = Get-ShellHomeContentRows -ConsoleHeight $ConsoleHeight -BrandRowCount $BrandRowCount
    $dRows = if ($FooterTemplate -eq 'ListWithToolbar') { $c.HomeDRows } else { $c.SubDRows }

    return $cHome + ($c.HomeDRows - $dRows)
}

function Get-ShellLayoutMetrics {
    param(
        [ValidateSet('ListWithToolbar', 'SystemToolbarOnly')]
        [string]$FooterTemplate = 'ListWithToolbar',
        [int]$ConsoleHeight = 0,
        [hashtable]$Shell = $null
    )

    if ($ConsoleHeight -le 0) { $ConsoleHeight = Get-ConsoleLineHeight }

    $c = Get-ShellLayoutConstants
    $brandRowCount = Get-ShellBrandRowCount -Shell $Shell
    $dRows = if ($FooterTemplate -eq 'ListWithToolbar') { $c.HomeDRows } else { $c.SubDRows }
    $footerBarRows = if ($FooterTemplate -eq 'ListWithToolbar') { $c.HomeFooterBarRows } else { $c.SubFooterBarRows }
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
        if ($FooterTemplate -eq 'ListWithToolbar') {
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
        if ($FooterTemplate -eq 'ListWithToolbar') {
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
        [ValidateSet('ListWithToolbar', 'SystemToolbarOnly')]
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
    }

    $null = Ensure-ToolkitShellLayoutBrandInnerWidth -Shell $Shell
    $null = Sync-ToolkitShellContentMetrics -Shell $Shell

    $metrics = Get-ShellLayoutMetrics -FooterTemplate $FooterTemplate -Shell $Shell
    $c = Get-ShellLayoutConstants

    if ($WithSectionTitle) {
        $layout['SectionTitleRow'] = $metrics.SectionTitleRow
        $layout['SectionGapRow'] = $metrics.SectionGapRow
        $layout['ContentRow'] = $metrics.SectionGapRow
    }
    else {
        $layout['SectionTitleRow'] = -1
        $layout['SectionGapRow'] = -1
        $layout['ContentRow'] = -1
    }

    $layout['ListStartRow'] = $metrics.ListStartRow
    $layout['ListEndRow'] = $metrics.ListEndRow
    $layout['ListViewportHeight'] = $metrics.ListViewportRows
    $layout['GapRow'] = $metrics.GapRow
    $layout['MessageRow'] = $metrics.GapRow
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
        ContentRow = $Layout.ContentRow
        GapRow     = $Layout.GapRow
        MessageRow = $Layout.MessageRow
        HintRow    = $Layout.HintRow
        StatusRow  = $Layout.StatusRow
        ToolbarRow = $Layout.ToolbarRow
    }
}

function Clear-ToolkitShellBelowFooter {
    param([hashtable]$Shell)

    if (-not $Shell -or -not $Shell.Layout) { return }
    if ($Shell.SuppressBelowFooterClear) { return }
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

    foreach ($rowKey in @('ContentRow', 'GapRow', 'MessageRow', 'HintRow', 'StatusRow', 'ToolbarRow')) {
        $prevRow = $PreviousLayout[$rowKey]
        if ($null -eq $prevRow -or $prevRow -lt 0) { continue }

        $newRow = $layout[$rowKey]
        if ($prevRow -ne $newRow) {
            Write-FixedLine $prevRow '' -Color DarkGray
        }
    }
}
