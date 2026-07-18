# Shell Title 层：页面标题（1 行 cap）；Catalog 层由 Render-ToolkitShellCatalogRow 绘制

function Write-ToolkitShellSectionTitle {
    param(
        [hashtable]$Shell,
        [string]$Title
    )

    if ([string]::IsNullOrWhiteSpace($Title)) { return }
    if ($Shell.Layout.TitleRow -lt 0) { return }

    $barWidth = Get-ToolkitShellLayoutBarInnerWidth -Shell $Shell
    Write-BrandSectionCapLine -Row $Shell.Layout.TitleRow -Title $Title -BrandInnerWidth $barWidth

    Render-ToolkitShellCatalogRow -Shell $Shell
}

function Render-ShellTitle {
    param(
        [hashtable]$Shell,
        [string]$Title
    )

    Write-ToolkitShellSectionTitle -Shell $Shell -Title $Title
}
