# node 工具 — 固定入口（miao node → 本文件，参数原样透传）

param(
    [Alias('i')]
    [switch]$Install,

    [Alias('p')]
    [switch]$PinProject,

    [Alias('d')]
    [switch]$SetDefault,

    [int]$PageSize = 0,
    [int]$ViewHeight = 0,
    [switch]$LtsOnly
)

$ErrorActionPreference = 'Stop'
$ToolRoot = $PSScriptRoot

# 独立运行时初始化控制台 UTF-8（经 miao.ps1 进入时由 Paths.ps1 已处理）
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

if ($mode) {
    $action = $actions | Where-Object { $_.param.switch -eq $mode } | Select-Object -First 1
    if (-not $action) {
        Write-Host "未找到与 -$mode 对应的功能配置。" -ForegroundColor Red
        exit 1
    }
    if (-not $action.enabled) {
        Write-Host "功能「$($action.label)」尚未开放。" -ForegroundColor Yellow
        exit 1
    }
    $scriptPath = Resolve-ActionScript $action.script
    & $scriptPath @PSBoundParameters
    exit $LASTEXITCODE
}

$mainScript = Join-Path $ToolRoot 'lib/main.ps1'
& $mainScript -Config $config -ToolRoot $ToolRoot @PSBoundParameters
