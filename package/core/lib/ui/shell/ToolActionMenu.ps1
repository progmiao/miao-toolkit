# 工具一级功能菜单：单选列表 + 依赖项分发 + 业务 action 调度

function Import-ToolActionMenuCore {
    param([string]$CoreLib)

    if (Get-Command Get-ToolMenuItems -CommandType Function -ErrorAction SilentlyContinue) {
        return
    }

    if (Get-Command Import-MiaoToolDepsModule -CommandType Function -ErrorAction SilentlyContinue) {
        Import-MiaoToolDepsModule
        return
    }

    . (Join-Path $CoreLib 'config\Paths.ps1')
    . (Join-Path $CoreLib 'config\ListLayout.ps1')
    . (Join-Path $CoreLib 'config\UserConfig.ps1')
    . (Join-Path $CoreLib 'config\I18n.ps1')
    . (Join-Path $CoreLib 'domain\Discover-Tools.ps1')
    . (Join-Path $CoreLib 'ui\console\Console-Menu.ps1')
    . (Join-Path $CoreLib 'ui\shell\Nav.ps1')
    . (Join-Path $CoreLib 'ui\shell\SystemToolbar.ps1')
    . (Join-Path $CoreLib 'ui\shell\SingleSelectList.ps1')
    . (Join-Path $CoreLib 'ui\shell\MultiSelectList.ps1')
    . (Join-Path $CoreLib 'ui\shell\Draw.ps1')
    . (Join-Path $CoreLib 'ui\shell\Header.ps1')
    . (Join-Path $CoreLib 'ui\shell\Title.ps1')
    . (Join-Path $CoreLib 'ui\shell\CatalogRow.ps1')
    . (Join-Path $CoreLib 'ui\shell\Confirm.ps1')
    . (Join-Path $CoreLib 'ui\shell\Exit.ps1')
    . (Join-Path $CoreLib 'ui\shell\Footer.ps1')
    . (Join-Path $CoreLib 'ui\shell\Layout.ps1')
    foreach ($rel in @(
            'domain\Check-Update.ps1'
            'domain\Ensure-ToolDeps.ps1'
            'config\Deps-State.ps1'
            'domain\Invoke-ToolDepPackage.ps1'
            'domain\Invoke-ToolkitDepOperation.ps1'
            'ui\shell\DepOperationView.ps1'
            'domain\Invoke-ToolkitDeps.ps1'
        )) {
        . (Join-Path $CoreLib $rel)
    }
}

function Resolve-ToolActionMenuCacheKey {
    param($Tool)

    if ($Tool.command) { return [string]$Tool.command }
    if ($Tool.id) { return [string]$Tool.id }
    return 'tool'
}

function Invoke-ToolBusinessAction {
    param(
        [Parameter(Mandatory)]
        [string]$ToolRoot,
        [Parameter(Mandatory)]
        $Action,
        [hashtable]$ToolkitShell = $null,
        [hashtable]$ActionScriptParams = @{}
    )

    $scriptPath = Join-Path $ToolRoot ($Action.script -replace '/', [IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path $scriptPath)) {
        Write-MessageBlock -Title '错误' -Lines @("缺少脚本: $($Action.script)") -TitleColor Red
        return 1
    }

    $invokeParams = @{
        ToolkitShell = $ToolkitShell
        Action       = $Action
    }
    foreach ($key in @($ActionScriptParams.Keys)) {
        $invokeParams[$key] = $ActionScriptParams[$key]
    }

    $result = . $scriptPath @invokeParams
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

function Invoke-ToolActionMenu {
    param(
        [Parameter(Mandatory)]
        $Config,
        [Parameter(Mandatory)]
        [string]$ToolRoot,
        [hashtable]$ToolkitShell = $null,
        [int]$PageSize = 0,
        [int]$ViewHeight = 0,
        [hashtable]$ActionScriptParams = @{}
    )

    $coreLib = Join-Path $ToolRoot '..\..\core\lib'
    Import-ToolActionMenuCore -CoreLib $coreLib
    Initialize-PathsFromToolRoot -ToolRoot $ToolRoot

    $paging = Resolve-MenuPagingDefaults -PageSize $PageSize -ViewHeight $ViewHeight
    $PageSize = $paging.PageSize
    $ViewHeight = $paging.ViewHeight

    if (-not $ToolkitShell) {
        $ToolkitShell = Initialize-ToolkitShell
    }

    Sync-MiaoLocaleFromShell -Shell $ToolkitShell
    $tool = Get-ToolFromDirectory -ToolRoot $ToolRoot

    $mergedActionParams = @{
        PageSize   = $PageSize
        ViewHeight = $ViewHeight
    }
    foreach ($key in @($ActionScriptParams.Keys)) {
        $mergedActionParams[$key] = $ActionScriptParams[$key]
    }

    $toolbar = New-ShellSystemToolbarConfig
    $listCacheKey = Resolve-ToolActionMenuCacheKey -Tool $tool
    $sectionTitle = Get-ToolSectionTitle -Tool $tool
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
            Clear-ShellSingleSelectListCache -Shell $ToolkitShell -CacheKey $listCacheKey
            $sectionTitle = Get-ToolSectionTitle -Tool $tool
        }

        $picked = Invoke-ShellSingleSelectList -Shell $ToolkitShell `
            -SectionTitle $sectionTitle `
            -Rows (ConvertTo-ToolMenuListRows -ToolRoot $ToolRoot -MenuItems $menuItems) `
            -CacheKey $listCacheKey `
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
            Clear-ShellSingleSelectListCache -Shell $ToolkitShell -CacheKey $listCacheKey
            continue
        }

        $code = Invoke-ToolBusinessAction -ToolRoot $ToolRoot -Action $picked `
            -ToolkitShell $ToolkitShell -ActionScriptParams $mergedActionParams
        if (Test-ShellNavMarker $code) {
            return $code
        }
        if ($code -ne 0) {
            Start-Sleep -Milliseconds 1200
        }
    }
}
