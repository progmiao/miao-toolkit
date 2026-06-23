# node — 为项目指定 Node 版本（全量列表 + 标准单选）

param(
    [hashtable]$ToolkitShell = $null,
    $Action = $null,

    [int]$PageSize = 0,
    [int]$ViewHeight = 0,
    [switch]$LtsOnly
)

$ErrorActionPreference = 'Stop'

$toolRoot = Split-Path $PSScriptRoot -Parent
$coreLib = Join-Path $toolRoot '..\..\core\lib'

. (Join-Path $PSScriptRoot 'node-installed-select.ps1')
Import-NodeInstalledSelectCore -CoreLib $coreLib
. (Join-Path $PSScriptRoot 'node-action-title.ps1')
Import-NodeActionTitleCore -CoreLib $coreLib
. (Join-Path $PSScriptRoot 'volta-node.ps1')
. (Join-Path $PSScriptRoot 'node-pin-select.ps1')
Initialize-NodeVoltaToolRoot -ToolRoot $toolRoot
Initialize-PathsFromToolRoot -ToolRoot $toolRoot

$nodeToolAction = Resolve-NodeToolAction -ToolRoot $toolRoot -Action $Action -ScriptLeaf 'pin-project.ps1'
$nodeActionSectionTitle = Get-NodeActionSectionTitle -ToolRoot $toolRoot -Action $nodeToolAction `
    -ScriptLeaf 'pin-project.ps1'
$script:NodeActionSectionTitle = $nodeActionSectionTitle

$script:NodeBrowseInstallDotSourceOnly = $true
. (Join-Path $PSScriptRoot 'browse-install.ps1')
$script:NodeBrowseInstallDotSourceOnly = $false

$paging = Resolve-MenuPagingDefaults -PageSize $PageSize -ViewHeight $ViewHeight
$PageSize = $paging.PageSize
$ViewHeight = $paging.ViewHeight

$standaloneShell = $false
if (-not $ToolkitShell) {
    $ToolkitShell = Initialize-ToolkitShell
    $standaloneShell = $true
}

Sync-MiaoLocaleFromShell -Shell $ToolkitShell

function Invoke-NodePinProjectPage {
    param([hashtable]$Shell)

    $null = Ensure-ToolkitShellLayoutBrandInnerWidth -Shell $Shell
    $sectionTitle = $nodeActionSectionTitle

    if (-not (Get-Command volta -ErrorAction SilentlyContinue)) {
        Show-NodeInstalledSelectMessagePage -Shell $Shell -SectionTitle $sectionTitle `
            -Message (Get-NodePinI18n -ToolRoot $toolRoot -Key 'node.pin.voltaMissing') `
            -Color ([System.ConsoleColor]::Red) -DelayMs 1200
        return (Get-ShellNavMarker -Action 'back')
    }

    $pinContext = Resolve-NodeProjectPinContext
    if ($pinContext.HasProject -and -not (Test-NodeProjectPackageJsonReadable -PackageJsonPath $pinContext.PackageJsonPath)) {
        Show-NodeInstalledSelectMessagePage -Shell $Shell -SectionTitle $sectionTitle `
            -Message (Get-NodePinI18n -ToolRoot $toolRoot -Key 'node.pin.packageJsonInvalid') `
            -Color ([System.ConsoleColor]::Red) -DelayMs 1400
        return 1
    }

    $fetch = Start-NodeBrowseRemoteVersionsFetch -LtsOnly:$LtsOnly
    $loadResult = Wait-NodeBrowseRemoteVersionsLoad -Shell $Shell -SectionTitle $sectionTitle -Fetch $fetch
    if ($loadResult.Nav) {
        return $loadResult.Nav
    }

    try {
        if ($loadResult.Error) {
            throw $loadResult.Error
        }
        $remote = @($loadResult.Remote)
    }
    catch {
        Initialize-ToolkitShellBodyView -Shell $Shell -SectionTitle $sectionTitle -FooterTemplate SystemToolbarOnly
        $layout = $Shell.Layout
        Write-FixedLine $layout.ListStartRow (Get-NodePinI18n -ToolRoot $toolRoot -Key 'node.pin.loadFailed') -Color Red
        Write-FixedLine ($layout.ListStartRow + 1) $_.Exception.Message -Color DarkGray
        Start-Sleep -Milliseconds 1500
        return (Get-ShellNavMarker -Action 'back')
    }

    $progress = if ($loadResult.Progress) {
        $loadResult.Progress
    }
    else {
        @{ Percent = 55; SpinnerIndex = 0 }
    }

    $preparedList = Prepare-NodePinListContent -Shell $Shell -Progress $progress -Remote $remote `
        -PinnedVersion $pinContext.PinnedVersion
    $baseVersions = $preparedList.BaseVersions
    $usePreparedList = $true
    $flashMessage = ''
    $catalogLine = Format-NodePinCatalogLineMessage -ToolRoot $toolRoot -PinContext $pinContext `
        -VoltaInfo $preparedList.VoltaInfo
    $pendingInstallVersion = ''

    while ($true) {
        $pinContext = Resolve-NodeProjectPinContext

        if ($usePreparedList) {
            $voltaInfo = $preparedList.VoltaInfo
            $rows = $preparedList.Rows
            $columnLayout = $preparedList.ColumnLayout
            $sorted = $preparedList.Sorted
            $usePreparedList = $false
        }
        else {
            $voltaInfo = Get-VoltaNodeVersionInfo
            $merged = Build-NodePinMergedItems -BaseVersions $baseVersions -VoltaInfo $voltaInfo `
                -PinnedVersion $pinContext.PinnedVersion
            $sorted = Sort-NodeVersionItems -Items $merged
            $widths = Resolve-NodeInstalledVersionColumnWidths -Shell $Shell
            $rows = Build-NodePinRows -Items $sorted -InstalledMap $voltaInfo.Map `
                -DefaultVersion $voltaInfo.Default -ActiveVersion (Get-ActiveNodeVersion) `
                -PinnedVersion $pinContext.PinnedVersion
            $columnLayout = New-ShellListColumnLayout -Widths @($widths.Version, $widths.Tags)
            Clear-ShellSingleSelectListCache -Shell $Shell -CacheKey 'NodePin'
        }

        if ($sorted.Count -eq 0) {
            Initialize-ToolkitShellBodyView -Shell $Shell -SectionTitle $sectionTitle -FooterTemplate SystemToolbarOnly
            $layout = $Shell.Layout
            Write-FixedLine $layout.ListStartRow (Get-NodePinI18n -ToolRoot $toolRoot -Key 'node.pin.noVersions') -Color Yellow
            Start-Sleep -Milliseconds 900
            return (Get-ShellNavMarker -Action 'back')
        }

        if ($progress.Percent -lt 100) {
            Update-NodeBrowseInstallLoadingProgress -Shell $Shell -Progress $progress -TargetPercent 100
        }

        $catalogLine = Format-NodePinCatalogLineMessage -ToolRoot $toolRoot -PinContext $pinContext `
            -VoltaInfo $voltaInfo
        $statusMessage = Format-NodePinMessageLineMessage -ToolRoot $toolRoot -PinContext $pinContext `
            -VoltaInfo $voltaInfo
        $messageLine = if ([string]::IsNullOrWhiteSpace($flashMessage)) { $statusMessage } else { $flashMessage }

        $picked = Invoke-NodePinVersionSingleSelectPage -Shell $Shell -ToolRoot $toolRoot `
            -Rows $rows -ColumnLayout $columnLayout -InitialCatalogLine $catalogLine `
            -InitialFlashMessage $messageLine -SectionTitle $nodeActionSectionTitle
        $flashMessage = ''

        if (Test-ShellNavMarker $picked) {
            return $picked
        }
        if ($null -eq $picked) {
            return (Get-ShellNavMarker -Action 'back')
        }

        $ver = Resolve-NodeInstalledVersionFromPick -Picked $picked
        if ([string]::IsNullOrWhiteSpace($ver)) {
            continue
        }

        $installedBefore = Test-NodeVersionInstalled -Version $ver -InstalledMap $voltaInfo.Map
        if (-not $installedBefore) {
            $pendingInstallVersion = $ver
            $sourceItem = Resolve-NodePinPickSourceItem -Picked $picked
            $installResult = Run-NodeBrowseInstallOperation -Shell $Shell -Items @($sourceItem) `
                -SectionTitle $nodeActionSectionTitle
            if (Test-ShellNavMarker $installResult) {
                return $installResult
            }

            $pinContext = Resolve-NodeProjectPinContext
            $voltaAfter = Get-VoltaNodeVersionInfo
            $pinned = Normalize-NodeVersionLabel -Version ([string]$pinContext.PinnedVersion)
            $pending = Normalize-NodeVersionLabel -Version $pendingInstallVersion
            if ($pinned -and $pending -eq $pinned `
                -and (Test-NodeVersionInstalled -Version $pending -InstalledMap $voltaAfter.Map)) {
                $flashMessage = Get-NodePinI18n -ToolRoot $toolRoot -Key 'node.pin.installEffective' `
                    -Vars @{ version = $pending }
            }
            $pendingInstallVersion = ''
            continue
        }

        $pinContext = Resolve-NodeProjectPinContext
        $pinned = Normalize-NodeVersionLabel -Version ([string]$pinContext.PinnedVersion)
        if ($pinned -and $ver -eq $pinned) {
            $flashMessage = Get-NodePinI18n -ToolRoot $toolRoot -Key 'node.pin.noChange' -Vars @{ version = $ver }
            continue
        }

        if (-not $pinContext.HasProject) {
            $null = New-NodeProjectPackageJson -Directory $pinContext.CreateDirectory
            $pinContext = Resolve-NodeProjectPinContext
        }

        Push-Location $pinContext.WorkingDirectory
        try {
            & volta pin "node@$ver"
            $code = $LASTEXITCODE
        }
        finally {
            Pop-Location
        }

        if ($code -eq 0) {
            $flashMessage = Get-NodePinI18n -ToolRoot $toolRoot -Key 'node.pin.success' -Vars @{ version = $ver }
        }
        else {
            $flashMessage = Get-NodePinI18n -ToolRoot $toolRoot -Key 'node.pin.failed'
        }
    }
}

$result = Invoke-NodePinProjectPage -Shell $ToolkitShell
if ($standaloneShell) {
    exit $(if ($null -eq $result) { 0 } elseif ($result -is [int]) { $result } else { 0 })
}
return $result
