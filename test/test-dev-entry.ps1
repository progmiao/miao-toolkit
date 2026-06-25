$ErrorActionPreference = 'Stop'
$env:MIAO_DEV = '1'
$env:MIAO_SKIP_DEPS = '1'
$root = Split-Path $PSScriptRoot -Parent
$lib = Join-Path $root 'package\core\lib'
. (Join-Path $lib 'bootstrap\Load-Core.ps1') -LibDirectory $lib
Initialize-Paths -BinDirectory (Join-Path $root 'package\bin')

Clear-ToolkitInitDirectory
Reset-ToolkitToolsMemoryCache
if (Test-ToolkitInitValid) { throw 'init should be invalid after clear' }
if (-not (Test-MiaoDevMode)) { throw 'MIAO_DEV not active' }

$keys = Get-MiaoI18nKeys
if (-not $keys.Esc) { throw 'I18nKeys missing Esc' }

$tb = New-ShellSystemToolbarConfig -HideBack
if ($tb.Segments.Count -lt 1) { throw 'toolbar segments empty' }

$tools = @(Get-ToolkitTools)
if ($tools.Count -lt 1) { throw 'no tools discovered' }

$menuTools = Get-ToolkitMenuTools -RealTools $tools
$rows = Get-HomeToolListRows -Tools $menuTools
if ($rows.Count -lt 1) { throw 'home rows empty' }

$listLayout = New-ShellListLayout
$columnLayout = Resolve-ShellListLayoutColumnLayout -Layout $listLayout
$normalized = @(Normalize-ShellListRows -Rows $rows -Layout $listLayout)
$built = Build-ShellSingleSelectListRowCache -Rows $normalized -ColumnLayout $columnLayout
$handlers = New-ShellSingleSelectListDrawHandlers -RowCache $built.RowCache -ColGap $built.ColGap
& $handlers['GetLabel'] $rows[0] 0 | Out-Null

Write-Host 'DEV ENTRY OK'
