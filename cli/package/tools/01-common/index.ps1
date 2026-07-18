# common tool entry (miao common)

param(
    [hashtable]$ToolkitShell = $null,
    [int]$PageSize = 0,
    [int]$ViewHeight = 0
)

$ErrorActionPreference = 'Stop'
$ToolRoot = $PSScriptRoot

$pathsLib = Join-Path $ToolRoot '..\..\core\lib\config\Paths.ps1'
if (Test-Path $pathsLib) {
    . $pathsLib
    Initialize-Console
    $i18nLib = Join-Path $ToolRoot '..\..\core\lib\config\I18n.ps1'
    $userConfigLib = Join-Path $ToolRoot '..\..\core\lib\config\UserConfig.ps1'
    $binDir = Join-Path $ToolRoot '..\..\bin'
    if (Test-Path $binDir) {
        Initialize-Paths -BinDirectory (Resolve-Path $binDir).Path
    }
    if (Test-Path $userConfigLib) {
        . $userConfigLib
    }
    if (Test-Path $i18nLib) {
        . $i18nLib
    }
}

$paging = Resolve-MenuPagingDefaults -PageSize $PageSize -ViewHeight $ViewHeight
$config = Get-Content (Join-Path $ToolRoot 'index.json') -Raw -Encoding UTF8 | ConvertFrom-Json

$mainScript = Join-Path $ToolRoot 'lib/main.ps1'
$mainParams = @{
    Config       = $config
    ToolRoot     = $ToolRoot
    PageSize     = $paging.PageSize
    ViewHeight   = $paging.ViewHeight
    ToolkitShell = $ToolkitShell
}
if ($ToolkitShell) {
    return (. $mainScript @mainParams)
}

$result = & $mainScript @mainParams
exit $(if ($null -eq $result) { 0 } else { [int]$result })
