# pnpm — 浏览并安装（Shell 多选版本列表）

param(
    [hashtable]$ToolkitShell = $null,
    $Action = $null,

    [int]$PageSize = 0,
    [int]$ViewHeight = 0
)

$ErrorActionPreference = 'Stop'

$toolRoot = Split-Path $PSScriptRoot -Parent
$coreLib = Join-Path $toolRoot '..\..\core\lib'

function Import-PnpmBrowseInstallCore {
    if (-not (Get-Command Initialize-PathsFromToolRoot -ErrorAction SilentlyContinue)) {
        . (Join-Path $coreLib 'config\Paths.ps1')
        . (Join-Path $coreLib 'config\ListLayout.ps1')
        . (Join-Path $coreLib 'config\UserConfig.ps1')
        . (Join-Path $coreLib 'config\I18n.ps1')
    }

    . (Join-Path $coreLib 'ui\console\Console-Menu.ps1')
    . (Join-Path $coreLib 'ui\shell\Nav.ps1')
    . (Join-Path $coreLib 'ui\shell\SystemToolbar.ps1')
    . (Join-Path $coreLib 'ui\shell\SingleSelectList.ps1')
    . (Join-Path $coreLib 'ui\shell\MultiSelectList.ps1')
    . (Join-Path $coreLib 'ui\shell\Draw.ps1')
    . (Join-Path $coreLib 'ui\shell\Layout.ps1')
    . (Join-Path $coreLib 'ui\shell\Header.ps1')
    . (Join-Path $coreLib 'ui\shell\Title.ps1')
    . (Join-Path $coreLib 'ui\shell\CatalogRow.ps1')
    . (Join-Path $coreLib 'ui\shell\Exit.ps1')
    . (Join-Path $coreLib 'ui\shell\Footer.ps1')

    if (-not (Get-Command Draw-ToolkitDepOperationView -ErrorAction SilentlyContinue)) {
        . (Join-Path $coreLib 'ui\shell\DepOperationView.ps1')
    }
}

Import-PnpmBrowseInstallCore
. (Join-Path $PSScriptRoot 'pnpm-action-title.ps1')
Import-PnpmActionTitleCore -CoreLib $coreLib
. (Join-Path $PSScriptRoot 'volta-pnpm.ps1')
Set-PnpmVoltaToolRoot -ToolRoot $toolRoot
. (Join-Path $PSScriptRoot 'browse-install-run.ps1')
Initialize-PathsFromToolRoot -ToolRoot $toolRoot

$paging = Resolve-MenuPagingDefaults -PageSize $PageSize -ViewHeight $ViewHeight
$PageSize = $paging.PageSize
$ViewHeight = $paging.ViewHeight

$standaloneShell = $false
if (-not $ToolkitShell) {
    $ToolkitShell = Initialize-ToolkitShell
    $standaloneShell = $true
}

Sync-MiaoLocaleFromShell -Shell $ToolkitShell

if (-not $script:PnpmBrowseInstallDotSourceOnly) {
    $PnpmToolAction = Resolve-PnpmToolAction -ToolRoot $toolRoot -Action $Action -ScriptLeaf 'browse-install.ps1'
    $PnpmActionSectionTitle = Get-PnpmActionSectionTitle -ToolRoot $toolRoot -Action $PnpmToolAction `
        -ScriptLeaf 'browse-install.ps1'
    $script:PnpmActionSectionTitle = $PnpmActionSectionTitle
}

function Get-PnpmBrowseI18n {
    param(
        [string]$Key,
        [hashtable]$Vars = @{}
    )

    return Get-ToolI18n -ToolRoot $toolRoot -Key $Key -Vars $Vars
}

function Get-PnpmBrowseInstallTagsLabel {
    param(
        $Item,
        [hashtable]$InstalledMap,
        [string]$DefaultVersion,
        [string]$ActiveVersion
    )

    return (Get-PnpmVersionStatusTags -Item $Item -InstalledMap $InstalledMap `
        -DefaultVersion $DefaultVersion -ActiveVersion $ActiveVersion)
}

