# node — 浏览并安装：批量安装进度与日志视图

. (Join-Path $PSScriptRoot 'volta-conpty.ps1')

function Get-NodeBrowseInstallCoreLib {
    if ($script:NodeBrowseInstallCoreLib) {
        return $script:NodeBrowseInstallCoreLib
    }
    if ($coreLib) {
        return [string]$coreLib
    }

    $toolRoot = Split-Path $PSScriptRoot -Parent
    $script:NodeBrowseInstallCoreLib = (Join-Path $toolRoot '..\..\core\lib')
    return $script:NodeBrowseInstallCoreLib
}

function Ensure-NodeBrowseInstallShellUi {
    $coreLib = Get-NodeBrowseInstallCoreLib

    foreach ($rel in @(
            'ui\shell\SystemToolbar.ps1'
            'ui\shell\Exit.ps1'
            'ui\shell\Footer.ps1'
            'ui\shell\DepOperationView.ps1'
            'domain\Invoke-ToolDepPackage.ps1'
        )) {
        $path = Join-Path $coreLib $rel
        $name = [IO.Path]::GetFileNameWithoutExtension($rel)
        if ($name -eq 'Invoke-ToolDepPackage') {
            if (Get-Command Get-WingetStreamLineCleanText -ErrorAction SilentlyContinue) { continue }
        }
        elseif ($name -eq 'DepOperationView') {
            if (Get-Command Draw-ToolkitDepOperationView -ErrorAction SilentlyContinue) { continue }
        }
        elseif ($name -eq 'Footer') {
            if (Get-Command Invoke-ToolkitShellRegisteredFooter -ErrorAction SilentlyContinue) { continue }
        }
        elseif ($name -eq 'Exit') {
            if (Get-Command Write-ShellExitFooter -ErrorAction SilentlyContinue) { continue }
        }
        elseif ($name -eq 'SystemToolbar') {
            if (Get-Command Set-ToolkitShellToolbarLocked -ErrorAction SilentlyContinue) { continue }
        }
        . $path
    }

    $batchOpPath = Join-Path $coreLib 'ui\shell\ToolkitDepBatchOperation.ps1'
    if (-not (Get-Command Initialize-ToolkitDepBatchOperationView -ErrorAction SilentlyContinue)) {
        . $batchOpPath
    }
}

function Ensure-NodeBrowseInstallDepView {
    Ensure-NodeBrowseInstallShellUi
}

function New-NodeBrowseInstallLog {
    param(
        [int]$ViewportRows = 0,
        [int]$BrandInnerWidth = 0
    )

    return [pscustomobject]@{
        Lines           = [System.Collections.Generic.List[object]]::new()
        AutoScroll      = $true
        ScrollOffset    = 0
        ViewportRows    = $ViewportRows
        BrandInnerWidth = $BrandInnerWidth
    }
}

function Write-NodeBrowseInstallLogLine {
    param(
        $Log,
        [string]$Text,
        [string]$Kind = 'text',
        [switch]$WithTimestamp
    )

    if ($null -eq $Log -or $null -eq $Log.Lines) { return }

    $lineColor = [System.ConsoleColor]::Gray
    switch ($Kind) {
        'section' { $lineColor = [System.ConsoleColor]::Cyan }
        'success' { $lineColor = [System.ConsoleColor]::Green }
        'error' { $lineColor = [System.ConsoleColor]::Red }
        'heading' { $lineColor = [System.ConsoleColor]::White }
        'separator' { $lineColor = [System.ConsoleColor]::DarkGray }
        'hint' { $lineColor = [System.ConsoleColor]::DarkGray }
    }

    $brandInnerWidth = [int]$Log.BrandInnerWidth
    $timeWidth = 8
    if (Get-Command Get-ToolkitDepLogWrapWidth -ErrorAction SilentlyContinue) {
        $wrapWidth = if ($Kind -ne 'separator' -and $brandInnerWidth -gt 0) {
            Get-ToolkitDepLogWrapWidth -Kind $Kind -BrandInnerWidth $brandInnerWidth -TimeWidth $timeWidth
        }
        else { 0 }
    }
    else {
        $wrapWidth = if ($Kind -notin @('separator', 'spacer') -and $brandInnerWidth -gt 0) {
            [Math]::Max(8, $brandInnerWidth - $timeWidth - 2)
        }
        else { 0 }
    }

    $textLines = @([string]$Text)
    if ($wrapWidth -gt 0 -and -not [string]::IsNullOrEmpty($Text)) {
        if (Get-Command Split-DisplayTextToLines -ErrorAction SilentlyContinue) {
            $textLines = @(Split-DisplayTextToLines -Text $Text -MaxWidth $wrapWidth)
        }
    }

    $isFirst = $true
    foreach ($textLine in $textLines) {
        $timestamp = if ($WithTimestamp -and $isFirst) { (Get-Date).ToString('HH:mm:ss') } else { '' }
        $Log.Lines.Add([pscustomobject]@{
            Timestamp = $timestamp
            Text      = [string]$textLine
            Kind      = $Kind
            Color     = $lineColor
        }) | Out-Null
        $isFirst = $false
    }

    $maxLines = 500
    while ($Log.Lines.Count -gt $maxLines) {
        if ($Log.Lines.Count -le 0) { break }
        $Log.Lines.RemoveAt(0)
        if ($Log.ScrollOffset -gt 0) { $Log.ScrollOffset-- }
    }

    if ($Log.AutoScroll -and [int]$Log.ViewportRows -gt 0) {
        $Log.ScrollOffset = [Math]::Max(0, $Log.Lines.Count - [int]$Log.ViewportRows)
    }
}

