# node — 浏览并安装（Shell 多选版本列表）

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

function Import-NodeBrowseInstallCore {
    if (-not (Get-Command Initialize-PathsFromToolRoot -ErrorAction SilentlyContinue)) {
        . (Join-Path $coreLib 'config\Paths.ps1')
        . (Join-Path $coreLib 'config\ListLayout.ps1')
        . (Join-Path $coreLib 'config\UserConfig.ps1')
        . (Join-Path $coreLib 'config\I18n.ps1')
    }

    # 子脚本 (&) 内须本地 dot-source：global 只有 Invoke 等副本，缺 Show/Handlers 等配套函数
    . (Join-Path $coreLib 'ui\console\Console-Menu.ps1')
    . (Join-Path $coreLib 'ui\shell\Nav.ps1')
    . (Join-Path $coreLib 'ui\shell\SystemToolbar.ps1')
    . (Join-Path $coreLib 'ui\shell\SingleSelectList.ps1')
    . (Join-Path $coreLib 'ui\shell\MultiSelectList.ps1')
    . (Join-Path $coreLib 'ui\shell\Draw.ps1')
    . (Join-Path $coreLib 'ui\shell\Layout.ps1')
    . (Join-Path $coreLib 'ui\shell\Header.ps1')
    . (Join-Path $coreLib 'ui\shell\Title.ps1')
    . (Join-Path $coreLib 'ui\shell\Exit.ps1')
    . (Join-Path $coreLib 'ui\shell\Footer.ps1')

    if (-not (Get-Command Draw-ToolkitDepOperationView -ErrorAction SilentlyContinue)) {
        . (Join-Path $coreLib 'ui\shell\DepOperationView.ps1')
    }
}

Import-NodeBrowseInstallCore
. (Join-Path $PSScriptRoot 'node-action-title.ps1')
Import-NodeActionTitleCore -CoreLib $coreLib
. (Join-Path $PSScriptRoot 'volta-node.ps1')
Set-NodeVoltaToolRoot -ToolRoot $toolRoot
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

if (-not $script:NodeBrowseInstallDotSourceOnly) {
    $nodeToolAction = Resolve-NodeToolAction -ToolRoot $toolRoot -Action $Action -ScriptLeaf 'browse-install.ps1'
    $nodeActionSectionTitle = Get-NodeActionSectionTitle -ToolRoot $toolRoot -Action $nodeToolAction `
        -ScriptLeaf 'browse-install.ps1'
    $script:NodeActionSectionTitle = $nodeActionSectionTitle
}

function Get-NodeBrowseI18n {
    param(
        [string]$Key,
        [hashtable]$Vars = @{}
    )

    return Get-ToolI18n -ToolRoot $toolRoot -Key $Key -Vars $Vars
}

function Get-NodeBrowseInstallVersionLabel {
    param(
        $Item,
        [hashtable]$InstalledMap,
        [string]$DefaultVersion,
        [string]$ActiveVersion
    )

    return (Format-NodeVersionMenuLabel -Item $Item -InstalledMap $InstalledMap `
        -DefaultVersion $DefaultVersion -ActiveVersion $ActiveVersion)
}

function Get-NodeBrowseInstallTagsLabel {
    param(
        $Item,
        [hashtable]$InstalledMap,
        [string]$DefaultVersion,
        [string]$ActiveVersion
    )

    return (Get-NodeVersionStatusTags -Item $Item -InstalledMap $InstalledMap `
        -DefaultVersion $DefaultVersion -ActiveVersion $ActiveVersion)
}

function Build-NodeBrowseInstallRows {
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
            (Get-NodeBrowseInstallTagsLabel -Item $Item -InstalledMap $InstalledMap `
                -DefaultVersion $DefaultVersion -ActiveVersion $ActiveVersion)
        )
    } -GetEnabled {
        param($Item, [int]$Index)
        $version = Normalize-NodeVersionLabel -Version ([string]$Item.Version)
        -not $InstalledMap.ContainsKey($version)
    }
}

