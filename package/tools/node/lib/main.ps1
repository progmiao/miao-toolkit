# node — 一级功能菜单（单选列表 + 系统工具栏）

param(
    [Parameter(Mandatory = $true)]
    $Config,

    [Parameter(Mandatory = $true)]
    [string]$ToolRoot,

    [hashtable]$ToolkitShell = $null,

    [int]$PageSize = 0,
    [int]$ViewHeight = 0,
    [switch]$LtsOnly
)

$ErrorActionPreference = 'Stop'

$coreLib = Join-Path $ToolRoot '..\..\core\lib'

# 嵌套脚本里 $script:MiaoCoreLoaded 不可见；用父作用域/全局已加载的 core 判断
$coreReady = $false
if ($global:MiaoCoreLoaded) { $coreReady = $true }
elseif (Get-Command Import-MiaoModule -CommandType Function -ErrorAction SilentlyContinue) { $coreReady = $true }

if (-not $coreReady) {
    . (Join-Path $coreLib 'config\Paths.ps1')
    . (Join-Path $coreLib 'config\ListLayout.ps1')
    . (Join-Path $coreLib 'config\UserConfig.ps1')
    . (Join-Path $coreLib 'config\I18n.ps1')
    . (Join-Path $coreLib 'domain\Discover-Tools.ps1')
    . (Join-Path $coreLib 'ui\console\Console-Menu.ps1')
    . (Join-Path $coreLib 'ui\shell\Nav.ps1')
    . (Join-Path $coreLib 'ui\shell\SystemToolbar.ps1')
    . (Join-Path $coreLib 'ui\shell\SingleSelectList.ps1')
    . (Join-Path $coreLib 'ui\shell\MultiSelectList.ps1')
    . (Join-Path $coreLib 'ui\shell\Draw.ps1')
    . (Join-Path $coreLib 'ui\shell\Header.ps1')
    . (Join-Path $coreLib 'ui\shell\Title.ps1')
    . (Join-Path $coreLib 'ui\shell\Exit.ps1')
    . (Join-Path $coreLib 'ui\shell\Footer.ps1')
    . (Join-Path $coreLib 'ui\shell\Layout.ps1')
    foreach ($rel in @(
            'domain\Check-Update.ps1'
            'domain\Ensure-ToolDeps.ps1'
            'config\Deps-State.ps1'
            'domain\Invoke-ToolDepPackage.ps1'
            'domain\Invoke-ToolkitDepOperation.ps1'
            'ui\shell\DepOperationView.ps1'
            'domain\Invoke-ToolkitDeps.ps1'
        )) {
        . (Join-Path $coreLib $rel)
    }
}

Initialize-PathsFromToolRoot -ToolRoot $ToolRoot

$paging = Resolve-MenuPagingDefaults -PageSize $PageSize -ViewHeight $ViewHeight
$PageSize = $paging.PageSize
$ViewHeight = $paging.ViewHeight

if (-not $ToolkitShell) {
    $ToolkitShell = Initialize-ToolkitShell
}

Sync-MiaoLocaleFromShell -Shell $ToolkitShell
$tool = Get-ToolFromDirectory -ToolRoot $ToolRoot

function Get-NodeToolSectionTitle {
    return (Get-ToolSectionTitle -Tool $tool)
}

function Resolve-NodeActionScript {
    param([string]$RelativePath)
    Join-Path $ToolRoot ($RelativePath -replace '/', [IO.Path]::DirectorySeparatorChar)
}

function Invoke-NodeAction {
    param($Action)

    $scriptPath = Resolve-NodeActionScript $Action.script
    if (-not (Test-Path $scriptPath)) {
        Write-MessageBlock -Title '错误' -Lines @("缺少脚本: $($Action.script)") -TitleColor Red
        return 1
    }

    $result = . $scriptPath -ToolkitShell $ToolkitShell -Action $Action -PageSize $PageSize `
        -ViewHeight $ViewHeight -LtsOnly:$LtsOnly
    if (Test-ShellNavMarker $result 'quit') {
        return $result
    }
    if (Test-ShellNavMarker $result 'sys') {
        return $result
    }
    if (Test-ShellNavMarker $result 'help') {
        return $result
    }
    if ($null -ne $result -and $result -is [int]) {
        return $result
    }
    return 0
}

$toolbar = New-ShellSystemToolbarConfig
$sectionTitle = Get-NodeToolSectionTitle
$dependencyUpdateAvailable = $false

while ($true) {
    Sync-MiaoLocaleFromShell -Shell $ToolkitShell
    $tool = Get-ToolFromDirectory -ToolRoot $ToolRoot

    $probeChanged = Update-ToolDependencyMenuProbe -Tool $tool -Shell $ToolkitShell `
        -UpdateMenuAvailable ([ref]$dependencyUpdateAvailable)

    $menuItems = @(Get-ToolMenuItems -BusinessActions @($Config.actions) -Tool $tool `
        -DependencyUpdateAvailable:$dependencyUpdateAvailable)

    $currentLocale = Get-CurrentLocale
    if ($probeChanged -or -not $ToolkitShell.HeaderLocale -or $ToolkitShell.HeaderLocale -ne $currentLocale) {
        Clear-ShellSingleSelectListCache -Shell $ToolkitShell -CacheKey 'Node'
        $sectionTitle = Get-NodeToolSectionTitle
    }

    $picked = Invoke-ShellSingleSelectList -Shell $ToolkitShell `
        -SectionTitle $sectionTitle `
        -Rows (ConvertTo-ToolMenuListRows -ToolRoot $ToolRoot -MenuItems $menuItems) `
        -CacheKey 'Node' `
        -ColumnLayout (New-ShellListColumnLayout -Preset ToolList) `
        -ToolbarConfig $toolbar

    if (-not $picked) {
        return (Get-ShellNavMarker -Action 'back')
    }
    if (Test-ShellNavMarker $picked) {
        return $picked
    }

    if (Test-ToolDependencyMenuAction $picked) {
        $depResult = Invoke-ToolDependencyMenuAction -Tool $tool -Action $picked -Shell $ToolkitShell
        if (Test-ShellNavMarker $depResult) {
            return $depResult
        }
        Clear-DepsStateCache
        Reset-ToolDependencyUpgradeProbe -Tool $tool -Shell $ToolkitShell
        $dependencyUpdateAvailable = $false
        Clear-ShellSingleSelectListCache -Shell $ToolkitShell -CacheKey 'Node'
        continue
    }

    $code = Invoke-NodeAction $picked
    if (Test-ShellNavMarker $code) {
        return $code
    }
    if ($code -ne 0) {
        Start-Sleep -Milliseconds 1200
    }
}