function New-NodeBrowseInstallLoadingState {
    if (Get-Command New-ToolkitDepOperationLoadingState -ErrorAction SilentlyContinue) {
        return New-ToolkitDepOperationLoadingState
    }

    return @{
        SpinnerFrames    = @('|', '/', '-', '\')
        SpinnerIndex     = 0
        OutputSeen       = $false
        LastOutputTick   = 0
    }
}

function Update-NodeBrowseInstallLoadingStatus {
    param(
        $Ui,
        $LoadingState,
        [string]$Version
    )

    if (-not $Ui.ItemInFlight) { return }

    $phase = [string]$LoadingState['InstallPhase']
    if ([string]::IsNullOrWhiteSpace($phase) -and $Ui.TaskPhase) {
        $phase = [string]$Ui.TaskPhase
    }
    if ([string]::IsNullOrWhiteSpace($phase) -and $Ui.InstallPhase) {
        $phase = [string]$Ui.InstallPhase
    }

    $key = switch ($phase) {
        'downloading' { 'node.browse.installStatusDownloading' }
        'unpacking' { 'node.browse.installStatusInstalling' }
        default {
            if ($LoadingState['OutputSeen']) {
                'node.browse.installStatusWorking'
            }
            else {
                'node.browse.installStatusStarting'
            }
        }
    }

    $mainText = Get-NodeBrowseI18n -Key $key -Vars @{
        spinner = '{spinner}'
        version = $Version
    }
    Update-ToolkitDepOperationSpinnerStatus -Ui $Ui -LoadingState $LoadingState -MainText $mainText
}

function Sync-NodeBrowseInstallLoadingPhase {
    param(
        $LoadingState,
        $Ui,
        [string]$Phase,
        [hashtable]$OutputState = $null,
        $Watch = $null
    )

    $resolved = [string]$Phase
    if ([string]::IsNullOrWhiteSpace($resolved) -and $OutputState -and $OutputState.VoltaPhase) {
        $resolved = [string]$OutputState.VoltaPhase
    }
    if ([string]::IsNullOrWhiteSpace($resolved) -and $Watch -and $Watch.Phase) {
        $resolved = [string]$Watch.Phase
    }
    if ([string]::IsNullOrWhiteSpace($resolved)) { return }

    $LoadingState['InstallPhase'] = $resolved
    $LoadingState['TaskPhase'] = $resolved
    if ($Ui) {
        $Ui.InstallPhase = $resolved
        $Ui.TaskPhase = $resolved
    }
}

function Start-NodeVoltaInstallProcess {
    param([string]$Version)

    $voltaCmd = Get-Command volta -ErrorAction Stop
    $target = "node@$Version"
    $commandLine = "volta install --verbose `"$target`""
    $arguments = "install --verbose `"$target`""

    # Volta re-spawns itself on Windows; ConPTY only captures the parent shell and
    # never receives indicatif progress output. Use redirect + --verbose instead.
    $queue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $voltaCmd.Source
    $psi.Arguments = $arguments
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi

    $enqueueLine = {
        if ($EventArgs.Data) {
            $Event.MessageData.Enqueue([string]$EventArgs.Data)
        }
    }.GetNewClosure()

    $stdoutSub = Register-ObjectEvent -InputObject $proc -EventName OutputDataReceived `
        -Action $enqueueLine -MessageData $queue
    $stderrSub = Register-ObjectEvent -InputObject $proc -EventName ErrorDataReceived `
        -Action $enqueueLine -MessageData $queue

    if (-not $proc.Start()) {
        Unregister-Event -SourceIdentifier $stdoutSub.Name -ErrorAction SilentlyContinue
        Unregister-Event -SourceIdentifier $stderrSub.Name -ErrorAction SilentlyContinue
        throw 'Failed to start volta install'
    }

    $proc.BeginOutputReadLine()
    $proc.BeginErrorReadLine()

    return @{
        Mode          = 'redirect'
        Process       = $proc
        Queue         = $queue
        Subscriptions = @($stdoutSub, $stderrSub)
        CommandLine   = $commandLine
    }
}

function Complete-NodeVoltaInstallProcess {
    param($State)

    return (Complete-NodeVoltaInstallProcessState -State $State)
}

function Stop-NodeVoltaInstallProcess {
    param($State)

    return (Stop-NodeVoltaInstallProcessState -State $State)
}

function Drain-NodeVoltaInstallQueue {
    param(
        $State,
        $Log,
        $LoadingState,
        $Redraw,
        $Ui = $null,
        [hashtable]$OutputState = $null
    )

    if (-not $State -or -not $State.Queue) { return $false }

    $line = $null
    $changed = $false
    while ($State.Queue.TryDequeue([ref]$line)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        if ($null -ne $Ui -and $null -ne $OutputState) {
            $null = Update-NodeVoltaInstallOutputLine -Line $line -Ui $Ui -LoadingState $LoadingState `
                -OutputState $OutputState -Log $Log -Redraw $Redraw
        }
        else {
            $LoadingState['OutputSeen'] = $true
            $LoadingState['LastOutputTick'] = [Environment]::TickCount
            if ($null -ne $LoadingState -and $null -ne $LoadingState['OutputLines']) {
                $LoadingState['OutputLines'].Add([string]$line) | Out-Null
            }
            Write-NodeBrowseInstallLogLine -Log $Log -Text $line
            Invoke-NodeVoltaInstallRedraw -Redraw $Redraw
        }

        $changed = $true
        $line = $null
    }
    return $changed
}

function Wait-NodeVoltaInstallProcess {
    param(
        $State,
        $Ui,
        $LoadingState,
        [string]$Version,
        [hashtable]$Shell,
        $Log,
        [int]$LogViewportRows,
        $OnExitKey,
        [hashtable]$ScrollState,
        $FnLogInput,
        $Redraw
    )

    $pollState = @{
        LastFrameTick   = 0
        FrameIntervalMs = 80
        LastWatchTick   = 0
        WatchInterval   = 150
    }
    $outputState = @{
        LoggedSuccess     = $false
        VoltaPhase        = ''
        MinUnpackPercent  = 0
    }
    $progressWatch = New-VoltaNodeInstallProgressWatch -Version $Version -StartTick $Ui.ExecuteStartTick

    while (-not (Test-NodeVoltaInstallProcessExited -State $State)) {
        Drain-NodeVoltaInstallQueue -State $State -Log $Log -LoadingState $LoadingState -Redraw $Redraw `
            -Ui $Ui -OutputState $outputState

        $now = [Environment]::TickCount
        if (($now - $pollState.LastWatchTick) -ge $pollState.WatchInterval) {
            Update-NodeVoltaInstallProgressFromWatch -Ui $Ui -Watch $progressWatch -Redraw $Redraw `
                -Version $Version -NowTick $now -LoadingState $LoadingState | Out-Null
            $pollState.LastWatchTick = $now
        }

        Sync-NodeBrowseInstallLoadingPhase -LoadingState $LoadingState -Ui $Ui `
            -OutputState $outputState -Watch $progressWatch

        if (($now - $pollState.LastFrameTick) -ge $pollState.FrameIntervalMs) {
            Update-NodeBrowseInstallLoadingStatus -Ui $Ui -LoadingState $LoadingState -Version $Version
            Invoke-NodeVoltaInstallRedraw -Redraw $Redraw
            $pollState.LastFrameTick = $now
        }

        if (Test-ToolkitShellToolbarLocked -Shell $Shell) {
            Drain-ShellLockedToolbarKeys -Shell $Shell -AllowLogScroll
        }

        $inputResult = & $FnLogInput -Shell $Shell -Log $Log -ViewportRows $LogViewportRows `
            -OnExitKey $OnExitKey -ScrollState $ScrollState
        if ($inputResult -eq 'scroll') {
            Invoke-NodeVoltaInstallRedraw -Redraw $Redraw
        }

        Start-Sleep -Milliseconds 30
    }

    if ($State.Mode -eq 'redirect' -and $State.Process) {
        $State.Process.WaitForExit()
        Start-Sleep -Milliseconds 80
    }
    Drain-NodeVoltaInstallQueue -State $State -Log $Log -LoadingState $LoadingState -Redraw $Redraw `
        -Ui $Ui -OutputState $outputState
    Update-NodeVoltaInstallProgressFromWatch -Ui $Ui -Watch $progressWatch -Redraw $Redraw `
        -Version $Version -LoadingState $LoadingState | Out-Null
    Sync-NodeBrowseInstallLoadingPhase -LoadingState $LoadingState -Ui $Ui `
        -OutputState $outputState -Watch $progressWatch
    if ([int]$Ui.ItemSubPercent -lt 100) {
        Set-NodeVoltaInstallProgressPercent -Ui $Ui -Percent 100 -Version $Version | Out-Null
        Update-NodeBrowseInstallLoadingStatus -Ui $Ui -LoadingState $LoadingState -Version $Version
        Invoke-NodeVoltaInstallRedraw -Redraw $Redraw
    }
    return (Complete-NodeVoltaInstallProcess -State $State)
}

function Run-NodeBrowseInstallOperation {
    param(
        [hashtable]$Shell,
        [array]$Items,
        [string]$SectionTitle = ''
    )

    Ensure-NodeBrowseInstallShellUi

    $versions = @((Ensure-StringArray -Value @($Items | ForEach-Object {
        if ($_.Version) { Normalize-NodeVersionLabel -Version ([string]$_.Version) }
        elseif ($_.Source -and $_.Source.Version) { Normalize-NodeVersionLabel -Version ([string]$_.Source.Version) }
        else { '' }
    } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })))
    $total = $versions.Count
    if ($total -le 0) {
        return $null
    }

    $sectionTitle = if (-not [string]::IsNullOrWhiteSpace($SectionTitle)) {
        $SectionTitle
    }
    else {
        $script:NodeActionSectionTitle
    }
    $ctx = Initialize-ToolkitDepBatchOperationView -Shell $Shell -SectionTitle $sectionTitle `
        -ProgressTotal $total -ReadyStatusText (Get-NodeBrowseI18n -Key 'node.browse.installStatusReady')

    $log = $ctx.Log
    $ui = $ctx.Ui
    $RedrawView = $ctx.RedrawView
    $onExitKey = $ctx.OnExitKey
    $uiPollState = $ctx.PollState
    $logSeparatorRow = $ctx.LogSeparatorRow
    $logContentViewportRows = $ctx.LogContentViewportRows

    $successCount = 0
    $failedCount = 0
    $cancelled = $false

    try {
        & $ctx.FnDrainStaleInput
        if (Get-Command Clear-ConsoleInputBuffer -ErrorAction SilentlyContinue) {
            Clear-ConsoleInputBuffer
        }

        Set-ToolkitShellToolbarLocked -Shell $Shell -Locked $true
        Start-ToolkitDepOperationBatch -Ui $ui
        & $RedrawView

        for ($i = 0; $i -lt $total; $i++) {
            if ($cancelled) { break }

            $ver = [string]$versions[$i]
            $target = "node@$ver"
            $loadingState = New-NodeBrowseInstallLoadingState
            $loadingState['InstallPhase'] = 'starting'
            $ui.ItemSubPercent = 0
            $ui.InstallPhase = 'starting'

            if ($ui.ProgressCurrent -gt 0) {
                Write-NodeBrowseInstallLogLine -Log $log -Text '' -Kind 'separator'
            }
            $sectionText = Get-I18n -Key 'page.depOperation.logSectionPackage' -Vars @{
                name  = $target
                index = ($i + 1)
                total = $total
            }
            Write-NodeBrowseInstallLogLine -Log $log -Text $sectionText -Kind 'section' -WithTimestamp

            $ui.ProgressName = $target
            $ui.ItemInFlight = $true
            $ui.ExecuteStartTick = [Environment]::TickCount
            $loadingState['LastOutputTick'] = $ui.ExecuteStartTick
            Update-NodeBrowseInstallLoadingStatus -Ui $ui -LoadingState $loadingState -Version $ver
            & $RedrawView

            Write-NodeBrowseInstallLogLine -Log $log -Text (Get-NodeBrowseI18n -Key 'node.browse.installLogStart' -Vars @{
                version = $ver
            }) -Kind 'heading' -WithTimestamp

            try {
                if (-not (Test-VoltaNodeInventoryZipReady -Version $ver)) {
                    $loadingState['InstallPhase'] = 'downloading'
                    $ui.InstallPhase = 'downloading'
                    Invoke-VoltaNodeInventoryDownload -Version $ver -Ui $ui -Redraw $RedrawView -Log $log `
                        -LoadingState $loadingState
                }
                else {
                    Set-NodeVoltaInstallProgressPercent -Ui $ui -Percent 65 -Version $ver -Phase 'downloading' | Out-Null
                    $loadingState['InstallPhase'] = 'downloading'
                    $ui.InstallPhase = 'downloading'
                    Update-NodeBrowseInstallLoadingStatus -Ui $ui -LoadingState $loadingState -Version $ver
                    & $RedrawView
                }
            }
            catch {
                $failedCount++
                Write-NodeBrowseInstallLogLine -Log $log -Text (Get-NodeBrowseI18n -Key 'node.browse.installLogDownloadFailed' -Vars @{
                    version = $ver
                    detail  = [string]$_.Exception.Message
                }) -Kind 'error' -WithTimestamp
                $ui.ItemInFlight = $false
                $ui.ItemSubPercent = -1
                $ui.ProgressCurrent = $i + 1
                & $RedrawView
                continue
            }

            $procState = Start-NodeVoltaInstallProcess -Version $ver
            Write-NodeBrowseInstallLogLine -Log $log -Text $procState.CommandLine -WithTimestamp
            & $RedrawView

            $exitCode = @(Wait-NodeVoltaInstallProcess -State $procState -Ui $ui -LoadingState $loadingState `
                -Version $ver -Shell $Shell -Log $log -LogViewportRows $logContentViewportRows `
                -OnExitKey $onExitKey -ScrollState $uiPollState -FnLogInput $ctx.FnLogInput `
                -Redraw $RedrawView)[-1]
            $exitCode = [int]$exitCode

            if ($exitCode -eq 0) {
                $ui.ItemSubPercent = 100
                Update-NodeBrowseInstallLoadingStatus -Ui $ui -LoadingState $loadingState -Version $ver
                & $RedrawView
            }

            $ui.ItemInFlight = $false
            $ui.ItemSubPercent = -1
            $ui.InstallPhase = ''

            if ($exitCode -eq 0) {
                $successCount++
                Write-NodeBrowseInstallLogLine -Log $log -Text (Get-NodeBrowseI18n -Key 'node.browse.installLogSuccess' -Vars @{
                    version = $ver
                }) -Kind 'success' -WithTimestamp
            }
            else {
                $failedCount++
                Write-NodeBrowseInstallLogLine -Log $log -Text (Get-NodeBrowseI18n -Key 'node.browse.installLogFailed' -Vars @{
                    version = $ver
                    code    = [string]$exitCode
                }) -Kind 'error' -WithTimestamp
            }

            $ui.ProgressCurrent = $i + 1
            & $RedrawView
        }

        if (-not $cancelled) {
            Set-ToolkitDepOperationBatchCompleteUi -Ui $ui -Intent install -TotalCount $total `
                -SuccessCount $successCount -FailedCount $failedCount -ProgressCurrent $total
        }

        return Invoke-ToolkitDepBatchOperationWaitLoop -Context $ctx
    }
    finally {
        Clear-ToolkitDepBatchOperationView -Context $ctx
    }
}
