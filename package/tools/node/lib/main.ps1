# node — 一级功能菜单（读 index.json actions + 依赖管理）

param(
    [Parameter(Mandatory = $true)]
    $Config,

    [Parameter(Mandatory = $true)]
    [string]$ToolRoot,

    [int]$PageSize = 0,
    [int]$ViewHeight = 0,
    [switch]$LtsOnly
)

$ErrorActionPreference = 'Stop'

$coreLib = Join-Path $ToolRoot '..\..\core\lib'
. (Join-Path $coreLib 'config\Paths.ps1')
. (Join-Path $coreLib 'config\ListLayout.ps1')
. (Join-Path $coreLib 'config\UserConfig.ps1')
. (Join-Path $coreLib 'config\I18n.ps1')
. (Join-Path $coreLib 'config\Deps-State.ps1')
. (Join-Path $coreLib 'domain\Discover-Tools.ps1')
. (Join-Path $coreLib 'domain\Ensure-ToolDeps.ps1')
. (Join-Path $coreLib 'domain\Invoke-ToolkitDeps.ps1')
. (Join-Path $coreLib 'ui\console\Console-Menu.ps1')
Initialize-PathsFromToolRoot -ToolRoot $ToolRoot

$paging = Resolve-MenuPagingDefaults -PageSize $PageSize -ViewHeight $ViewHeight
$PageSize = $paging.PageSize
$ViewHeight = $paging.ViewHeight

$preview = Test-MiaoDevMode
$tool = Get-ToolFromDirectory -ToolRoot $ToolRoot

function Format-NodeActionLabel {
    param($Action, [int]$Index)

    $label = $Action.label
    if (-not $Action.enabled) {
        $label = "$label [即将推出]"
    }
    return "$label    $($Action.summary)"
}

function Test-NodeActionEnabled {
    param($Action, [int]$Index)

    if (Test-ToolDependencyMenuAction $Action) { return $true }
    return [bool]$Action.enabled
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

    & $scriptPath -PageSize $PageSize -ViewHeight $ViewHeight -LtsOnly:$LtsOnly
    return $LASTEXITCODE
}

$header = New-ToolMenuHeader -ToolConfig $Config -SectionTitle '功能菜单'

while ($true) {
    $menuItems = @(Get-ToolMenuItems -BusinessActions @($Config.actions) -Tool $tool)

    $picked = Show-PaginatedMenu -Header $header -Items $menuItems -CountLabel '个功能' `
        -HideColHeader `
        -GetItemLabel ${function:Format-NodeActionLabel} `
        -TestItemEnabled ${function:Test-NodeActionEnabled}

    if (-not $picked) { exit 0 }

    if (Test-ToolDependencyMenuAction $picked) {
        $null = Invoke-ToolDependencyMenuAction -Tool $tool -Action $picked -Preview:$preview
        Clear-DepsStateCache
        Wait-ToolDependencyMenuContinue
        continue
    }

    exit (Invoke-NodeAction $picked)
}
