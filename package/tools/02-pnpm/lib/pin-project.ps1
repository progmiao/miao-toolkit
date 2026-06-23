# pnpm — 为项目指定 pnpm 版本

param(
    [hashtable]$ToolkitShell = $null,
    $Action = $null,

    [int]$PageSize = 0,
    [int]$ViewHeight = 0
)

$ErrorActionPreference = 'Stop'

$toolRoot = Split-Path $PSScriptRoot -Parent
$coreLib = Join-Path $toolRoot '..\..\core\lib'

. (Join-Path $PSScriptRoot 'pnpm-installed-select.ps1')
Import-PnpmInstalledSelectCore -CoreLib $coreLib
. (Join-Path $PSScriptRoot 'pnpm-action-title.ps1')
Import-PnpmActionTitleCore -CoreLib $coreLib
. (Join-Path $PSScriptRoot 'volta-pnpm.ps1')
Initialize-PnpmVoltaToolRoot -ToolRoot $toolRoot
. (Join-Path $PSScriptRoot 'pnpm-pin-select.ps1')

$script:PnpmBrowseInstallDotSourceOnly = $true
. (Join-Path $PSScriptRoot 'browse-install.ps1')
$script:PnpmBrowseInstallDotSourceOnly = $false

Initialize-PathsFromToolRoot -ToolRoot $toolRoot

