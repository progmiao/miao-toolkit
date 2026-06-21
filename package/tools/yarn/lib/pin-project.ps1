# yarn — 为项目指定 Yarn 版本

param(
    [hashtable]$ToolkitShell = $null,
    $Action = $null,

    [int]$PageSize = 0,
    [int]$ViewHeight = 0
)

$ErrorActionPreference = 'Stop'

$toolRoot = Split-Path $PSScriptRoot -Parent
$coreLib = Join-Path $toolRoot '..\..\core\lib'

. (Join-Path $PSScriptRoot 'yarn-installed-select.ps1')
Import-YarnInstalledSelectCore -CoreLib $coreLib
. (Join-Path $PSScriptRoot 'yarn-action-title.ps1')
Import-YarnActionTitleCore -CoreLib $coreLib
. (Join-Path $PSScriptRoot 'volta-yarn.ps1')
Initialize-YarnVoltaToolRoot -ToolRoot $toolRoot
. (Join-Path $PSScriptRoot 'yarn-pin-select.ps1')

$script:YarnBrowseInstallDotSourceOnly = $true
. (Join-Path $PSScriptRoot 'browse-install.ps1')
$script:YarnBrowseInstallDotSourceOnly = $false

Initialize-PathsFromToolRoot -ToolRoot $toolRoot

