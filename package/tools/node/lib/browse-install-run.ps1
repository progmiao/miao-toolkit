# node — 浏览并安装：批量安装进度与日志视图

function Ensure-NodeBrowseInstallDepView {
    if (Get-Command Draw-ToolkitDepOperationView -ErrorAction SilentlyContinue) { return }
    . (Join-Path $coreLib 'ui\shell\DepOperationView.ps1')
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

    $timestamp = if ($WithTimestamp) { (Get-Date).ToString('HH:mm:ss') } else { '' }
    $Log.Lines.Add([pscustomobject]@{
        Timestamp = $timestamp
        Text      = [string]$Text
        Kind      = $Kind
        Color     = $lineColor
    }) | Out-Null

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

    $LoadingState['SpinnerIndex'] = [int]$LoadingState['SpinnerIndex'] + 1
    $frames = $LoadingState['SpinnerFrames']
    $spinner = $frames[[int]$LoadingState['SpinnerIndex'] % $frames.Count]
    $elapsed = 0
    if ($Ui.ExecuteStartTick -gt 0) {
        $elapsed = [int][Math]::Floor(([Environment]::TickCount - $Ui.ExecuteStartTick) / 1000.0)
    }

    $key = if ($LoadingState['OutputSeen']) {
        'node.browse.installStatusWorking'
    }
    else {
        'node.browse.installStatusStarting'
    }
    $Ui.StatusText = Get-NodeBrowseI18n -Key $key -Vars @{
        spinner = $spinner
        elapsed = [string]$elapsed
        version = $Version
    }
    $Ui.StatusPlain = $false
}

function Start-NodeVoltaInstallProcess {
    param([string]$Version)

    $voltaCmd = Get-Command volta -ErrorAction Stop
    $target = "node@$Version"
    $queue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $voltaCmd.Source
    $psi.Arguments = "install `"$target`""
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
        Process       = $proc
        Queue         = $queue
        Subscriptions = @($stdoutSub, $stderrSub)
        CommandLine   = "volta install `"$target`""
    }
}

function Complete-NodeVoltaInstallProcess {
    param($State)

    foreach ($sub in @($State.Subscriptions)) {
        if ($sub) {
            Unregister-Event -SourceIdentifier $sub.Name -ErrorAction SilentlyContinue
        }
    }

    $exitCode = 1
    if ($State.Process) {
        try {
            if (-not $State.Process.HasExited) {
                $State.Process.WaitForExit(2000)
            }
            $exitCode = [int]$State.Process.ExitCode
        }
        catch { }
    }
    return $exitCode
}

function Stop-NodeVoltaInstallProcess {
    param($State)

    try {
        if ($State.Process -and -not $State.Process.HasExited) {
            $State.Process.Kill()
            $State.Process.WaitForExit(2000)
        }
    }
    catch { }
    return (Complete-NodeVoltaInstallProcess -State $State)
}

