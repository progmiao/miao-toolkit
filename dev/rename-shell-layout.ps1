# One-off: align shell layout naming with docs/LAYOUT.md
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

$replacements = @(
    @('Sync-ToolkitShellContentMetrics', 'Sync-ToolkitShellLayoutLineMetrics'),
    @('Get-ToolkitShellContentMetrics', 'Get-ToolkitShellLayoutLineMetrics'),
    @('Get-ToolkitShellContentLineWidth', 'Get-ToolkitShellLayoutLineWidth'),
    @('Render-ToolkitShellContentRow', 'Render-ToolkitShellCatalogRow'),
    @('Set-ToolkitShellBodyContentLine', 'Set-ToolkitShellBodyCatalogLine'),
    @('Get-ToolkitShellBodyContentLine', 'Get-ToolkitShellBodyCatalogLine'),
    @('Write-ToolkitShellContentRow', 'Write-ToolkitShellCatalogRow'),
    @('Get-ToolkitShellContentRow', 'Get-ToolkitShellCatalogRow'),
    @('Get-ToolkitDepContentRowWriteLimit', 'Get-ToolkitDepCatalogRowWriteLimit'),
    @('Complete-ToolkitDepContentRowPadding', 'Complete-ToolkitDepCatalogRowPadding'),
    @('Get-ShellHomeContentRows', 'Get-ShellHomeBodyRows'),
    @('Get-ShellViewContentRows', 'Get-ShellViewBodyRows'),
    @('Draw-BrandedContentLines', 'Draw-BrandedBodyLines'),
    @('New-BrandedContentLine', 'New-BrandedBodyLine'),
    @('Format-NodePinContentLineMessage', 'Format-NodePinCatalogLineMessage'),
    @('Format-PnpmPinContentLineMessage', 'Format-PnpmPinCatalogLineMessage'),
    @('Format-YarnPinContentLineMessage', 'Format-YarnPinCatalogLineMessage'),
    @('InitialContentLine', 'InitialCatalogLine'),
    @('BodyContentLine', 'BodyCatalogLine'),
    @('ContentMetrics', 'LayoutLineMetrics'),
    @('ContentLineWidth', 'LayoutLineWidth'),
    @('ContentStartColumn', 'LayoutStartColumn'),
    @('HomeContentRows', 'HomeBodyRows'),
    @('SectionCapRows', 'TitleCatalogRows'),
    @('SectionTitleRow', 'TitleRow'),
    @('SectionGapRow', 'CatalogRow'),
    @('FooterGapRows', 'MessageRows'),
    @('Format-ToolkitShellContentSeparator', 'Format-ToolkitShellLayoutSeparator'),
    @('ui\shell\ContentRow.ps1', 'ui\shell\CatalogRow.ps1'),
    @('ContentRow.ps1', 'CatalogRow.ps1')
)

$files = Get-ChildItem -Path $root -Recurse -Include *.ps1,*.md,*.mdc -File |
    Where-Object { $_.FullName -notmatch '\\\.git\\' -and $_.Name -ne 'rename-shell-layout.ps1' }

foreach ($file in $files) {
    $text = [IO.File]::ReadAllText($file.FullName)
    $orig = $text
    foreach ($pair in $replacements) {
        $text = $text.Replace($pair[0], $pair[1])
    }
    if ($text -ne $orig) {
        [IO.File]::WriteAllText($file.FullName, $text, (New-Object System.Text.UTF8Encoding $true))
        Write-Output $file.FullName.Replace("$root\", '')
    }
}