$yarnToolAction = Resolve-YarnToolAction -ToolRoot $toolRoot -Action $Action -ScriptLeaf 'pin-project.ps1'
$yarnActionSectionTitle = Get-YarnActionSectionTitle -ToolRoot $toolRoot -Action $yarnToolAction `
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

function Invoke-YarnPinProjectPage {
    param([hashtable]$Shell)

    $null = Ensure-ToolkitShellLayoutBrandInnerWidth -Shell $Shell
    $sectionTitle = $yarnActionSectionTitle

    if (-not (Get-Command volta -ErrorAction SilentlyContinue)) {
        Show-YarnInstalledSelectMessagePage -Shell $Shell -SectionTitle $sectionTitle `
            -Message (Get-YarnPinI18n -ToolRoot $toolRoot -Key 'yarn.pin.voltaMissing') `
            -Color ([System.ConsoleColor]::Red) -DelayMs 1200
        return (Get-ShellNavMarker -Action 'back')
    }

    $pinContext = Resolve-YarnProjectPinContext
    if ($pinContext.HasProject -and -not (Test-YarnProjectPackageJsonReadable -PackageJsonPath $pinContext.PackageJsonPath)) {
        Show-YarnInstalledSelectMessagePage -Shell $Shell -SectionTitle $sectionTitle `
            -Message (Get-YarnPinI18n -ToolRoot $toolRoot -Key 'yarn.pin.packageJsonInvalid') `
            -Color ([System.ConsoleColor]::Red) -DelayMs 1400
        return 1
    }

    $fetch = Start-YarnBrowseRemoteVersionsFetch
    $loadResult = Wait-YarnBrowseRemoteVersionsLoad -Shell $Shell -SectionTitle $sectionTitle -Fetch $fetch
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
        Write-FixedLine $layout.ListStartRow (Get-YarnPinI18n -ToolRoot $toolRoot -Key 'yarn.pin.loadFailed') -Color Red
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

    $preparedList = Prepare-YarnPinListContent -Shell $Shell -Progress $progress -Remote $remote `
        -PinnedVersion $pinContext.PinnedVersion
    $usePreparedList = $true
    $flashMessage = ''
    $contentLine = Format-YarnPinContentLineMessage -ToolRoot $toolRoot -PinContext $pinContext `
        -VoltaInfo $preparedList.VoltaInfo
    $pendingInstallVersion = ''

    while ($true) {
        $pinContext = Resolve-YarnProjectPinContext

        if ($usePreparedList) {
            $voltaInfo = $preparedList.VoltaInfo
            $rows = $preparedList.Rows
            $columnLayout = $preparedList.ColumnLayout
            $sorted = $preparedList.Sorted
            $usePreparedList = $false
        }
        else {
            $voltaInfo = Get-VoltaYarnVersionInfo
            $merged = Build-YarnPinMergedItems -BaseVersions $preparedList.BaseVersions -VoltaInfo $voltaInfo `
                -PinnedVersion $pinContext.PinnedVersion
            $sorted = Sort-YarnVersionItems -Items $merged
            $widths = Resolve-YarnInstalledVersionColumnWidths -Shell $Shell
            $rows = Build-YarnPinRows -Items $sorted -InstalledMap $voltaInfo.Map `
                -DefaultVersion $voltaInfo.Default -ActiveVersion (Get-ActiveYarnVersion) `
                -PinnedVersion $pinContext.PinnedVersion
            $columnLayout = New-ShellListColumnLayout -Widths @($widths.Version, $widths.Tags)
            Clear-ShellSingleSelectListCache -Shell $Shell -CacheKey 'YarnPin'
        }

        if ($sorted.Count -eq 0) {
            Initialize-ToolkitShellBodyView -Shell $Shell -SectionTitle $sectionTitle -FooterTemplate SystemToolbarOnly
            $layout = $Shell.Layout
            Write-FixedLine $layout.ListStartRow (Get-YarnPinI18n -ToolRoot $toolRoot -Key 'yarn.pin.noVersions') -Color Yellow
            Start-Sleep -Milliseconds 900
            return (Get-ShellNavMarker -Action 'back')
        }

        if ($progress.Percent -lt 100) {
            Update-YarnBrowseInstallLoadingProgress -Shell $Shell -Progress $progress -TargetPercent 100
        }

        $contentLine = Format-YarnPinContentLineMessage -ToolRoot $toolRoot -PinContext $pinContext `
            -VoltaInfo $voltaInfo
        $statusMessage = Format-YarnPinMessageLineMessage -ToolRoot $toolRoot -PinContext $pinContext `
            -VoltaInfo $voltaInfo
        $messageLine = if ([string]::IsNullOrWhiteSpace($flashMessage)) { $statusMessage } else { $flashMessage }

        $picked = Invoke-YarnPinVersionSingleSelectPage -Shell $Shell -ToolRoot $toolRoot `
            -Rows $rows -ColumnLayout $columnLayout -InitialContentLine $contentLine `
            -InitialFlashMessage $messageLine -SectionTitle $yarnActionSectionTitle
        $flashMessage = ''

        if (Test-ShellNavMarker $picked) {
            return $picked
        }
        if ($null -eq $picked) {
            return (Get-ShellNavMarker -Action 'back')
        }

        $ver = Resolve-YarnInstalledVersionFromPick -Picked $picked
        if ([string]::IsNullOrWhiteSpace($ver)) {
            continue
        }

        $installedBefore = Test-YarnVersionInstalled -Version $ver -InstalledMap $voltaInfo.Map
        if (-not $installedBefore) {
            $pendingInstallVersion = $ver
            $sourceItem = Resolve-YarnPinPickSourceItem -Picked $picked
            $installResult = Run-YarnBrowseInstallOperation -Shell $Shell -Items @($sourceItem) `
                -SectionTitle $yarnActionSectionTitle
            if (Test-ShellNavMarker $installResult) {
                return $installResult
            }

            $pinContext = Resolve-YarnProjectPinContext
            $voltaAfter = Get-VoltaYarnVersionInfo
            $pinned = Normalize-YarnVersionLabel -Version ([string]$pinContext.PinnedVersion)
            $pending = Normalize-YarnVersionLabel -Version $pendingInstallVersion
            if ($pinned -and $pending -eq $pinned `
                -and (Test-YarnVersionInstalled -Version $pending -InstalledMap $voltaAfter.Map)) {
                $flashMessage = Get-YarnPinI18n -ToolRoot $toolRoot -Key 'yarn.pin.installEffective' `
                    -Vars @{ version = $pending }
            }
            $pendingInstallVersion = ''
            continue
        }

        $pinContext = Resolve-YarnProjectPinContext
        $pinned = Normalize-YarnVersionLabel -Version ([string]$pinContext.PinnedVersion)
        if ($pinned -and $ver -eq $pinned) {
            $flashMessage = Get-YarnPinI18n -ToolRoot $toolRoot -Key 'yarn.pin.noChange' -Vars @{ version = $ver }
            continue
        }

        if (-not $pinContext.HasProject) {
            $null = New-YarnProjectPackageJson -Directory $pinContext.CreateDirectory
            $pinContext = Resolve-YarnProjectPinContext
        }

        Push-Location $pinContext.WorkingDirectory
        try {
            & volta pin "yarn@$ver"
            $code = $LASTEXITCODE
        }
        finally {
            Pop-Location
        }

        if ($code -eq 0) {
            $flashMessage = Get-YarnPinI18n -ToolRoot $toolRoot -Key 'yarn.pin.success' -Vars @{ version = $ver }
        }
        else {
            $flashMessage = Get-YarnPinI18n -ToolRoot $toolRoot -Key 'yarn.pin.failed'
        }
    }
}

$result = Invoke-YarnPinProjectPage -Shell $ToolkitShell
if ($standaloneShell) {
    exit $(if ($null -eq $result) { 0 } elseif ($result -is [int]) { $result } else { 0 })
}
return $result
