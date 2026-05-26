# Shell 标题区：2 行居中 cap + gap

function Write-ToolkitShellSectionTitle {
    param(
        [hashtable]$Shell,
        [string]$Title
    )

    if ([string]::IsNullOrWhiteSpace($Title)) { return }
    if ($Shell.Layout.SectionTitleRow -lt 0) { return }

    $barWidth = if ($Shell.BrandInnerWidth -gt 0) { $Shell.BrandInnerWidth } else { $Shell.Layout.BrandInnerWidth }
    Write-BrandSectionCapLine -Row $Shell.Layout.SectionTitleRow -Title $Title -BrandInnerWidth $barWidth

    if ($Shell.Layout.SectionGapRow -ge 0) {
        Write-FixedLine $Shell.Layout.SectionGapRow '' -Color DarkGray
    }
}

function Render-ShellTitle {
    param(
        [hashtable]$Shell,
        [string]$Title
    )

    Write-ToolkitShellSectionTitle -Shell $Shell -Title $Title
}
