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
}

Import-NodeBrowseInstallCore
. (Join-Path $PSScriptRoot 'volta-node.ps1')
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
        -Fallback '浏览并安装')
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

    $tag = ''
    if ($Item.Version -eq $ActiveVersion) { $tag += ' [当前]' }
    if ($InstalledMap.ContainsKey($Item.Version)) { $tag += ' [已安装]' }
    if ($Item.Version -eq $DefaultVersion) { $tag += ' [默认]' }
    if ($Item.Lts -and $Item.Lts -ne $false) { $tag += " [LTS:$($Item.Lts)]" }
    return $tag
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
        -not $InstalledMap.ContainsKey([string]$Item.Version)
    }
}

function Resolve-NodeBrowseInstallTagsColumnWidth {
    param([hashtable]$Shell)

    $metrics = Get-ToolkitShellContentMetrics -Shell $Shell
    $versionKeyWidth = Get-ShellMultiSelectSearchKeyWidth
    $gap = Get-MenuColumnGap
    $prefixReserve = 2 + 3 + 1 + $versionKeyWidth + $gap
    return [Math]::Max(12, [int]$metrics.EndColumn - $prefixReserve)
}

function Get-NodeBrowseListLineIndent {
    # 与多选列表行前缀左缘一致（" $mark $check …"）
    return ' '
}

function Format-NodeBrowseListLine {
    param([string]$Text)

    return (Get-NodeBrowseListLineIndent) + $Text
}

function Write-NodeBrowseInstallLoadingLine {
    param(
        [hashtable]$Shell,
        [string]$Spinner
    )

    $layout = $Shell.Layout
    $text = Format-NodeBrowseListLine -Text (Get-NodeBrowseI18n -Key 'node.browse.loading' -Vars @{
            spinner = $Spinner
        })
    $row = [int]$layout.ListStartRow
    $useBatch = Test-ShellConsoleBatchDraw
    $enteredBatch = $false
    if ($useBatch) {
        Enter-ConsoleDrawBatch
        $enteredBatch = $true
    }
    Prepare-ConsoleRowWrite -Row $row
    Write-FixedLine $row $text -Color Yellow
    Set-ConsoleCursorAfterRowWrite -Row $row
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
        [string]$Spinner = '|'
    )

    Initialize-ToolkitShellBodyView -Shell $Shell -SectionTitle $SectionTitle -FooterTemplate SystemToolbarOnly
    Write-NodeBrowseInstallLoadingLine -Shell $Shell -Spinner $Spinner
    $layout = $Shell.Layout
    for ($row = 1; $row -lt $layout.ListViewportHeight; $row++) {
        Write-FixedLine ($layout.ListStartRow + $row) '' -Color DarkGray
    }
    $toolbar = New-ShellSystemToolbarConfig
    Write-ToolkitShellFooter -Shell $Shell -Template SystemToolbarOnly -ToolbarConfig $toolbar
    Finalize-ToolkitShellBodyView -Shell $Shell
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

    Show-NodeBrowseInstallLoadingFrame -Shell $Shell -SectionTitle $SectionTitle `
        -Spinner $spinnerFrames[0]

    while ($true) {
        $spinner = $spinnerFrames[$spinnerIndex % $spinnerFrames.Count]
        Write-NodeBrowseInstallLoadingLine -Shell $Shell -Spinner $spinner
        $spinnerIndex++

        if (-not (Test-NodeBrowseRemoteVersionsFetchRunning -Fetch $Fetch)) {
            break
        }

        if (Test-ConsoleKeyAvailable) {
            $key = Read-ShellSystemToolbarKey -Shell $Shell -ToolbarConfig $toolbar
            if ($key -eq 'exitCancel') { continue }
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
    }

    try {
        $remote = Complete-NodeBrowseRemoteVersionsFetch -Fetch $Fetch
        return @{ Nav = $null; Remote = $remote; Error = $null }
    }
    catch {
        return @{ Nav = $null; Remote = $null; Error = $_ }
    }
}

function Show-NodeBrowseInstallSelectionPreview {
    param(
        [hashtable]$Shell,
        [array]$Items
    )

    $sectionTitle = Get-NodeBrowseI18n -Key 'node.browse.selectedTitle' -Vars @{
        count = [string]$Items.Count
    }
    Initialize-ToolkitShellBodyView -Shell $Shell -SectionTitle $sectionTitle -FooterTemplate SystemToolbarOnly
    $layout = $Shell.Layout
    $viewport = [Math]::Max(1, [int]$layout.ListViewportHeight)

    Write-FixedLine $layout.ListStartRow (Get-NodeBrowseI18n -Key 'node.browse.selectedHint') -Color DarkGray
    $row = 1
    foreach ($item in @($Items)) {
        if ($row -ge ($viewport - 1)) { break }
        Write-FixedLine ($layout.ListStartRow + $row) "  $($item.Version)" -Color Gray
        $row++
    }
    for (; $row -lt $viewport; $row++) {
        Write-FixedLine ($layout.ListStartRow + $row) '' -Color DarkGray
    }

    $toolbar = New-ShellSystemToolbarConfig -HideSystem -HideHelp
    $barWidth = Get-ToolkitShellLayoutBarInnerWidth -Shell $Shell
    $lineWidth = Get-BrandSeparatorLineWidth -BrandInnerWidth $barWidth
    $enterHint = Format-I18nPressEnterBack
    Write-MenuBarLine -Row $layout.ToolbarRow -InnerWidth $lineWidth `
        -Segments @($enterHint, '', '', '', '') -ColumnCount 5

    while ($true) {
        $confirm = Read-ShellExitIfActive -Shell $Shell
        if ($confirm -eq 'exitCancel') { continue }
        if ($confirm -eq 'exitConfirmed') {
            return (Get-ShellNavMarker -Action 'quit')
        }

        $key = Read-ShellSystemToolbarKey -Shell $Shell -ToolbarConfig $toolbar -AllowEnter
        if ($key -eq 'enter') {
            return (Get-ShellNavMarker -Action 'back')
        }
        if (Test-ShellNavMarker $key) {
            return $key
        }
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

    $voltaInfo = Get-VoltaNodeVersionInfo
    $activeVersion = Get-ActiveNodeVersion

    $items = [System.Collections.Generic.List[object]]::new()
    $seen = @{}
    foreach ($r in $remote) {
        if (-not $seen[$r.Version]) {
            $items.Add($r)
            $seen[$r.Version] = $true
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

    return Show-NodeBrowseInstallSelectionPreview -Shell $Shell -Items $picked
}

$result = Invoke-NodeBrowseInstallPage -Shell $ToolkitShell
if ($standaloneShell) {
    exit 0
}
return $result
