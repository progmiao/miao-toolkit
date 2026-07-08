# Shell 列表 — 异步加载进度过渡（列表 Body 区域）

function Import-ToolkitShellListLoadCore {
    param([string]$CoreLib)

    if (-not (Get-Command Resolve-DepOperationFn -ErrorAction SilentlyContinue)) {
        $batchPath = Join-Path $CoreLib 'ui\shell\BatchExecution.ps1'
        if (Test-Path -LiteralPath $batchPath) {
            . $batchPath
        }
        $depViewPath = Join-Path $CoreLib 'ui\shell\DepOperationView.ps1'
        if (Test-Path -LiteralPath $depViewPath) {
            . $depViewPath
        }
    }
}

function Get-ToolkitShellListLoadStatusKeyForPercent {
    param([int]$Percent)

    if ($Percent -ge 100) { return 'common.list.loadingDraw' }
    if ($Percent -ge 80) { return 'common.list.loadingResult' }
    return 'common.list.loadingFetch'
}

function Get-ToolkitShellListLoadStatusText {
    param(
        [string]$Spinner,
        [string]$StatusKey = 'common.list.loadingFetch'
    )

    return (Get-I18n -Key $StatusKey -Vars @{ spinner = $Spinner })
}

function Write-ToolkitShellListLoadingView {
    param(
        [hashtable]$Shell,
        [string]$Spinner,
        [int]$Percent = 0,
        [string]$StatusKey = 'common.list.loadingFetch'
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
    $statusText = Get-ToolkitShellListLoadStatusText -Spinner $Spinner -StatusKey $StatusKey
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

function Show-ToolkitShellListLoadingFrame {
    param(
        [hashtable]$Shell,
        [string]$SectionTitle,
        [string]$Spinner = '|',
        [int]$Percent = 0,
        [string]$StatusKey = 'common.list.loadingFetch'
    )

    Initialize-ToolkitShellBodyView -Shell $Shell -SectionTitle $SectionTitle -FooterTemplate SystemToolbarOnly
    Write-ToolkitShellListLoadingView -Shell $Shell -Spinner $Spinner -Percent $Percent -StatusKey $StatusKey
    $toolbar = New-ShellSystemToolbarConfig
    Write-ToolkitShellFooter -Shell $Shell -Template SystemToolbarOnly -ToolbarConfig $toolbar
    Finalize-ToolkitShellBodyView -Shell $Shell
}

function Update-ToolkitShellListLoadingProgress {
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
    $statusKey = Get-ToolkitShellListLoadStatusKeyForPercent -Percent $Progress.Percent
    Write-ToolkitShellListLoadingView -Shell $Shell -Spinner $spinner -Percent $Progress.Percent `
        -StatusKey $statusKey
}

function Start-ToolkitShellListLoadJob {
    param([scriptblock]$FetchJob)

    $job = Start-Job -ScriptBlock $FetchJob
    return @{ Job = $job }
}

function Stop-ToolkitShellListLoadJob {
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

function Test-ToolkitShellListLoadJobRunning {
    param($Fetch)

    return ($Fetch -and $Fetch.Job -and $Fetch.Job.State -eq 'Running')
}

function Complete-ToolkitShellListLoadJob {
    param($Fetch)

    if (-not $Fetch -or -not $Fetch.Job) { return $null }

    try {
        return (Receive-Job -Job $Fetch.Job -ErrorAction Stop)
    }
    finally {
        Remove-Job -Job $Fetch.Job -Force -ErrorAction SilentlyContinue
    }
}

function Wait-ToolkitShellListLoad {
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
    Show-ToolkitShellListLoadingFrame -Shell $Shell -SectionTitle $SectionTitle `
        -Spinner '|' -Percent 0 -StatusKey 'common.list.loadingFetch'

    while ($true) {
        if ($Shell.ExitMode) {
            if (Test-ConsoleKeyAvailable) {
                $key = Read-ShellSystemToolbarKey -Shell $Shell -ToolbarConfig $toolbar
                if ($key -eq 'exitCancel' -or $key -eq 'exitConfirm') { continue }
                if ($key -eq 'exitConfirmed') {
                    Stop-ToolkitShellListLoadJob -Fetch $Fetch
                    return @{ Nav = (Get-ShellNavMarker -Action 'quit'); Data = $null; Error = $null }
                }
                if (Test-ShellNavMarker $key) {
                    Stop-ToolkitShellListLoadJob -Fetch $Fetch
                    return @{ Nav = $key; Data = $null; Error = $null }
                }
            }
            Start-Sleep -Milliseconds 120
            continue
        }

        if (-not (Test-ToolkitShellListLoadJobRunning -Fetch $Fetch)) {
            break
        }

        $fetchCap = 55
        if ($progress.Percent -lt $fetchCap) {
            Update-ToolkitShellListLoadingProgress -Shell $Shell -Progress $progress `
                -TargetPercent ([Math]::Min($fetchCap, $progress.Percent + 2))
        }
        else {
            Update-ToolkitShellListLoadingProgress -Shell $Shell -Progress $progress -TargetPercent $fetchCap
        }

        if (Test-ToolkitShellToolbarLocked -Shell $Shell) {
            Drain-ShellLockedToolbarKeys -Shell $Shell
        }

        if (Test-ConsoleKeyAvailable) {
            $key = Read-ShellSystemToolbarKey -Shell $Shell -ToolbarConfig $toolbar
            if ($key -eq 'exitCancel' -or $key -eq 'exitConfirm') { continue }
            if ($key -eq 'exitConfirmed') {
                Stop-ToolkitShellListLoadJob -Fetch $Fetch
                Set-ToolkitShellToolbarLocked -Shell $Shell -Locked $false
                return @{ Nav = (Get-ShellNavMarker -Action 'quit'); Data = $null; Error = $null }
            }
            if (Test-ShellNavMarker $key) {
                Stop-ToolkitShellListLoadJob -Fetch $Fetch
                Set-ToolkitShellToolbarLocked -Shell $Shell -Locked $false
                return @{ Nav = $key; Data = $null; Error = $null }
            }
        }

        Start-Sleep -Milliseconds 120
    }

    try {
        $data = Complete-ToolkitShellListLoadJob -Fetch $Fetch
        if ($progress.Percent -lt 55) {
            Update-ToolkitShellListLoadingProgress -Shell $Shell -Progress $progress -TargetPercent 55
        }
        Set-ToolkitShellToolbarLocked -Shell $Shell -Locked $false
        return @{ Nav = $null; Data = $data; Error = $null; Progress = $progress }
    }
    catch {
        Set-ToolkitShellToolbarLocked -Shell $Shell -Locked $false
        return @{ Nav = $null; Data = $null; Error = $_; Progress = $progress }
    }
}

function Invoke-ToolkitShellListLoad {
    param(
        [hashtable]$Shell,
        [string]$SectionTitle,
        [scriptblock]$FetchJob,
        [string]$CoreLib = ''
    )

    if ([string]::IsNullOrWhiteSpace($CoreLib)) {
        $CoreLib = Join-Path $PSScriptRoot '..\..\..'
        if (-not (Test-Path (Join-Path $CoreLib 'config\Paths.ps1'))) {
            $CoreLib = $global:MiaoCoreLibDir
        }
    }

    Import-ToolkitShellListLoadCore -CoreLib $CoreLib
    $fetch = Start-ToolkitShellListLoadJob -FetchJob $FetchJob
    return (Wait-ToolkitShellListLoad -Shell $Shell -SectionTitle $SectionTitle -Fetch $fetch)
}
