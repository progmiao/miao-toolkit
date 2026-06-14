$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$lib = Join-Path $root 'package\core\lib'
. (Join-Path $lib 'bootstrap\Load-Core.ps1') -LibDirectory $lib
Initialize-Paths -BinDirectory (Join-Path $root 'package\bin')

$zhWidth = Measure-ToolkitShellBrandInnerWidthForLocale -Locale 'zh'
$enWidth = Measure-ToolkitShellBrandInnerWidthForLocale -Locale 'en'
$standard = Get-ToolkitShellStandardBrandInnerWidth

if ($standard -ne $zhWidth) {
    throw "standard width should match zh ($zhWidth), got $standard"
}

Initialize-ToolkitShell -Force | Out-Null
$shell = $script:ToolkitShell
if ($shell -isnot [hashtable]) {
    throw "Initialize-ToolkitShell should return hashtable, got $($shell.GetType().FullName)"
}
if ([int]$shell.LayoutBrandInnerWidth -ne $standard) {
    throw "shell LayoutBrandInnerWidth should be $standard, got $($shell.LayoutBrandInnerWidth)"
}

$metrics = Get-ToolkitShellContentMetrics -Shell $shell
if ([int]$metrics.InnerWidth -ne $standard) {
    throw "content metrics inner width should be $standard, got $($metrics.InnerWidth)"
}

$script:CurrentLocale = 'en'
Update-ToolkitShellBrandHeader -Shell $shell
if ([int]$shell.LayoutBrandInnerWidth -ne $standard) {
    throw "after en header refresh width should stay $standard, got $($shell.LayoutBrandInnerWidth)"
}

Update-ToolkitShellViewLayout -Shell $shell -FooterTemplate SystemToolbarOnly -WithSectionTitle
if ([int]$shell.LayoutBrandInnerWidth -ne $standard) {
    throw "SystemToolbarOnly layout should keep width $standard, got $($shell.LayoutBrandInnerWidth)"
}
$lineWidth = Get-BrandSeparatorLineWidth -BrandInnerWidth (Get-ToolkitShellLayoutBarInnerWidth -Shell $shell)
if ($lineWidth -ne ($standard + (Get-BrandSeparatorExtra))) {
    throw "footer line width mismatch: $lineWidth"
}

$cap = Format-BrandSectionCapLine -Title 'Very Long English Section Title Overflow' -BrandInnerWidth $standard
$capInner = $cap.TrimStart()
if ((Get-DisplayWidth $capInner) -gt ($standard + (Get-BrandSeparatorExtra) + 1)) {
    throw 'section cap should truncate to layout width'
}

Write-Host 'test-shell-layout-width: OK'