$PnpmToolAction = Resolve-PnpmToolAction -ToolRoot $toolRoot -Action $Action -ScriptLeaf 'pin-project.ps1'
$PnpmActionSectionTitle = Get-PnpmActionSectionTitle -ToolRoot $toolRoot -Action $PnpmToolAction `
    -ScriptLeaf 'pin-project.ps1'

$paging = Resolve-MenuPagingDefaults -PageSize $PageSize -ViewHeight $ViewHeight
$PageSize = $paging.PageSize
$ViewHeight = $paging.ViewHeight

$standaloneShell = $false
if (-not $ToolkitShell) {
    $ToolkitShell = Initialize-ToolkitShell
    $standaloneShell = $true
}

Sync-MiaoLocaleFromShell -Shell $ToolkitShell

function Invoke-PnpmPinProjectPage {
    param([hashtable]$Shell)

    $null = Ensure-ToolkitShellLayoutBrandInnerWidth -Shell $Shell
    $sectionTitle = $PnpmActionSectionTitle

    if (-not (Get-Command volta -ErrorAction SilentlyContinue)) {
        Show-PnpmInstalledSelectMessagePage -Shell $Shell -SectionTitle $sectionTitle `
            -Message (Get-PnpmPinI18n -ToolRoot $toolRoot -Key 'pnpm.pin.voltaMissing') `
            -Color ([System.ConsoleColor]::Red) -DelayMs 1200
        return (Get-ShellNavMarker -Action 'back')
    }

    $pinContext = Resolve-PnpmProjectPinContext
    if ($pinContext.HasProject -and -not (Test-PnpmProjectPackageJsonReadable -PackageJsonPath $pinContext.PackageJsonPath)) {
        Show-PnpmInstalledSelectMessagePage -Shell $Shell -SectionTitle $sectionTitle `
            -Message (Get-PnpmPinI18n -ToolRoot $toolRoot -Key 'pnpm.pin.packageJsonInvalid') `
            -Color ([System.ConsoleColor]::Red) -DelayMs 1400
        return 1
    }

    $fetch = Start-PnpmBrowseRemoteVersionsFetch
    $loadResult = Wait-PnpmBrowseRemoteVersionsLoad -Shell $Shell -SectionTitle $sectionTitle -Fetch $fetch
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
        Write-FixedLine $layout.ListStartRow (Get-PnpmPinI18n -ToolRoot $toolRoot -Key 'pnpm.pin.loadFailed') -Color Red
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

    $preparedList = Prepare-PnpmPinListContent -Shell $Shell -Progress $progress -Remote $remote `
        -PinnedVersion $pinContext.PinnedVersion
    $usePreparedList = $true
    $flashMessage = ''
    $catalogLine = Format-PnpmPinCatalogLineMessage -ToolRoot $toolRoot -PinContext $pinContext `
        -VoltaInfo $preparedList.VoltaInfo
    $pendingInstallVersion = ''

    while ($true) {
        $pinContext = Resolve-PnpmProjectPinContext

        if ($usePreparedList) {
            $voltaInfo = $preparedList.VoltaInfo
            $rows = $preparedList.Rows
            $columnLayout = $preparedList.ColumnLayout
            $sorted = $preparedList.Sorted
            $usePreparedList = $false
        }
        else {
            $voltaInfo = Get-VoltaPnpmVersionInfo
            $merged = Build-PnpmPinMergedItems -BaseVersions $preparedList.BaseVersions -VoltaInfo $voltaInfo `
                -PinnedVersion $pinContext.PinnedVersion
            $sorted = Sort-PnpmVersionItems -Items $merged
            $widths = Resolve-PnpmInstalledVersionColumnWidths -Shell $Shell
            $rows = Build-PnpmPinRows -Items $sorted -InstalledMap $voltaInfo.Map `
                -DefaultVersion $voltaInfo.Default -ActiveVersion (Get-ActivePnpmVersion) `
                -PinnedVersion $pinContext.PinnedVersion
            $columnLayout = New-ShellListColumnLayout -Widths @($widths.Version, $widths.Tags)
            Clear-ShellSingleSelectListCache -Shell $Shell -CacheKey 'PnpmPin'
        }

        if ($sorted.Count -eq 0) {
            Initialize-ToolkitShellBodyView -Shell $Shell -SectionTitle $sectionTitle -FooterTemplate SystemToolbarOnly
            $layout = $Shell.Layout
            Write-FixedLine $layout.ListStartRow (Get-PnpmPinI18n -ToolRoot $toolRoot -Key 'pnpm.pin.noVersions') -Color Yellow
            Start-Sleep -Milliseconds 900
            return (Get-ShellNavMarker -Action 'back')
        }

        if ($progress.Percent -lt 100) {
            Update-PnpmBrowseInstallLoadingProgress -Shell $Shell -Progress $progress -TargetPercent 100
        }

        $catalogLine = Format-PnpmPinCatalogLineMessage -ToolRoot $toolRoot -PinContext $pinContext `
            -VoltaInfo $voltaInfo
        $statusMessage = Format-PnpmPinMessageLineMessage -ToolRoot $toolRoot -PinContext $pinContext `
            -VoltaInfo $voltaInfo
        $messageLine = if ([string]::IsNullOrWhiteSpace($flashMessage)) { $statusMessage } else { $flashMessage }

        $picked = Invoke-PnpmPinVersionSingleSelectPage -Shell $Shell -ToolRoot $toolRoot `
            -Rows $rows -ColumnLayout $columnLayout -InitialCatalogLine $catalogLine `
            -InitialFlashMessage $messageLine -SectionTitle $PnpmActionSectionTitle
        $flashMessage = ''

        if (Test-ShellNavMarker $picked) {
            return $picked
        }
        if ($null -eq $picked) {
            return (Get-ShellNavMarker -Action 'back')
        }

        $ver = Resolve-PnpmInstalledVersionFromPick -Picked $picked
        if ([string]::IsNullOrWhiteSpace($ver)) {
            continue
        }

        $installedBefore = Test-PnpmVersionInstalled -Version $ver -InstalledMap $voltaInfo.Map
        if (-not $installedBefore) {
            $pendingInstallVersion = $ver
            $sourceItem = Resolve-PnpmPinPickSourceItem -Picked $picked
            $installResult = Run-PnpmBrowseInstallOperation -Shell $Shell -Items @($sourceItem) `
                -SectionTitle $PnpmActionSectionTitle
            if (Test-ShellNavMarker $installResult) {
                return $installResult
            }

            $pinContext = Resolve-PnpmProjectPinContext
            $voltaAfter = Get-VoltaPnpmVersionInfo
            $pinned = Normalize-PnpmVersionLabel -Version ([string]$pinContext.PinnedVersion)
            $pending = Normalize-PnpmVersionLabel -Version $pendingInstallVersion
            if ($pinned -and $pending -eq $pinned `
                -and (Test-PnpmVersionInstalled -Version $pending -InstalledMap $voltaAfter.Map)) {
                $flashMessage = Get-PnpmPinI18n -ToolRoot $toolRoot -Key 'pnpm.pin.installEffective' `
                    -Vars @{ version = $pending }
            }
            $pendingInstallVersion = ''
            continue
        }

        $pinContext = Resolve-PnpmProjectPinContext
        $pinned = Normalize-PnpmVersionLabel -Version ([string]$pinContext.PinnedVersion)
        if ($pinned -and $ver -eq $pinned) {
            $flashMessage = Get-PnpmPinI18n -ToolRoot $toolRoot -Key 'pnpm.pin.noChange' -Vars @{ version = $ver }
            continue
        }

        if (-not $pinContext.HasProject) {
            $null = New-PnpmProjectPackageJson -Directory $pinContext.CreateDirectory
            $pinContext = Resolve-PnpmProjectPinContext
        }

        Push-Location $pinContext.WorkingDirectory
        try {
            Ensure-VoltaPnpmFeatureEnabled
            & volta pin "pnpm@$ver"
            $code = $LASTEXITCODE
        }
        finally {
            Pop-Location
        }

        if ($code -eq 0) {
            $flashMessage = Get-PnpmPinI18n -ToolRoot $toolRoot -Key 'pnpm.pin.success' -Vars @{ version = $ver }
        }
        else {
            $flashMessage = Get-PnpmPinI18n -ToolRoot $toolRoot -Key 'pnpm.pin.failed'
        }
    }
}

$result = Invoke-PnpmPinProjectPage -Shell $ToolkitShell
if ($standaloneShell) {
    exit $(if ($null -eq $result) { 0 } elseif ($result -is [int]) { $result } else { 0 })
}
return $result
