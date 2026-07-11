# yarn 工具 — 固定入口（miao yarn → 本文件，参数原样透传）

param(
    [Alias('i')]
    [switch]$Install,

    [Alias('p')]
    [switch]$PinProject,

    [Alias('d')]
    [switch]$SetDefault,

    [Alias('u')]
    [switch]$Uninstall,

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
$PageSize = $paging.PageSize
$ViewHeight = $paging.ViewHeight

function Get-ToolConfig {
    $path = Join-Path $ToolRoot 'index.json'
    Get-Content -Raw -Path $path -Encoding UTF8 | ConvertFrom-Json
}

function Resolve-ActionScript {
    param([string]$RelativePath)
    Join-Path $ToolRoot ($RelativePath -replace '/', [IO.Path]::DirectorySeparatorChar)
}

$config = Get-ToolConfig
$actions = @($config.actions)

$mode = $null
if ($Install.IsPresent) { $mode = 'Install' }
elseif ($PinProject.IsPresent) { $mode = 'Pin' }
elseif ($SetDefault.IsPresent) { $mode = 'Default' }
elseif ($Uninstall.IsPresent) { $mode = 'Uninstall' }

if ($mode) {
    $action = $actions | Where-Object { $_.param.switch -eq $mode } | Select-Object -First 1
    if (-not $action) {
        Write-Host "未找到与 -$mode 对应的功能配置。" -ForegroundColor Red
        exit 1
    }
    if (-not $action.enabled) {
        $label = [string]$action.command
        if (Get-Command Resolve-ToolI18nLabel -ErrorAction SilentlyContinue) {
            $label = Resolve-ToolI18nLabel -ToolRoot $ToolRoot -Key ([string]$action.name) -Fallback $label
        }
        Write-Host "功能「$label」尚未开放。" -ForegroundColor Yellow
        exit 1
    }
    $scriptPath = Resolve-ActionScript $action.script
    & $scriptPath -ToolkitShell $ToolkitShell -Action $action -PageSize $PageSize `
        -ViewHeight $ViewHeight
    exit $LASTEXITCODE
}

$mainScript = Join-Path $ToolRoot 'lib/main.ps1'
$mainParams = @{
    Config     = $config
    ToolRoot   = $ToolRoot
    PageSize   = $PageSize
    ViewHeight = $ViewHeight
}
$mainParams['ToolkitShell'] = $ToolkitShell
if ($ToolkitShell) {
    return (. $mainScript @mainParams)
}

$result = & $mainScript @mainParams
exit $(if ($null -eq $result) { 0 } else { [int]$result })
