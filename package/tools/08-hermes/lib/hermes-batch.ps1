# hermes — 批量执行（安装 / 更新 / 卸载）

function Write-HermesBatchLogLine {
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

function Invoke-HermesProcessStream {
    param(
        [string]$FileName,
        [string[]]$ArgumentList,
        [scriptblock]$OnOutputLine = $null,
        [scriptblock]$OnUiPoll = $null,
        [scriptblock]$OnChromePulse = $null,
        [int]$ProcessExitWaitMs = 1800000
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FileName
    $escaped = @($ArgumentList | ForEach-Object {
        if ($_ -match '\s') { "`"$_`"" } else { $_ }
    })
    $psi.Arguments = ($escaped -join ' ')
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $psi.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    $process.EnableRaisingEvents = $true

    $stdoutQueue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
    $stderrQueue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()

    $stdoutSub = Register-ObjectEvent -InputObject $process -EventName OutputDataReceived -Action {
        if ($null -ne $EventArgs.Data) {
            [void]$Event.MessageData.Queue.Enqueue([string]$EventArgs.Data)
        }
        else {
            $Event.MessageData.Ended = $true
        }
    } -MessageData @{ Queue = $stdoutQueue; Ended = $false }

    $stderrSub = Register-ObjectEvent -InputObject $process -EventName ErrorDataReceived -Action {
        if ($null -ne $EventArgs.Data) {
            [void]$Event.MessageData.Queue.Enqueue([string]$EventArgs.Data)
        }
        else {
            $Event.MessageData.Ended = $true
        }
    } -MessageData @{ Queue = $stderrQueue; Ended = $false }

    $streamState = @{
        AllLines       = (New-Object System.Collections.ArrayList)
        LastOutputTick = [Environment]::TickCount
    }
    $timedOut = $false
    $startTick = [Environment]::TickCount

    $drainQueues = {
        param($Queue, $OnLine, $State)

        $item = $null
        $notified = $false
        while ($Queue.TryDequeue([ref]$item)) {
            if ([string]::IsNullOrWhiteSpace([string]$item)) { continue }
            $line = [string]$item
            [void]$State.AllLines.Add($line)
            if ($OnLine) {
                & $OnLine $line
            }
            $State.LastOutputTick = [Environment]::TickCount
            $notified = $true
        }
        return $notified
    }.GetNewClosure()

    try {
        $null = $process.Start()
        $process.BeginOutputReadLine()
        $process.BeginErrorReadLine()

        $deadline = $startTick + [Math]::Max(60000, $ProcessExitWaitMs)

        while (-not $process.HasExited) {
            if ([Environment]::TickCount -ge $deadline) {
                $timedOut = $true
                try { $process.Kill() } catch {}
                break
            }

            if ($OnChromePulse) { & $OnChromePulse }
            if ($OnUiPoll) { & $OnUiPoll }

            $null = & $drainQueues $stdoutQueue $OnOutputLine $streamState
            $null = & $drainQueues $stderrQueue $OnOutputLine $streamState

            Start-Sleep -Milliseconds 50
        }

        if (-not $timedOut) {
            $null = $process.WaitForExit(5000)
        }

        $null = & $drainQueues $stdoutQueue $OnOutputLine $streamState
        $null = & $drainQueues $stderrQueue $OnOutputLine $streamState

        $allLines = @($streamState.AllLines.ToArray())
        $exitCode = if ($process.HasExited) { [int]$process.ExitCode } else { -1 }

        return [pscustomobject]@{
            ExitCode = $exitCode
            Success  = (-not $timedOut -and $exitCode -eq 0)
            TimedOut = $timedOut
            Lines    = $allLines
            Output   = (($allLines | ForEach-Object { [string]$_ }) -join "`n")
        }
    }
    finally {
        if ($stdoutSub) {
            try { Unregister-Event -SourceIdentifier $stdoutSub.Name -ErrorAction SilentlyContinue } catch {}
            try { Remove-Event -SourceIdentifier $stdoutSub.Name -ErrorAction SilentlyContinue } catch {}
        }
        if ($stderrSub) {
            try { Unregister-Event -SourceIdentifier $stderrSub.Name -ErrorAction SilentlyContinue } catch {}
            try { Remove-Event -SourceIdentifier $stderrSub.Name -ErrorAction SilentlyContinue } catch {}
        }
        try { $process.Dispose() } catch {}
    }
}

function New-HermesStreamOutputLineHandler {
    param(
        $Log,
        $Ui,
        $ProgressState,
        [scriptblock]$Pump,
        [scriptblock]$RedrawView
    )

    $fnProgressLog = Get-Command -Name Write-HermesProgressLogLine -CommandType Function -ErrorAction Stop
    $fnSetStatus = Get-Command -Name Set-ToolkitDepOperationInFlightStatus -CommandType Function -ErrorAction Stop
    $logRef = $Log
    $uiRef = $Ui
    $progressRef = $ProgressState
    $pumpRef = $Pump
    $redrawRef = $RedrawView

    return {
        param($Line)
        if ([string]::IsNullOrWhiteSpace($Line)) { return }
        $trim = [string]$Line.Trim()
        if ([string]::IsNullOrWhiteSpace($trim)) { return }
        & $fnProgressLog -Log $logRef -Text $trim -Kind 'text' -WithTimestamp `
            -ProgressState $progressRef -Ui $uiRef
        & $fnSetStatus -Ui $uiRef -MainText $trim -AdvanceSpinner
        & $pumpRef
        & $redrawRef
    }.GetNewClosure()
}

function Invoke-HermesInstallStreamWork {
    param(
        $Context,
        [string]$ToolRoot,
        [string]$SuccessLogKey,
        [string]$FailureLogKey,
        [scriptblock]$Pump,
        $ProgressState = $null
    )

    $log = $Context.Log
    $ui = $Context.Ui
    $RedrawView = $Context.RedrawView

    if ($ProgressState) {
        Set-HermesProgressPhase -State $ProgressState -Ui $ui -Phase 'install-run'
    }

    $sectionText = Get-HermesI18n -ToolRoot $ToolRoot -Key 'hermes.cli.installInProgress'
    Write-HermesProgressLogLine -Log $log -Text $sectionText -Kind 'section' -WithTimestamp `
        -ProgressState $ProgressState -Ui $ui

    $ui.ProgressName = 'Hermes CLI'
    $ui.ItemInFlight = $true
    if ([int]$ui.ItemSubPercent -lt 0) { $ui.ItemSubPercent = 0 }
    $ui.ExecuteStartTick = [Environment]::TickCount
    Set-ToolkitDepOperationInFlightStatus -Ui $ui -MainText $sectionText -AdvanceSpinner
    & $RedrawView

    $wrapperPath = New-HermesInstallWrapperScriptPath
    $result = $null
    try {
        $onOutputLine = New-HermesStreamOutputLineHandler -Log $log -Ui $ui `
            -ProgressState $ProgressState -Pump $Pump -RedrawView $RedrawView

        $result = Invoke-HermesProcessStream -FileName 'powershell.exe' `
            -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $wrapperPath) `
            -OnOutputLine $onOutputLine -OnUiPoll $Pump -OnChromePulse { & $RedrawView } `
            -ProcessExitWaitMs $script:HermesInstallProcessExitWaitMs
    }
    finally {
        if ($wrapperPath -and (Test-Path -LiteralPath $wrapperPath)) {
            Remove-Item -LiteralPath $wrapperPath -Force -ErrorAction SilentlyContinue
        }
    }

    return (Resolve-HermesStreamWorkOutcome -Result $result -ToolRoot $ToolRoot `
        -SuccessLogKey $SuccessLogKey -FailureLogKey $FailureLogKey -Log $log `
        -IncludePostInstallHint -TimeoutMs $script:HermesInstallProcessExitWaitMs)
}

function Invoke-HermesCliStreamWork {
    param(
        $Context,
        [string]$ToolRoot,
        [ValidateSet('update', 'uninstall')]
        [string]$Intent,
        [string]$SuccessLogKey,
        [string]$FailureLogKey,
        [scriptblock]$Pump,
        $ProgressState = $null
    )

    $log = $Context.Log
    $ui = $Context.Ui
    $RedrawView = $Context.RedrawView

    if ($ProgressState) {
        Set-HermesProgressPhase -State $ProgressState -Ui $ui -Phase 'install-run'
    }

    $label = if ($Intent -eq 'update') { 'hermes update' } else { 'hermes uninstall' }
    Write-HermesProgressLogLine -Log $log -Text $label -Kind 'section' -WithTimestamp `
        -ProgressState $ProgressState -Ui $ui

    $ui.ProgressName = $label
    $ui.ItemInFlight = $true
    if ([int]$ui.ItemSubPercent -lt 0) { $ui.ItemSubPercent = 0 }
    $ui.ExecuteStartTick = [Environment]::TickCount
    Set-ToolkitDepOperationInFlightStatus -Ui $ui -MainText $label -AdvanceSpinner
    & $RedrawView

    $args = if ($Intent -eq 'update') {
        @('update', '--yes')
    }
    else {
        @('uninstall', '--yes')
    }

    $timeout = if ($Intent -eq 'update') {
        $script:HermesUpdateProcessExitWaitMs
    }
    else {
        $script:HermesUninstallTimeoutMs
    }

    $exe = Resolve-HermesExecutable
    $onOutputLine = New-HermesStreamOutputLineHandler -Log $log -Ui $ui `
        -ProgressState $ProgressState -Pump $Pump -RedrawView $RedrawView

    $result = Invoke-HermesProcessStream -FileName $exe -ArgumentList $args `
        -OnOutputLine $onOutputLine -OnUiPoll $Pump -OnChromePulse { & $RedrawView } `
        -ProcessExitWaitMs $timeout

    return (Resolve-HermesStreamWorkOutcome -Result $result -ToolRoot $ToolRoot `
        -SuccessLogKey $SuccessLogKey -FailureLogKey $FailureLogKey -Log $log `
        -TimeoutMs $timeout)
}

function Resolve-HermesStreamWorkOutcome {
    param(
        $Result,
        [string]$ToolRoot,
        [string]$SuccessLogKey,
        [string]$FailureLogKey,
        $Log,
        [switch]$IncludePostInstallHint,
        [int]$TimeoutMs = 0
    )

    $fnWriteLog = ${function:Write-HermesBatchLogLine}
    $ok = $false
    if ($Result) {
        if ($Result.TimedOut) {
            $ok = $false
        }
        else {
            $ok = [bool]$Result.Success
        }
    }

    if ($ok) {
        & $fnWriteLog -Log $Log -Text (Get-HermesI18n -ToolRoot $ToolRoot -Key $SuccessLogKey) `
            -Kind 'success' -WithTimestamp
        if ($IncludePostInstallHint) {
            foreach ($hintLine in @(Get-HermesPostInstallHintLines -ToolRoot $ToolRoot)) {
                & $fnWriteLog -Log $Log -Text $hintLine -Kind 'text' -WithTimestamp
            }
        }
    }
    else {
        $detail = ''
        if ($Result) {
            if ($Result.TimedOut) {
                $minutes = if ($TimeoutMs -gt 0) {
                    [int][Math]::Max(1, [Math]::Round($TimeoutMs / 60000.0))
                }
                else {
                    120
                }
                $detail = Get-HermesI18n -ToolRoot $ToolRoot -Key 'hermes.cli.toolkitTimedOut' `
                    -Vars @{ minutes = $minutes }
            }
            elseif ($Result.Lines) {
                $detail = ($Result.Lines | Select-Object -Last 3 | ForEach-Object { [string]$_ }) -join ' '
            }
            if ([string]::IsNullOrWhiteSpace($detail) -and $Result.Output) {
                $detail = [string]$Result.Output
            }
            if ([string]::IsNullOrWhiteSpace($detail) -and $null -ne $Result.ExitCode) {
                $detail = "exit $($Result.ExitCode)"
            }
        }
        if ([string]::IsNullOrWhiteSpace($detail)) { $detail = 'unknown error' }
        & $fnWriteLog -Log $Log -Text (Get-HermesI18n -ToolRoot $ToolRoot -Key $FailureLogKey `
            -Vars @{ detail = $detail }) -Kind 'error' -WithTimestamp
    }

    return @{
        Ok     = $ok
        Result = $Result
    }
}

function Get-HermesPostInstallHintLines {
    param([string]$ToolRoot)

    $hint = Get-HermesI18n -ToolRoot $ToolRoot -Key 'hermes.cli.postInstallHint'
    if ([string]::IsNullOrWhiteSpace($hint)) { return @() }
    return @($hint -split "`r?`n" | ForEach-Object { [string]$_ } | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_)
    })
}

function Write-HermesDesktopNoticeIfNeeded {
    param(
        $Log,
        [string]$ToolRoot,
        [string]$CoreLib
    )

    if (-not (Test-HermesWingetDesktopInstalled -CoreLib $CoreLib)) {
        return
    }

    Write-HermesBatchLogLine -Log $Log -Text (Get-HermesI18n -ToolRoot $ToolRoot `
        -Key 'hermes.cli.desktopDetected') -Kind 'text' -WithTimestamp
}