function Build-PnpmBrowseInstallRows {
    param(
        [array]$Items,
        [hashtable]$InstalledMap,
        [string]$DefaultVersion,
        [string]$ActiveVersion
    )

    return ConvertTo-ShellListRows -Items $Items -KeepSource -GetSearchKey {
        param($Item, [int]$Index)
        [string]$Item.Version
    } -MapCells {
        param($Item, [int]$Index)
        @(
            (Get-PnpmBrowseInstallTagsLabel -Item $Item -InstalledMap $InstalledMap `
                -DefaultVersion $DefaultVersion -ActiveVersion $ActiveVersion)
        )
    } -GetEnabled {
        param($Item, [int]$Index)
        $version = Normalize-PnpmVersionLabel -Version ([string]$Item.Version)
        -not $InstalledMap.ContainsKey($version)
    }
}

function Resolve-PnpmBrowseInstallTagsColumnWidth {
    param([hashtable]$Shell)

    $metrics = Get-ToolkitShellLayoutLineMetrics -Shell $Shell
    $versionKeyWidth = Get-ShellMultiSelectSearchKeyWidth
    $gap = Get-MenuColumnGap
    $prefixReserve = 2 + 3 + 1 + $versionKeyWidth + $gap
    $remaining = [int]$metrics.EndColumn - $prefixReserve
    $maxTags = 26
    return [Math]::Max(10, [Math]::Min($maxTags, $remaining))
}

function Get-PnpmBrowseInstallLoadingStatusText {
    param(
        [string]$Spinner,
        [string]$StatusKey = 'pnpm.browse.loading'
    )

    return (Get-PnpmBrowseI18n -Key $StatusKey -Vars @{ spinner = $Spinner })
}

function Write-PnpmBrowseInstallLoadingView {
    param(
        [hashtable]$Shell,
        [string]$Spinner,
        [int]$Percent = 0,
        [string]$StatusKey = 'pnpm.browse.loadingFetch'
    )

    $layout = $Shell.Layout
    $barWidth = if ($Shell.BrandInnerWidth -gt 0) { [int]$Shell.BrandInnerWidth } else { [int]$layout.BrandInnerWidth }
    if ($barWidth -le 0) {
        $null = Ensure-ToolkitShellLayoutBrandInnerWidth -Shell $Shell
        $barWidth = if ($Shell.BrandInnerWidth -gt 0) { [int]$Shell.BrandInnerWidth } else { [int]$Shell.Layout.BrandInnerWidth }
    }

    $percent = [Math]::Min(100, [Math]::Max(0, $Percent))
    $fnFormatBar = Resolve-DepOperationFn 'Format-ToolkitDepProgressBar'
    $barLine = & $fnFormatBar -Current 0 -Total 1 -Name '' -BrandInnerWidth $barWidth `
        -LoadingPercent $percent
    $statusText = Get-PnpmBrowseInstallLoadingStatusText -Spinner $Spinner -StatusKey $StatusKey
    $statusRow = [int]$layout.ListStartRow + 1
    $progressRow = [int]$layout.ListStartRow

    $useBatch = Test-ShellConsoleBatchDraw
    $enteredBatch = $false
    if ($useBatch) {
        Enter-ConsoleDrawBatch
        $enteredBatch = $true
    }

    Write-FixedLine $progressRow $barLine -Color Cyan
    Write-FixedLine $statusRow " $statusText" -Color White
    for ($row = 2; $row -lt $layout.ListViewportHeight; $row++) {
        Write-FixedLine ($layout.ListStartRow + $row) '' -Color DarkGray
    }

    if ($enteredBatch) {
        $null = Complete-ConsoleDrawBatch -ToolkitShell $Shell
    }
}

function Show-PnpmBrowseInstallLoadingFrame {
    param(
        [hashtable]$Shell,
        [string]$SectionTitle,
        [string]$Spinner = '|',
        [int]$Percent = 0,
        [string]$StatusKey = 'pnpm.browse.loadingFetch'
    )

    Initialize-ToolkitShellBodyView -Shell $Shell -SectionTitle $SectionTitle -FooterTemplate SystemToolbarOnly
    Write-PnpmBrowseInstallLoadingView -Shell $Shell -Spinner $Spinner -Percent $Percent -StatusKey $StatusKey
    $toolbar = New-ShellSystemToolbarConfig
    Write-ToolkitShellFooter -Shell $Shell -Template SystemToolbarOnly -ToolbarConfig $toolbar
    Finalize-ToolkitShellBodyView -Shell $Shell
}

function Get-PnpmBrowseInstallLoadingStatusKeyForPercent {
    param([int]$Percent)

    if ($Percent -ge 100) { return 'pnpm.browse.loadingDraw' }
    if ($Percent -ge 80) { return 'pnpm.browse.loadingResult' }
    if ($Percent -ge 55) { return 'pnpm.browse.loadingCompute' }
    return 'pnpm.browse.loadingFetch'
}

function Update-PnpmBrowseInstallLoadingProgress {
    param(
        [hashtable]$Shell,
        [hashtable]$Progress,
        [int]$TargetPercent
    )

    $spinnerFrames = @('|', '/', '-', '\')
    if ($TargetPercent -gt $Progress.Percent) {
        $Progress.Percent = $TargetPercent
    }

    $spinner = $spinnerFrames[$Progress.SpinnerIndex % $spinnerFrames.Count]
    $Progress.SpinnerIndex++
    $statusKey = Get-PnpmBrowseInstallLoadingStatusKeyForPercent -Percent $Progress.Percent
    Write-PnpmBrowseInstallLoadingView -Shell $Shell -Spinner $spinner -Percent $Progress.Percent `
        -StatusKey $statusKey
}

function Complete-PnpmBrowseInstallLoadingProgress {
    param(
        [hashtable]$Shell,
        [hashtable]$Progress,
        [array]$Targets
    )

    foreach ($target in $Targets) {
        Update-PnpmBrowseInstallLoadingProgress -Shell $Shell -Progress $Progress -TargetPercent $target
    }
}

function Build-PnpmBrowseInstallBaseVersions {
    param([array]$Remote)

    $seen = @{}
    $baseVersions = @()
    foreach ($r in $Remote) {
        $ver = Normalize-PnpmVersionLabel -Version ([string]$r.Version)
        if (-not $seen[$ver]) {
            $baseVersions += $r
            $seen[$ver] = $true
        }
    }
    return $baseVersions
}

function Build-PnpmBrowseInstallMergedItems {
    param(
        [array]$BaseVersions,
        [hashtable]$VoltaInfo
    )

    $items = [System.Collections.Generic.List[object]]::new()
    $seen = @{}
    foreach ($r in $BaseVersions) {
        $ver = Normalize-PnpmVersionLabel -Version ([string]$r.Version)
        if (-not $seen[$ver]) {
            $items.Add($r)
            $seen[$ver] = $true
        }
    }
    foreach ($ver in $VoltaInfo.Map.Keys) {
        if (-not $seen[$ver]) {
            $items.Add((New-PnpmVersionMenuItem -Version $ver))
            $seen[$ver] = $true
        }
    }
    return @($items.ToArray())
}

function Prepare-PnpmBrowseInstallListContent {
    param(
        [hashtable]$Shell,
        [hashtable]$Progress,
        [array]$Remote
    )

    Update-PnpmBrowseInstallLoadingProgress -Shell $Shell -Progress $Progress -TargetPercent 60
    $baseVersions = Build-PnpmBrowseInstallBaseVersions -Remote $Remote

    Update-PnpmBrowseInstallLoadingProgress -Shell $Shell -Progress $Progress -TargetPercent 70
    $voltaInfo = Get-VoltaPnpmVersionInfo
    $activeVersion = Get-ActivePnpmVersion

    Update-PnpmBrowseInstallLoadingProgress -Shell $Shell -Progress $Progress -TargetPercent 85
    $merged = Build-PnpmBrowseInstallMergedItems -BaseVersions $baseVersions -VoltaInfo $voltaInfo
    $sorted = Sort-PnpmVersionItems -Items $merged

    Update-PnpmBrowseInstallLoadingProgress -Shell $Shell -Progress $Progress -TargetPercent 95
    $tagsWidth = Resolve-PnpmBrowseInstallTagsColumnWidth -Shell $Shell
    $rows = Build-PnpmBrowseInstallRows -Items $sorted -InstalledMap $voltaInfo.Map `
        -DefaultVersion $voltaInfo.Default -ActiveVersion $activeVersion
    $columnLayout = New-ShellListColumnLayout -Widths @($tagsWidth)

    Clear-ShellMultiSelectListCache -Shell $Shell -CacheKey 'PnpmBrowse'
    Initialize-ShellMultiSelectListDependencies
    $normalized = @(Normalize-ShellListRows -Rows $rows -ColumnLayout $columnLayout)
    $null = Get-ShellMultiSelectListRowCache -Shell $Shell -CacheKey 'PnpmBrowse' `
        -Rows $normalized -ColumnLayout $columnLayout

    return @{
        BaseVersions  = $baseVersions
        Rows          = $rows
        VoltaInfo     = $voltaInfo
        ActiveVersion = $activeVersion
        Sorted        = $sorted
        TagsWidth     = $tagsWidth
        ColumnLayout  = $columnLayout
    }
}

function Start-PnpmBrowseRemoteVersionsFetch {
    $job = Start-Job -ScriptBlock {
        $ErrorActionPreference = 'Stop'
        $seen = @{}
        $items = [System.Collections.Generic.List[object]]::new()

        try {
            $pkg = Invoke-RestMethod 'https://registry.npmjs.org/pnpm'
            foreach ($ver in @($pkg.versions.PSObject.Properties.Name)) {
                $norm = ($ver -replace '^v', '').Trim()
                if ([string]::IsNullOrWhiteSpace($norm)) { continue }
                if ($norm -match '[^0-9.]') { continue }
                if ($seen[$norm]) { continue }
                $seen[$norm] = $true
                $items.Add([PSCustomObject]@{ Version = $norm }) | Out-Null
            }
        }
        catch {}

        return @($items.ToArray())
    }

    return @{ Job = $job }
}

function Complete-PnpmBrowseRemoteVersionsFetch {
    param($Fetch)

    if (-not $Fetch -or -not $Fetch.Job) { return $null }

    try {
        $result = Receive-Job -Job $Fetch.Job -ErrorAction Stop
        return @($result | Sort-Object {
            try { [version]($_.Version.Split('-')[0]) }
            catch { [version]'0.0.0' }
        } -Descending)
    }
    finally {
        Remove-Job -Job $Fetch.Job -Force -ErrorAction SilentlyContinue
    }
}

function Stop-PnpmBrowseRemoteVersionsFetch {
    param($Fetch)

    if (-not $Fetch -or -not $Fetch.Job) { return }

    try {
        if ($Fetch.Job.State -eq 'Running') {
            Stop-Job -Job $Fetch.Job -ErrorAction SilentlyContinue
        }
    }
    catch {}
    finally {
        Remove-Job -Job $Fetch.Job -Force -ErrorAction SilentlyContinue
    }
}

function Test-PnpmBrowseRemoteVersionsFetchRunning {
    param($Fetch)

    return ($Fetch -and $Fetch.Job -and $Fetch.Job.State -eq 'Running')
}

function Wait-PnpmBrowseRemoteVersionsLoad {
    param(
        [hashtable]$Shell,
        [string]$SectionTitle,
        $Fetch
    )

    $toolbar = New-ShellSystemToolbarConfig
    $progress = @{
        Percent      = 0
        SpinnerIndex = 0
    }

    Set-ToolkitShellToolbarLocked -Shell $Shell -Locked $true
    Show-PnpmBrowseInstallLoadingFrame -Shell $Shell -SectionTitle $SectionTitle `
        -Spinner '|' -Percent 0 -StatusKey 'pnpm.browse.loadingFetch'

    while ($true) {
        if (-not (Test-PnpmBrowseRemoteVersionsFetchRunning -Fetch $Fetch)) {
            break
        }

        $fetchCap = 55
        if ($progress.Percent -lt $fetchCap) {
            Update-PnpmBrowseInstallLoadingProgress -Shell $Shell -Progress $progress `
                -TargetPercent ([Math]::Min($fetchCap, $progress.Percent + 2))
        }

        if (Test-ConsoleKeyAvailable) {
            $key = Read-ShellSystemToolbarKey -Shell $Shell -ToolbarConfig $toolbar
            if (Test-ShellNavMarker $key) {
                Stop-PnpmBrowseRemoteVersionsFetch -Fetch $Fetch
                Set-ToolkitShellToolbarLocked -Shell $Shell -Locked $false
                return @{ Nav = $key; Remote = $null; Error = $null }
            }
        }

        Start-Sleep -Milliseconds 120
    }

    try {
        $remote = Complete-PnpmBrowseRemoteVersionsFetch -Fetch $Fetch
        if ($progress.Percent -lt 55) {
            Complete-PnpmBrowseInstallLoadingProgress -Shell $Shell -Progress $progress -Targets @(55)
        }
        Set-ToolkitShellToolbarLocked -Shell $Shell -Locked $false
        return @{ Nav = $null; Remote = $remote; Error = $null; Progress = $progress }
    }
    catch {
        Set-ToolkitShellToolbarLocked -Shell $Shell -Locked $false
        return @{ Nav = $null; Remote = $null; Error = $_; Progress = $progress }
    }
}

function Invoke-PnpmBrowseInstallPage {
    param([hashtable]$Shell)

    $null = Ensure-ToolkitShellLayoutBrandInnerWidth -Shell $Shell

    if (-not (Get-Command volta -ErrorAction SilentlyContinue)) {
        Initialize-ToolkitShellBodyView -Shell $Shell -SectionTitle $PnpmActionSectionTitle `
            -FooterTemplate SystemToolbarOnly
        $layout = $Shell.Layout
        Write-FixedLine $layout.ListStartRow (Get-PnpmBrowseI18n -Key 'pnpm.browse.voltaMissing') -Color Red
        Start-Sleep -Milliseconds 1200
        return (Get-ShellNavMarker -Action 'back')
    }

    $sectionTitle = $PnpmActionSectionTitle
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
        Write-FixedLine $layout.ListStartRow (Get-PnpmBrowseI18n -Key 'pnpm.browse.loadFailed') -Color Red
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

    $preparedList = Prepare-PnpmBrowseInstallListContent -Shell $Shell -Progress $progress -Remote $remote
    $usePreparedList = $true

    while ($true) {
        if ($usePreparedList) {
            $rows = $preparedList.Rows
            $sorted = $preparedList.Sorted
            $columnLayout = $preparedList.ColumnLayout
            $usePreparedList = $false
        }
        else {
            $voltaInfo = Get-VoltaPnpmVersionInfo
            $activeVersion = Get-ActivePnpmVersion
            $merged = Build-PnpmBrowseInstallMergedItems -BaseVersions $preparedList.BaseVersions -VoltaInfo $voltaInfo
            $sorted = Sort-PnpmVersionItems -Items $merged
            $tagsWidth = Resolve-PnpmBrowseInstallTagsColumnWidth -Shell $Shell
            $rows = Build-PnpmBrowseInstallRows -Items $sorted -InstalledMap $voltaInfo.Map `
                -DefaultVersion $voltaInfo.Default -ActiveVersion $activeVersion
            $columnLayout = New-ShellListColumnLayout -Widths @($tagsWidth)
            Clear-ShellMultiSelectListCache -Shell $Shell -CacheKey 'PnpmBrowse'
        }

        if ($sorted.Count -eq 0) {
            Initialize-ToolkitShellBodyView -Shell $Shell -SectionTitle $sectionTitle -FooterTemplate SystemToolbarOnly
            $layout = $Shell.Layout
            Write-FixedLine $layout.ListStartRow (Get-PnpmBrowseI18n -Key 'pnpm.browse.noVersions') -Color Yellow
            Start-Sleep -Milliseconds 900
            return (Get-ShellNavMarker -Action 'back')
        }

        if ($progress.Percent -lt 100) {
            Update-PnpmBrowseInstallLoadingProgress -Shell $Shell -Progress $progress -TargetPercent 100
        }

        $toolbar = New-ShellSystemToolbarConfig
        $invokeMultiSelect = Get-Command Invoke-ShellMultiSelectList -CommandType Function -ErrorAction Stop
        $picked = & $invokeMultiSelect -Shell $Shell -SectionTitle $sectionTitle `
            -Rows $rows -CacheKey 'PnpmBrowse' `
            -ColumnLayout $columnLayout `
            -ToolbarConfig $toolbar -CountLabel (Get-PnpmBrowseI18n -Key 'pnpm.browse.countUnit') `
            -SearchKeyMode

        if (Test-ShellNavMarker $picked) {
            return $picked
        }
        if ($null -eq $picked -or @($picked).Count -eq 0) {
            return (Get-ShellNavMarker -Action 'back')
        }

        $installResult = Run-PnpmBrowseInstallOperation -Shell $Shell -Items $picked `
            -SectionTitle $PnpmActionSectionTitle
        if (Test-ShellNavMarker $installResult) {
            return $installResult
        }
    }
}

if (-not $script:PnpmBrowseInstallDotSourceOnly) {
    $result = Invoke-PnpmBrowseInstallPage -Shell $ToolkitShell
    if ($standaloneShell) {
        exit 0
    }
    return $result
}
