# Shell 标题区：2 行居中 cap + gap

function Write-ToolkitShellSectionTitle {
    param(
        [hashtable]$Shell,
        [string]$Title
    )

    if ([string]::IsNullOrWhiteSpace($Title)) { return }
    if ($Shell.Layout.SectionTitleRow -lt 0) { return }

    $barWidth = Get-ToolkitShellLayoutBarInnerWidth -Shell $Shell
    Write-BrandSectionCapLine -Row $Shell.Layout.SectionTitleRow -Title $Title -BrandInnerWidth $barWidth

    Render-ToolkitShellContentRow -Shell $Shell
}

function Render-ShellTitle {
    param(
        [hashtable]$Shell,
        [string]$Title
    )

    Write-ToolkitShellSectionTitle -Shell $Shell -Title $Title
}
