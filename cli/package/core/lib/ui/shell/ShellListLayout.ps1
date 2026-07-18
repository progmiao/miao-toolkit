# Shell 列表：列宽解析（单选/多选共用）

function Add-ShellListLayoutScrollFields {
    param(
        [hashtable]$Target,
        [hashtable]$Source
    )

    if ($Source -and $Source.ContainsKey('ScrollColumn')) {
        $Target['ScrollColumn'] = [int]$Source.ScrollColumn
    }
    if ($Source -and $Source.ContainsKey('ScrollIntervalMs')) {
        $Target['ScrollIntervalMs'] = [int]$Source.ScrollIntervalMs
    }
    return $Target
}

function Resolve-ShellListLayout {
    param(
        [hashtable]$Shell,
        [hashtable]$Layout,
        [int]$NumWidth = 2,
        [ValidateSet('Single', 'Multi')]
        [string]$Mode = 'Single',
        [ValidateSet('Number', 'SearchKey')]
        [string]$KeyColumn = 'Number',
        [int]$SearchKeyWidth = 0,
        [switch]$HideNumberColumn
    )

    if (-not $Layout) {
        $Layout = New-ShellListLayout
    }

    $widths = @([int[]]$Layout.Widths)
    if ($widths.Count -lt 1) {
        throw 'Resolve-ShellListLayout requires at least one column width.'
    }

    $metrics = Get-ToolkitShellLayoutLineMetrics -Shell $Shell
    $maxRowWidth = [int]$metrics.EndColumn
    $colGap = Get-MenuColumnGap
    $keyWidth = if ($Mode -eq 'Multi' -and $HideNumberColumn) {
        0
    }
    elseif ($KeyColumn -eq 'SearchKey') {
        if ($SearchKeyWidth -gt 0) { $SearchKeyWidth } else { Get-ShellMultiSelectSearchKeyWidth }
    }
    else {
        [Math]::Max(1, [int]$NumWidth)
    }

    $prefixReserve = Get-ShellListRowPrefixReserve -Mode $Mode -KeyWidth $keyWidth `
        -HideNumberColumn:$HideNumberColumn

    if ($Layout.Preset -eq 'HalfSplit' -and $widths.Count -eq 2) {
        $bodyW = $maxRowWidth - $prefixReserve - $colGap
        $widths[0] = [Math]::Max(6, [Math]::Floor($bodyW / 2))
        $widths[1] = [Math]::Max(6, $bodyW - [int]$widths[0])
        return (Add-ShellListLayoutScrollFields -Target @{
            Widths  = @($widths)
            Headers = if ($Layout.Headers) { @($Layout.Headers) } else { @() }
        } -Source $Layout)
    }

    $flexIndex = -1
    for ($i = 0; $i -lt $widths.Count; $i++) {
        if ([int]$widths[$i] -le 0) {
            $flexIndex = $i
            break
        }
    }

    if ($flexIndex -ge 0) {
        $fixedW = 0
        for ($i = 0; $i -lt $widths.Count; $i++) {
            if ($i -ne $flexIndex) {
                $fixedW += [int]$widths[$i]
                if ($i -lt ($widths.Count - 1)) { $fixedW += $colGap }
            }
        }
        $widths[$flexIndex] = [Math]::Max(6, $maxRowWidth - $prefixReserve - $fixedW)
    }

    return (Add-ShellListLayoutScrollFields -Target @{
        Widths  = @($widths)
        Headers = if ($Layout.Headers) { @($Layout.Headers) } else { @() }
    } -Source $Layout)
}
