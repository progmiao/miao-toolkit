# node — 浏览并安装（Shell 多选版本列表）

param(
    [hashtable]$ToolkitShell = $null,

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
. (Join-Path $PSScriptRoot 'volta-node.ps1')
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

function Get-NodeBrowseI18n {
    param(
        [string]$Key,
        [hashtable]$Vars = @{}
    )

    return Get-ToolI18n -ToolRoot $toolRoot -Key $Key -Vars $Vars
}

function Get-NodeBrowseInstallSectionTitle {
    return (Resolve-ToolI18nLabel -ToolRoot $toolRoot -Key 'node.browse.sectionTitle' `
        -Fallback '安装Node.js')
}

function Get-NodeBrowseInstallProgressSectionTitle {
    return (Resolve-ToolI18nLabel -ToolRoot $toolRoot -Key 'node.browse.installPageTitle' `
        -Fallback 'Node.js 安装')
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

function Get-NodeBrowseInstallFetchPercents {
    return @(5, 15, 25, 35)
}

function Step-NodeBrowseInstallLoadingPercent {
    param(
        [hashtable]$Shell,
        [string]$Spinner,
        [int]$FromPercent,
        [int]$ToPercent,
        [string]$StatusKey,
        [int]$Steps = 4,
        [int]$DelayMs = 60
    )

    if ($Steps -le 0) { $Steps = 1 }
    for ($step = 1; $step -le $Steps; $step++) {
        $percent = $FromPercent + [int][Math]::Round(($ToPercent - $FromPercent) * $step / $Steps)
        Write-NodeBrowseInstallLoadingView -Shell $Shell -Spinner $Spinner -Percent $percent -StatusKey $StatusKey
        if ($step -lt $Steps -and $DelayMs -gt 0) {
            Start-Sleep -Milliseconds $DelayMs
        }
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
    $spinnerFrames = @('|', '/', '-', '\')
    $spinnerIndex = 0
    $fetchPercents = Get-NodeBrowseInstallFetchPercents

    Set-ToolkitShellToolbarLocked -Shell $Shell -Locked $true
    Show-NodeBrowseInstallLoadingFrame -Shell $Shell -SectionTitle $SectionTitle `
        -Spinner $spinnerFrames[0] -Percent $fetchPercents[0] -StatusKey 'node.browse.loadingFetch'

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

        $spinner = $spinnerFrames[$spinnerIndex % $spinnerFrames.Count]
        $percent = $fetchPercents[$spinnerIndex % $fetchPercents.Count]
        Write-NodeBrowseInstallLoadingView -Shell $Shell -Spinner $spinner -Percent $percent `
            -StatusKey 'node.browse.loadingFetch'
        $spinnerIndex++

        if (-not (Test-NodeBrowseRemoteVersionsFetchRunning -Fetch $Fetch)) {
            break
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

    $spinner = $spinnerFrames[$spinnerIndex % $spinnerFrames.Count]
    Step-NodeBrowseInstallLoadingPercent -Shell $Shell -Spinner $spinner -FromPercent 40 -ToPercent 55 `
        -StatusKey 'node.browse.loadingCompute' -Steps 3 -DelayMs 50

    try {
        $remote = Complete-NodeBrowseRemoteVersionsFetch -Fetch $Fetch
        $spinner = $spinnerFrames[($spinnerIndex + 1) % $spinnerFrames.Count]
        Step-NodeBrowseInstallLoadingPercent -Shell $Shell -Spinner $spinner -FromPercent 55 -ToPercent 75 `
            -StatusKey 'node.browse.loadingCompute' -Steps 2 -DelayMs 40
        $spinner = $spinnerFrames[($spinnerIndex + 2) % $spinnerFrames.Count]
        Step-NodeBrowseInstallLoadingPercent -Shell $Shell -Spinner $spinner -FromPercent 75 -ToPercent 90 `
            -StatusKey 'node.browse.loadingResult' -Steps 3 -DelayMs 50
        $spinner = $spinnerFrames[($spinnerIndex + 3) % $spinnerFrames.Count]
        Step-NodeBrowseInstallLoadingPercent -Shell $Shell -Spinner $spinner -FromPercent 90 -ToPercent 95 `
            -StatusKey 'node.browse.loadingResult' -Steps 2 -DelayMs 40
        Set-ToolkitShellToolbarLocked -Shell $Shell -Locked $false
        return @{ Nav = $null; Remote = $remote; Error = $null }
    }
    catch {
        Set-ToolkitShellToolbarLocked -Shell $Shell -Locked $false
        return @{ Nav = $null; Remote = $null; Error = $_ }
    }
}

function Invoke-NodeBrowseInstallPage {
    param([hashtable]$Shell)

    $null = Ensure-ToolkitShellLayoutBrandInnerWidth -Shell $Shell

    if (-not (Get-Command volta -ErrorAction SilentlyContinue)) {
        Initialize-ToolkitShellBodyView -Shell $Shell -SectionTitle (Get-NodeBrowseInstallSectionTitle) `
            -FooterTemplate SystemToolbarOnly
        $layout = $Shell.Layout
        Write-FixedLine $layout.ListStartRow (Get-NodeBrowseI18n -Key 'node.browse.voltaMissing') -Color Red
        Start-Sleep -Milliseconds 1200
        return (Get-ShellNavMarker -Action 'back')
    }

    $sectionTitle = Get-NodeBrowseInstallSectionTitle
    $fetch = Start-NodeBrowseRemoteVersionsFetch -LtsOnly:$LtsOnly
    $loadResult = Wait-NodeBrowseRemoteVersionsLoad -Shell $Shell -SectionTitle $sectionTitle -Fetch $fetch
    if ($loadResult.Nav) {
        return $loadResult.Nav
    }

    Write-NodeBrowseInstallLoadingView -Shell $Shell -Spinner '/' -Percent 100 -StatusKey 'node.browse.loadingDraw'
    Start-Sleep -Milliseconds 80

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

    $seen = @{}
    $baseVersions = @()
    foreach ($r in $remote) {
        $ver = Normalize-NodeVersionLabel -Version ([string]$r.Version)
        if (-not $seen[$ver]) {
            $baseVersions += $r
            $seen[$ver] = $true
        }
    }

    while ($true) {
        $voltaInfo = Get-VoltaNodeVersionInfo
        $activeVersion = Get-ActiveNodeVersion

        $items = [System.Collections.Generic.List[object]]::new()
        $seen = @{}
        foreach ($r in $baseVersions) {
            $ver = Normalize-NodeVersionLabel -Version ([string]$r.Version)
            if (-not $seen[$ver]) {
                $items.Add($r)
                $seen[$ver] = $true
            }
        }
        foreach ($ver in $voltaInfo.Map.Keys) {
            if (-not $seen[$ver]) {
                $items.Add((New-NodeVersionMenuItem -Version $ver))
                $seen[$ver] = $true
            }
        }

        $sorted = Sort-NodeVersionItems -Items @($items.ToArray())
        if ($sorted.Count -eq 0) {
            Initialize-ToolkitShellBodyView -Shell $Shell -SectionTitle $sectionTitle -FooterTemplate SystemToolbarOnly
            $layout = $Shell.Layout
            Write-FixedLine $layout.ListStartRow (Get-NodeBrowseI18n -Key 'node.browse.noVersions') -Color Yellow
            Start-Sleep -Milliseconds 900
            return (Get-ShellNavMarker -Action 'back')
        }

        $tagsWidth = Resolve-NodeBrowseInstallTagsColumnWidth -Shell $Shell
        $rows = Build-NodeBrowseInstallRows -Items $sorted -InstalledMap $voltaInfo.Map `
            -DefaultVersion $voltaInfo.Default -ActiveVersion $activeVersion

        Clear-ShellMultiSelectListCache -Shell $Shell -CacheKey 'NodeBrowse'

        $toolbar = New-ShellSystemToolbarConfig
        $invokeMultiSelect = Get-Command Invoke-ShellMultiSelectList -CommandType Function -ErrorAction Stop
        $picked = & $invokeMultiSelect -Shell $Shell -SectionTitle $sectionTitle `
            -Rows $rows -CacheKey 'NodeBrowse' `
            -ColumnLayout (New-ShellListColumnLayout -Widths @($tagsWidth)) `
            -ToolbarConfig $toolbar -CountLabel (Get-NodeBrowseI18n -Key 'node.browse.countUnit') `
            -SearchKeyMode

        if (Test-ShellNavMarker $picked) {
            return $picked
        }
        if ($null -eq $picked -or @($picked).Count -eq 0) {
            return (Get-ShellNavMarker -Action 'back')
        }

        $installResult = Run-NodeBrowseInstallOperation -Shell $Shell -Items $picked
        if (Test-ShellNavMarker $installResult) {
            return $installResult
        }
    }
}

$result = Invoke-NodeBrowseInstallPage -Shell $ToolkitShell
if ($standaloneShell) {
    exit 0
}
return $result
