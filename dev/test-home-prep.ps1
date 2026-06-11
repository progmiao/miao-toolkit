$ErrorActionPreference = 'Stop'
$env:MIAO_DEV = '1'
$env:MIAO_SKIP_DEPS = '1'
$root = Split-Path $PSScriptRoot -Parent
$lib = Join-Path $root 'package\core\lib'
. (Join-Path $lib 'bootstrap\Load-Core.ps1') -LibDirectory $lib
Initialize-Paths -BinDirectory (Join-Path $root 'package\bin')

$tools = @(Get-ToolkitTools)
$menuTools = @(Get-ToolkitMenuTools -RealTools $tools)
$rows = @(Get-HomeToolListRows -Tools $menuTools)
$layout = New-ShellListColumnLayout -Preset ToolList
$normalized = @(Normalize-ShellListRows -Rows $rows -ColumnLayout $layout)
$built = Build-ShellSingleSelectListRowCache -Rows $normalized -ColumnLayout $layout
$handlers = New-ShellSingleSelectListDrawHandlers -RowCache $built.RowCache -ColGap $built.ColGap

if (-not $handlers['GetLabel']) { throw 'no GetLabel' }
if (-not $handlers['DrawListRow']) { throw 'no DrawListRow' }
if (-not $handlers['GetListRowSpec']) { throw 'no GetListRowSpec' }

$spec = & $handlers['GetListRowSpec'] 0 $true 2 1 $true
if (-not $spec) { throw 'GetListRowSpec returned null' }
if ([string]::IsNullOrWhiteSpace($spec.Text) -and -not $spec.Segments) { throw 'empty row spec' }

$tb = New-ShellSystemToolbarConfig -HideBack
if ($tb.Segments.Count -lt 1) { throw 'empty toolbar' }

Write-Host "tools=$($menuTools.Count) specText=$($spec.Text.Substring(0, [Math]::Min(20, $spec.Text.Length)))"
Write-Host 'HOME PREP OK'