function Drain-NodeVoltaInstallQueue {
    param(
        $State,
        $Log,
        $LoadingState,
        [scriptblock]$Redraw
    )

    $line = $null
    $added = 0
    while ($State.Queue.TryDequeue([ref]$line)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $LoadingState['OutputSeen'] = $true
        $LoadingState['LastOutputTick'] = [Environment]::TickCount
        Write-NodeBrowseInstallLogLine -Log $Log -Text $line
        $added++
        $line = $null
    }
    if ($added -gt 0) {
        & $Redraw
    }
    return ($added -gt 0)
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
        [scriptblock]$OnExitKey,
        [hashtable]$ScrollState,
        $FnLogInput,
        [scriptblock]$Redraw,
        [ref]$Cancelled
    )

    $pollState = @{
        LastLoadingTick = 0
        LoadingInterval = 200
    }

    while (-not $State.Process.HasExited) {
        Drain-NodeVoltaInstallQueue -State $State -Log $Log -LoadingState $LoadingState -Redraw $Redraw

        $now = [Environment]::TickCount
        if (($now - $pollState.LastLoadingTick) -ge $pollState.LoadingInterval) {
            Update-NodeBrowseInstallLoadingStatus -Ui $Ui -LoadingState $LoadingState -Version $Version
            & $Redraw
            $pollState.LastLoadingTick = $now
        }

        $inputResult = & $FnLogInput -Shell $Shell -Log $Log -ViewportRows $LogViewportRows `
            -OnExitKey $OnExitKey -ScrollState $ScrollState
        if ($inputResult -eq 'scroll') {
            & $Redraw
        }
        elseif ($inputResult -eq 'exit') {
            $Cancelled.Value = $true
            Stop-NodeVoltaInstallProcess -State $State | Out-Null
            Drain-NodeVoltaInstallQueue -State $State -Log $Log -LoadingState $LoadingState -Redraw $Redraw
            return 1
        }

        Start-Sleep -Milliseconds 30
    }

    $State.Process.WaitForExit()
    Start-Sleep -Milliseconds 80
    Drain-NodeVoltaInstallQueue -State $State -Log $Log -LoadingState $LoadingState -Redraw $Redraw
    return (Complete-NodeVoltaInstallProcess -State $State)
}

function Run-NodeBrowseInstallOperation {
    param(
        [hashtable]$Shell,
        [array]$Items
    )

    Ensure-NodeBrowseInstallDepView

    $versions = @($Items | ForEach-Object {
        if ($_.Version) { [string]$_.Version }
        elseif ($_.Source -and $_.Source.Version) { [string]$_.Source.Version }
        else { '' }
    } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $total = $versions.Count
    if ($total -le 0) {
        return $null
    }

    $toolbar = New-ShellSystemToolbarConfig -HideSystem -HideHelp
    $renderFooter = New-ShellSystemToolbarFooterRenderer -Shell $Shell -ToolbarConfig $toolbar
    Register-ToolkitShellFooter -Shell $Shell -Renderer $renderFooter

    $sectionTitle = Get-NodeBrowseInstallProgressSectionTitle
    Initialize-ToolkitShellBodyView -Shell $Shell -SectionTitle $sectionTitle -FooterTemplate SystemToolbarOnly

    $layout = $Shell.Layout
    $logSeparatorRow = $layout.ListStartRow + 3
    $logAreaRows = [Math]::Max(1, $layout.ListViewportHeight - 3)
    if ($logSeparatorRow -gt $layout.ListEndRow) {
        $logSeparatorRow = $layout.ListEndRow
    }
    $availableLogRows = $layout.ListEndRow - $logSeparatorRow + 1
    if ($availableLogRows -lt $logAreaRows) {
        $logAreaRows = [Math]::Max(1, $availableLogRows)
    }
    $logContentViewportRows = [Math]::Max(1, $logAreaRows - 1)

    $contentMetrics = if ($Shell.Layout.ContentMetrics) { $Shell.Layout.ContentMetrics } else {
        Sync-ToolkitShellContentMetrics -Shell $Shell
    }
    $barWidth = [int]$contentMetrics.InnerWidth
    $log = New-NodeBrowseInstallLog -ViewportRows $logContentViewportRows -BrandInnerWidth $barWidth

    for ($clearRow = $logSeparatorRow; $clearRow -le $layout.ListEndRow; $clearRow++) {
        Write-FixedLine $clearRow '' -Color DarkGray
    }

    $ui = @{
        ProgressCurrent  = 0
        ItemInFlight     = $false
        ItemSubPercent   = -1
        ProgressName     = ''
        StatusText       = (Get-NodeBrowseI18n -Key 'node.browse.installStatusReady')
        StatusPlain      = $false
        StatusSegments   = $null
        ExecuteStartTick = 0
    }

    $fnEnterBatch = Resolve-DepOperationFn 'Enter-ConsoleDrawBatch'
    $fnCompleteBatch = Resolve-DepOperationFn 'Complete-ConsoleDrawBatch'
    $fnDrainStaleInput = Resolve-DepOperationFn 'Drain-ConsoleStaleToolbarInput'
    $fnReadExitIfActive = Resolve-DepOperationFn 'Read-ShellExitIfActive'
    $fnLogInput = Resolve-DepOperationFn 'Invoke-ToolkitDepLogInputIfAvailable'
    $fnRegisterExitExtension = Resolve-DepOperationFn 'Register-ShellExitExtension'
    $fnClearExitExtension = Resolve-DepOperationFn 'Clear-ShellExitExtension'
    $fnProcessEscInput = Resolve-DepOperationFn 'Process-ShellEscInputIfAvailable'

    $useBufferDraw = $false
    if ($env:MIAO_BUFFER_DRAW -eq '1') {
        try { $useBufferDraw = ($null -ne $Host.UI.RawUI) } catch {}
    }

    $fnDrawLogViewport = Resolve-DepOperationFn 'Draw-ToolkitDepOperationLogViewport'
    $fnPeekKey = Resolve-DepOperationFn 'Get-ConsoleVirtualKeyPeek'

    $RedrawView = {
        $itemSubPercent = if ($ui.ItemInFlight) { [int]$ui.ItemSubPercent } else { -1 }
        $statusSegments = if ($ui.StatusSegments) { @($ui.StatusSegments) } else { $null }
        if ($useBufferDraw) { & $fnEnterBatch }
        Draw-ToolkitDepOperationView -Shell $Shell -Log $log -ProgressCurrent $ui.ProgressCurrent `
            -ProgressTotal $total -ProgressName $ui.ProgressName -StatusText $ui.StatusText `
            -LogViewportRows 0 -LogStartRow $logSeparatorRow `
            -ProgressItemSubPercent $itemSubPercent -StatusPlain:([bool]$ui.StatusPlain) `
            -StatusSegments $statusSegments
        & $fnDrawLogViewport -Shell $Shell -Log $log `
            -LogSeparatorRow $logSeparatorRow -LogContentViewportRows $logContentViewportRows
        & $renderFooter
        if ($useBufferDraw) {
            $null = & $fnCompleteBatch -ToolkitShell $Shell
        }
    }.GetNewClosure()

    $exitConfirmArmed = $false
    $onExitConfirmed = { $exitConfirmArmed = $true }.GetNewClosure()
    & $fnRegisterExitExtension -Shell $Shell -OnExitConfirmed $onExitConfirmed

    $onExitKey = {
        $null = & $fnProcessEscInput -Shell $Shell
    }.GetNewClosure()

    $uiPollState = @{
        LastScrollTick      = 0
        MinScrollIntervalMs = 55
    }

    $successCount = 0
    $failedCount = 0
    $cancelled = $false

    try {
        & $fnDrainStaleInput
        if (Get-Command Clear-ConsoleInputBuffer -ErrorAction SilentlyContinue) {
            Clear-ConsoleInputBuffer
        }

        & $RedrawView

        for ($i = 0; $i -lt $total; $i++) {
            if ($cancelled) { break }

            $ver = $versions[$i]
            $target = "node@$ver"
            $loadingState = New-NodeBrowseInstallLoadingState

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

            $procState = Start-NodeVoltaInstallProcess -Version $ver
            Write-NodeBrowseInstallLogLine -Log $log -Text $procState.CommandLine
            & $RedrawView

            $cancelRef = [ref]$false
            $exitCode = Wait-NodeVoltaInstallProcess -State $procState -Ui $ui -LoadingState $loadingState `
                -Version $ver -Shell $Shell -Log $log -LogViewportRows $logContentViewportRows `
                -OnExitKey $onExitKey -ScrollState $uiPollState -FnLogInput $fnLogInput `
                -Redraw $RedrawView -Cancelled $cancelRef

            $ui.ItemInFlight = $false
            if ($cancelRef.Value) {
                $cancelled = $true
                Write-NodeBrowseInstallLogLine -Log $log -Text (Get-NodeBrowseI18n -Key 'node.browse.installCancelled') `
                    -Kind 'error' -WithTimestamp
                break
            }

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
            $ui.ProgressCurrent = $total
            $ui.StatusPlain = $true
            $ui.StatusText = ''
            $ui.StatusSegments = Get-ToolkitDepBatchSummarySegments -Intent install `
                -TotalCount $total -SuccessCount $successCount -FailedCount $failedCount
        }

        $log.AutoScroll = $false
        & $RedrawView
        & $fnDrainStaleInput

        while ($true) {
            $exitResult = & $fnReadExitIfActive -Shell $Shell
            if ($null -ne $exitResult) {
                if ($exitResult -eq 'exitConfirmed') {
                    return (Get-ShellNavMarker -Action 'quit')
                }
                & $RedrawView
                continue
            }

            if (Test-ConsoleKeyAvailable) {
                $peek = & $fnPeekKey
                if ($peek -in @('UpArrow', 'DownArrow', 'Escape')) {
                    $scrollInput = & $fnLogInput -Shell $Shell -Log $log -ViewportRows $logContentViewportRows `
                        -OnExitKey $onExitKey -ScrollState $uiPollState
                    if ($scrollInput -in @('scroll', 'exit')) {
                        & $RedrawView
                    }
                    continue
                }

                Prepare-ToolkitShellBodyDraw -Shell $Shell
                $key = [Console]::ReadKey($true)
                if ($key.KeyChar -match '^[qQ]$') {
                    $Shell.Layout['BodyDirty'] = $true
                    return $null
                }
                if ($key.Key -eq 'Escape') {
                    $null = & $onExitKey
                    & $RedrawView
                }
                continue
            }

            Start-Sleep -Milliseconds 20
        }
    }
    finally {
        & $fnClearExitExtension -Shell $Shell
    }
}