function Resolve-NodeBrowseInstallTagsColumnWidth {
    param([hashtable]$Shell)

    $metrics = Get-ToolkitShellContentMetrics -Shell $Shell
    $versionKeyWidth = Get-ShellMultiSelectSearchKeyWidth
    $gap = Get-MenuColumnGap
    $prefixReserve = 2 + 3 + 1 + $versionKeyWidth + $gap
    $remaining = [int]$metrics.EndColumn - $prefixReserve
    $maxTags = 26
    return [Math]::Max(10, [Math]::Min($maxTags, $remaining))
}

function Get-NodeBrowseListLineIndent {
    # 与多选列表行前缀左缘一致（" $mark $check …"）
    return ' '
}

function Format-NodeBrowseListLine {
    param([string]$Text)

    return (Get-NodeBrowseListLineIndent) + $Text
}

function Get-NodeBrowseInstallLoadingStatusText {
    param(
        [string]$Spinner,
        [string]$StatusKey = 'node.browse.loading'
    )

    return (Get-NodeBrowseI18n -Key $StatusKey -Vars @{
        spinner = $Spinner
    })
}

function Write-NodeBrowseInstallLoadingView {
    param(
        [hashtable]$Shell,
        [string]$Spinner,
        [int]$Percent = 0,
        [string]$StatusKey = 'node.browse.loadingFetch'
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
    $statusText = Get-NodeBrowseInstallLoadingStatusText -Spinner $Spinner -StatusKey $StatusKey
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
    if ((Get-ConsoleViewportTop) -gt 0) {
        $null = Sync-ConsoleViewportTop
    }
}

function Show-NodeBrowseInstallLoadingFrame {
    param(
        [hashtable]$Shell,
        [string]$SectionTitle,
        [string]$Spinner = '|',
        [int]$Percent = 0,
        [string]$StatusKey = 'node.browse.loadingFetch'
    )

    Initialize-ToolkitShellBodyView -Shell $Shell -SectionTitle $SectionTitle -FooterTemplate SystemToolbarOnly
    Write-NodeBrowseInstallLoadingView -Shell $Shell -Spinner $Spinner -Percent $Percent -StatusKey $StatusKey
    $toolbar = New-ShellSystemToolbarConfig
    Write-ToolkitShellFooter -Shell $Shell -Template SystemToolbarOnly -ToolbarConfig $toolbar
    Finalize-ToolkitShellBodyView -Shell $Shell
}

function Get-NodeBrowseInstallLoadingStatusKeyForPercent {
    param([int]$Percent)

    if ($Percent -ge 100) { return 'node.browse.loadingDraw' }
    if ($Percent -ge 80) { return 'node.browse.loadingResult' }
    if ($Percent -ge 55) { return 'node.browse.loadingCompute' }
    return 'node.browse.loadingFetch'
}

function Update-NodeBrowseInstallLoadingProgress {
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
    $statusKey = Get-NodeBrowseInstallLoadingStatusKeyForPercent -Percent $Progress.Percent
    Write-NodeBrowseInstallLoadingView -Shell $Shell -Spinner $spinner -Percent $Progress.Percent `
        -StatusKey $statusKey
}

function Complete-NodeBrowseInstallLoadingProgress {
    param(
        [hashtable]$Shell,
        [hashtable]$Progress,
        [array]$Targets
    )

    foreach ($target in $Targets) {
        Update-NodeBrowseInstallLoadingProgress -Shell $Shell -Progress $Progress -TargetPercent $target
    }
}

function Build-NodeBrowseInstallBaseVersions {
    param([array]$Remote)

    $seen = @{}
    $baseVersions = @()
    foreach ($r in $Remote) {
        $ver = Normalize-NodeVersionLabel -Version ([string]$r.Version)
        if (-not $seen[$ver]) {
            $baseVersions += $r
            $seen[$ver] = $true
        }
    }
    return $baseVersions
}

function Build-NodeBrowseInstallMergedItems {
    param(
        [array]$BaseVersions,
        [hashtable]$VoltaInfo
    )

    $items = [System.Collections.Generic.List[object]]::new()
    $seen = @{}
    foreach ($r in $BaseVersions) {
        $ver = Normalize-NodeVersionLabel -Version ([string]$r.Version)
        if (-not $seen[$ver]) {
            $items.Add($r)
            $seen[$ver] = $true
        }
    }
    foreach ($ver in $VoltaInfo.Map.Keys) {
        if (-not $seen[$ver]) {
            $items.Add((New-NodeVersionMenuItem -Version $ver))
            $seen[$ver] = $true
        }
    }
    return @($items.ToArray())
}

function Prepare-NodeBrowseInstallListContent {
    param(
        [hashtable]$Shell,
        [hashtable]$Progress,
        [array]$Remote
    )

    Update-NodeBrowseInstallLoadingProgress -Shell $Shell -Progress $Progress -TargetPercent 60
    $baseVersions = Build-NodeBrowseInstallBaseVersions -Remote $Remote

    Update-NodeBrowseInstallLoadingProgress -Shell $Shell -Progress $Progress -TargetPercent 70
    $voltaInfo = Get-VoltaNodeVersionInfo
    $activeVersion = Get-ActiveNodeVersion

    Update-NodeBrowseInstallLoadingProgress -Shell $Shell -Progress $Progress -TargetPercent 85
    $merged = Build-NodeBrowseInstallMergedItems -BaseVersions $baseVersions -VoltaInfo $voltaInfo
    $sorted = Sort-NodeVersionItems -Items $merged

    Update-NodeBrowseInstallLoadingProgress -Shell $Shell -Progress $Progress -TargetPercent 95
    $tagsWidth = Resolve-NodeBrowseInstallTagsColumnWidth -Shell $Shell
    $rows = Build-NodeBrowseInstallRows -Items $sorted -InstalledMap $voltaInfo.Map `
        -DefaultVersion $voltaInfo.Default -ActiveVersion $activeVersion
    $columnLayout = New-ShellListColumnLayout -Widths @($tagsWidth)

    Clear-ShellMultiSelectListCache -Shell $Shell -CacheKey 'NodeBrowse'
    Initialize-ShellMultiSelectListDependencies
    $normalized = @(Normalize-ShellListRows -Rows $rows -ColumnLayout $columnLayout)
    $null = Get-ShellMultiSelectListRowCache -Shell $Shell -CacheKey 'NodeBrowse' `
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

function Start-NodeBrowseRemoteVersionsFetch {
    param([switch]$LtsOnly)

    $job = Start-Job -ArgumentList @([bool]$LtsOnly) -ScriptBlock {
        param([bool]$LtsOnlyFlag)

        $ErrorActionPreference = 'Stop'
        $releases = Invoke-RestMethod 'https://nodejs.org/dist/index.json'
        if ($LtsOnlyFlag) {
            $releases = @($releases | Where-Object { $_.lts -ne $false })
        }

        return @($releases | ForEach-Object {
                [PSCustomObject]@{
                    Version = ($_.version -replace '^v', '')
                    Lts     = $_.lts
                    Date    = $_.date
                }
            })
    }

    return @{ Job = $job }
}

function Complete-NodeBrowseRemoteVersionsFetch {
    param($Fetch)

    if (-not $Fetch -or -not $Fetch.Job) { return $null }

    try {
        $result = Receive-Job -Job $Fetch.Job -ErrorAction Stop
        return @($result)
    }
    finally {
        Remove-Job -Job $Fetch.Job -Force -ErrorAction SilentlyContinue
    }
}

function Stop-NodeBrowseRemoteVersionsFetch {
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

function Test-NodeBrowseRemoteVersionsFetchRunning {
    param($Fetch)

    return ($Fetch -and $Fetch.Job -and $Fetch.Job.State -eq 'Running')
}

function Wait-NodeBrowseRemoteVersionsLoad {
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
    Show-NodeBrowseInstallLoadingFrame -Shell $Shell -SectionTitle $SectionTitle `
        -Spinner '|' -Percent 0 -StatusKey 'node.browse.loadingFetch'

    while ($true) {
        if ($Shell.ExitMode) {
            if (Test-ConsoleKeyAvailable) {
                $key = Read-ShellSystemToolbarKey -Shell $Shell -ToolbarConfig $toolbar
                if ($key -eq 'exitCancel' -or $key -eq 'exitConfirm') { continue }
                if ($key -eq 'exitConfirmed') {
                    Stop-NodeBrowseRemoteVersionsFetch -Fetch $Fetch
                    return @{ Nav = (Get-ShellNavMarker -Action 'quit'); Remote = $null; Error = $null }
                }
                if (Test-ShellNavMarker $key) {
                    Stop-NodeBrowseRemoteVersionsFetch -Fetch $Fetch
                    return @{ Nav = $key; Remote = $null; Error = $null }
                }
            }
            Start-Sleep -Milliseconds 120
            continue
        }

        if (-not (Test-NodeBrowseRemoteVersionsFetchRunning -Fetch $Fetch)) {
            break
        }

        $fetchCap = 55
        if ($progress.Percent -lt $fetchCap) {
            $nextPercent = [Math]::Min($fetchCap, $progress.Percent + 2)
            Update-NodeBrowseInstallLoadingProgress -Shell $Shell -Progress $progress -TargetPercent $nextPercent
        }
        else {
            Update-NodeBrowseInstallLoadingProgress -Shell $Shell -Progress $progress -TargetPercent $fetchCap
        }

        if (Test-ToolkitShellToolbarLocked -Shell $Shell) {
            Drain-ShellLockedToolbarKeys -Shell $Shell
        }

        if (Test-ConsoleKeyAvailable) {
            $key = Read-ShellSystemToolbarKey -Shell $Shell -ToolbarConfig $toolbar
            if ($key -eq 'exitCancel' -or $key -eq 'exitConfirm') { continue }
            if ($key -eq 'exitConfirmed') {
                Stop-NodeBrowseRemoteVersionsFetch -Fetch $Fetch
                Set-ToolkitShellToolbarLocked -Shell $Shell -Locked $false
                return @{ Nav = (Get-ShellNavMarker -Action 'quit'); Remote = $null; Error = $null }
            }
            if (Test-ShellNavMarker $key) {
                Stop-NodeBrowseRemoteVersionsFetch -Fetch $Fetch
                Set-ToolkitShellToolbarLocked -Shell $Shell -Locked $false
                return @{ Nav = $key; Remote = $null; Error = $null }
            }
        }

        Start-Sleep -Milliseconds 120
    }

    try {
        $remote = Complete-NodeBrowseRemoteVersionsFetch -Fetch $Fetch
        if ($progress.Percent -lt 55) {
            Complete-NodeBrowseInstallLoadingProgress -Shell $Shell -Progress $progress -Targets @(55)
        }
        Set-ToolkitShellToolbarLocked -Shell $Shell -Locked $false
        return @{ Nav = $null; Remote = $remote; Error = $null; Progress = $progress }
    }
    catch {
        Set-ToolkitShellToolbarLocked -Shell $Shell -Locked $false
        return @{ Nav = $null; Remote = $null; Error = $_; Progress = $progress }
    }
}

function Invoke-NodeBrowseInstallPage {
    param([hashtable]$Shell)

    $null = Ensure-ToolkitShellLayoutBrandInnerWidth -Shell $Shell

    if (-not (Get-Command volta -ErrorAction SilentlyContinue)) {
        Initialize-ToolkitShellBodyView -Shell $Shell -SectionTitle $nodeActionSectionTitle `
            -FooterTemplate SystemToolbarOnly
        $layout = $Shell.Layout
        Write-FixedLine $layout.ListStartRow (Get-NodeBrowseI18n -Key 'node.browse.voltaMissing') -Color Red
        Start-Sleep -Milliseconds 1200
        return (Get-ShellNavMarker -Action 'back')
    }

    $sectionTitle = $nodeActionSectionTitle
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
        Write-FixedLine $layout.ListStartRow (Get-NodeBrowseI18n -Key 'node.browse.loadFailed') -Color Red
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

    $preparedList = Prepare-NodeBrowseInstallListContent -Shell $Shell -Progress $progress -Remote $remote
    $baseVersions = $preparedList.BaseVersions
    $usePreparedList = $true
    $skipListCacheClear = $true

    while ($true) {
        if ($usePreparedList) {
            $voltaInfo = $preparedList.VoltaInfo
            $activeVersion = $preparedList.ActiveVersion
            $sorted = $preparedList.Sorted
            $rows = $preparedList.Rows
            $tagsWidth = $preparedList.TagsWidth
            $columnLayout = $preparedList.ColumnLayout
            $usePreparedList = $false
        }
        else {
            $voltaInfo = Get-VoltaNodeVersionInfo
            $activeVersion = Get-ActiveNodeVersion

            $merged = Build-NodeBrowseInstallMergedItems -BaseVersions $baseVersions -VoltaInfo $voltaInfo
            $sorted = Sort-NodeVersionItems -Items $merged
            $tagsWidth = Resolve-NodeBrowseInstallTagsColumnWidth -Shell $Shell
            $rows = Build-NodeBrowseInstallRows -Items $sorted -InstalledMap $voltaInfo.Map `
                -DefaultVersion $voltaInfo.Default -ActiveVersion $activeVersion
            $columnLayout = New-ShellListColumnLayout -Widths @($tagsWidth)
        }

        if ($sorted.Count -eq 0) {
            Initialize-ToolkitShellBodyView -Shell $Shell -SectionTitle $sectionTitle -FooterTemplate SystemToolbarOnly
            $layout = $Shell.Layout
            Write-FixedLine $layout.ListStartRow (Get-NodeBrowseI18n -Key 'node.browse.noVersions') -Color Yellow
            Start-Sleep -Milliseconds 900
            return (Get-ShellNavMarker -Action 'back')
        }

        if (-not $skipListCacheClear) {
            Clear-ShellMultiSelectListCache -Shell $Shell -CacheKey 'NodeBrowse'
        }
        $skipListCacheClear = $false

        if ($progress.Percent -lt 100) {
            Update-NodeBrowseInstallLoadingProgress -Shell $Shell -Progress $progress -TargetPercent 100
        }

        $toolbar = New-ShellSystemToolbarConfig
        $invokeMultiSelect = Get-Command Invoke-ShellMultiSelectList -CommandType Function -ErrorAction Stop
        $picked = & $invokeMultiSelect -Shell $Shell -SectionTitle $sectionTitle `
            -Rows $rows -CacheKey 'NodeBrowse' `
            -ColumnLayout $columnLayout `
            -ToolbarConfig $toolbar -CountLabel (Get-NodeBrowseI18n -Key 'node.browse.countUnit') `
            -SearchKeyMode

        if (Test-ShellNavMarker $picked) {
            return $picked
        }
        if ($null -eq $picked -or @($picked).Count -eq 0) {
            return (Get-ShellNavMarker -Action 'back')
        }

        $installResult = Run-NodeBrowseInstallOperation -Shell $Shell -Items $picked `
            -SectionTitle $nodeActionSectionTitle
        if (Test-ShellNavMarker $installResult) {
            return $installResult
        }
    }
}

if (-not $script:NodeBrowseInstallDotSourceOnly) {
    $result = Invoke-NodeBrowseInstallPage -Shell $ToolkitShell
    if ($standaloneShell) {
        exit 0
    }
    return $result
}
