# node — 浏览并卸载：批量卸载进度与日志视图

function Get-NodeBrowseUninstallCoreLib {
    if ($script:NodeBrowseUninstallCoreLib) {
        return $script:NodeBrowseUninstallCoreLib
    }
    if ($coreLib) {
        return [string]$coreLib
    }

    $toolRoot = Split-Path $PSScriptRoot -Parent
    $script:NodeBrowseUninstallCoreLib = (Join-Path $toolRoot '..\..\core\lib')
    return $script:NodeBrowseUninstallCoreLib
}

function Ensure-NodeBrowseUninstallShellUi {
    $coreLib = Get-NodeBrowseUninstallCoreLib

    foreach ($rel in @(
            'ui\shell\SystemToolbar.ps1'
            'ui\shell\Exit.ps1'
            'ui\shell\Footer.ps1'
            'ui\shell\DepOperationView.ps1'
        )) {
        $path = Join-Path $coreLib $rel
        $name = [IO.Path]::GetFileNameWithoutExtension($rel)
        if ($name -eq 'DepOperationView') {
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
}

function Update-NodeBrowseUninstallLoadingStatus {
    param(
        $Ui,
        $LoadingState,
        [string]$Version,
        [ValidateSet('uninstall', 'promote')]
        [string]$Phase = 'uninstall'
    )

    if (-not $Ui.ItemInFlight) { return }

    $LoadingState['SpinnerIndex'] = [int]$LoadingState['SpinnerIndex'] + 1
    $frames = $LoadingState['SpinnerFrames']
    $spinner = $frames[[int]$LoadingState['SpinnerIndex'] % $frames.Count]
    $elapsed = 0
    if ($Ui.ExecuteStartTick -gt 0) {
        $elapsed = [int][Math]::Floor(([Environment]::TickCount - $Ui.ExecuteStartTick) / 1000.0)
    }

    if ($Phase -eq 'promote') {
        $key = if ($LoadingState['OutputSeen']) {
            'node.uninstall.promoteStatusWorking'
        }
        else {
            'node.uninstall.promoteStatusStarting'
        }
    }
    else {
        $key = if ($LoadingState['OutputSeen']) {
            'node.uninstall.uninstallStatusWorking'
        }
        else {
            'node.uninstall.uninstallStatusStarting'
        }
    }

    $Ui.StatusText = Get-NodeBrowseUninstallI18n -Key $key -Vars @{
        spinner = $spinner
        elapsed = [string]$elapsed
        version = $Version
    }
    $Ui.StatusPlain = $false
}

function Start-NodeVoltaUninstallProcess {
    param([string]$Version)

    $voltaCmd = Get-Command volta -ErrorAction Stop
    $target = "node@$Version"
    $queue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $voltaCmd.Source
    $psi.Arguments = "uninstall `"$target`""
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
        throw 'Failed to start volta uninstall'
    }

    $proc.BeginOutputReadLine()
    $proc.BeginErrorReadLine()

    return @{
        Process       = $proc
        Queue         = $queue
        Subscriptions = @($stdoutSub, $stderrSub)
        CommandLine   = "volta uninstall `"$target`""
    }
}

function Wait-NodeVoltaUninstallProcess {
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
        [ValidateSet('uninstall', 'promote')]
        [string]$Phase = 'uninstall'
    )

    $pollState = @{
        LastLoadingTick = 0
        LoadingInterval = 200
    }

    while (-not $State.Process.HasExited) {
        Drain-NodeVoltaInstallQueue -State $State -Log $Log -LoadingState $LoadingState -Redraw $Redraw

        $now = [Environment]::TickCount
        if (($now - $pollState.LastLoadingTick) -ge $pollState.LoadingInterval) {
            Update-NodeBrowseUninstallLoadingStatus -Ui $Ui -LoadingState $LoadingState `
                -Version $Version -Phase $Phase
            & $Redraw
            $pollState.LastLoadingTick = $now
        }

        if (Test-ToolkitShellToolbarLocked -Shell $Shell) {
            Drain-ShellLockedToolbarKeys -Shell $Shell -AllowLogScroll
        }

        $inputResult = & $FnLogInput -Shell $Shell -Log $Log -ViewportRows $LogViewportRows `
            -OnExitKey $OnExitKey -ScrollState $ScrollState
        if ($inputResult -eq 'scroll') {
            & $Redraw
        }

        Start-Sleep -Milliseconds 30
    }

    $State.Process.WaitForExit()
    Start-Sleep -Milliseconds 80
    Drain-NodeVoltaInstallQueue -State $State -Log $Log -LoadingState $LoadingState -Redraw $Redraw
    return (Complete-NodeVoltaInstallProcess -State $State)
}

function Invoke-NodeVoltaProcessStep {
    param(
        $Ui,
        $Log,
        [hashtable]$Shell,
        [int]$LogViewportRows,
        [string]$Version,
        [scriptblock]$StartProcess,
        [ValidateSet('uninstall', 'promote')]
        [string]$Phase,
        [scriptblock]$OnExitKey,
        [hashtable]$ScrollState,
        $FnLogInput,
        [scriptblock]$Redraw
    )

    $loadingState = New-NodeBrowseInstallLoadingState
    $ui.ItemInFlight = $true
    $ui.ExecuteStartTick = [Environment]::TickCount
    $loadingState['LastOutputTick'] = $ui.ExecuteStartTick
    Update-NodeBrowseUninstallLoadingStatus -Ui $Ui -LoadingState $loadingState -Version $Version -Phase $Phase
    & $Redraw

    $procState = & $StartProcess -Version $Version
    Write-NodeBrowseInstallLogLine -Log $Log -Text $procState.CommandLine
    & $Redraw

    return (Wait-NodeVoltaUninstallProcess -State $procState -Ui $Ui -LoadingState $loadingState `
        -Version $Version -Shell $Shell -Log $Log -LogViewportRows $LogViewportRows `
        -OnExitKey $OnExitKey -ScrollState $ScrollState -FnLogInput $FnLogInput `
        -Redraw $Redraw -Phase $Phase)
}

function Run-NodeBrowseUninstallOperation {
    param(
        [hashtable]$Shell,
        [array]$Items
    )

    Ensure-NodeBrowseUninstallShellUi

    $versions = @($Items | ForEach-Object {
        if ($_.Version) { Normalize-NodeVersionLabel -Version ([string]$_.Version) }
        elseif ($_.Source -and $_.Source.Version) { Normalize-NodeVersionLabel -Version ([string]$_.Source.Version) }
        else { '' }
    } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $total = $versions.Count
    if ($total -le 0) {
        return $null
    }

    $initialInfo = Get-VoltaNodeVersionInfo
    $ordered = Order-NodeVersionsForUninstall -VersionsToUninstall $versions -DefaultVersion $initialInfo.Default

    $toolbar = New-ShellSystemToolbarConfig -HideSystem -HideHelp
    $renderFooter = New-ShellSystemToolbarFooterRenderer -Shell $Shell -ToolbarConfig $toolbar
    Register-ToolkitShellFooter -Shell $Shell -Renderer $renderFooter

    $sectionTitle = Get-NodeBrowseUninstallProgressSectionTitle
    Initialize-ToolkitShellBodyView -Shell $Shell -SectionTitle $sectionTitle -FooterTemplate SystemToolbarOnly

    $layout = $Shell.Layout
    $logLayout = Get-ToolkitDepOperationLogLayout -Layout $layout
    $logSeparatorRow = [int]$logLayout.SeparatorRow
    $logContentViewportRows = [int]$logLayout.ContentViewportRows

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
        StatusText       = (Get-NodeBrowseUninstallI18n -Key 'node.uninstall.statusReady')
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
    $fnWriteExitFooter = Get-Command Write-ShellExitFooter -CommandType Function -ErrorAction Stop

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
        if ($Shell.ExitMode) {
            & $fnWriteExitFooter -Shell $Shell
        }
        else {
            & $renderFooter
        }
        if ($useBufferDraw) {
            $null = & $fnCompleteBatch -ToolkitShell $Shell
        }
    }.GetNewClosure()

    $onExitConfirmed = { }.GetNewClosure()
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

        Set-ToolkitShellToolbarLocked -Shell $Shell -Locked $true
        & $RedrawView

        for ($i = 0; $i -lt $total; $i++) {
            if ($cancelled) { break }

            $ver = $ordered[$i]
            $target = "node@$ver"
            $voltaInfo = Get-VoltaNodeVersionInfo
            $defaultNorm = Normalize-NodeVersionLabel -Version $voltaInfo.Default
            $verNorm = Normalize-NodeVersionLabel -Version $ver
            $isDefault = ($defaultNorm -and $verNorm -eq $defaultNorm)

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
            Write-NodeBrowseInstallLogLine -Log $log -Text (Get-NodeBrowseUninstallI18n -Key 'node.uninstall.logStart' -Vars @{
                version = $ver
            }) -Kind 'heading' -WithTimestamp
            & $RedrawView

            if ($isDefault) {
                $replacement = Get-NodeDefaultReplacementVersion -InstalledMap $voltaInfo.Map -ExcludeVersion $ver
                if ($replacement) {
                    Write-NodeBrowseInstallLogLine -Log $log -Text (Get-NodeBrowseUninstallI18n -Key 'node.uninstall.logPromoteDefault' -Vars @{
                        version     = $ver
                        replacement = $replacement
                    }) -Kind 'hint' -WithTimestamp
                    & $RedrawView

                    $promoteExit = Invoke-NodeVoltaProcessStep -Ui $ui -Log $log -Shell $Shell `
                        -LogViewportRows $logContentViewportRows -Version $replacement `
                        -Phase 'promote' -StartProcess ${function:Start-NodeVoltaInstallProcess} `
                        -OnExitKey $onExitKey -ScrollState $uiPollState -FnLogInput $fnLogInput `
                        -Redraw $RedrawView

                    if ($promoteExit -ne 0) {
                        Write-NodeBrowseInstallLogLine -Log $log -Text (Get-NodeBrowseUninstallI18n -Key 'node.uninstall.logPromoteFailed' -Vars @{
                            replacement = $replacement
                            code        = [string]$promoteExit
                        }) -Kind 'error' -WithTimestamp
                    }
                    else {
                        Write-NodeBrowseInstallLogLine -Log $log -Text (Get-NodeBrowseUninstallI18n -Key 'node.uninstall.logPromoteSuccess' -Vars @{
                            replacement = $replacement
                        }) -Kind 'success' -WithTimestamp
                    }
                    & $RedrawView
                }
                else {
                    Write-NodeBrowseInstallLogLine -Log $log -Text (Get-NodeBrowseUninstallI18n -Key 'node.uninstall.logNoReplacement' -Vars @{
                        version = $ver
                    }) -Kind 'hint' -WithTimestamp
                    & $RedrawView
                }
            }

            $uninstallExit = Invoke-NodeVoltaProcessStep -Ui $ui -Log $log -Shell $Shell `
                -LogViewportRows $logContentViewportRows -Version $ver -Phase 'uninstall' `
                -StartProcess ${function:Start-NodeVoltaUninstallProcess} -OnExitKey $onExitKey `
                -ScrollState $uiPollState -FnLogInput $fnLogInput -Redraw $RedrawView
            $ui.ItemInFlight = $false

            Write-NodeBrowseInstallLogLine -Log $log -Text (Get-NodeBrowseUninstallI18n -Key 'node.uninstall.logCleanupStart' -Vars @{
                version = $ver
            }) -Kind 'heading' -WithTimestamp

            $cleanup = Remove-VoltaNodeVersionImageDirs -Version $ver
            if ([string]::IsNullOrWhiteSpace($cleanup.Root)) {
                Write-NodeBrowseInstallLogLine -Log $log -Text (Get-NodeBrowseUninstallI18n -Key 'node.uninstall.logCleanupNoHome') -Kind 'hint'
            }
            else {
                Write-NodeBrowseInstallLogLine -Log $log -Text (Get-NodeBrowseUninstallI18n -Key 'node.uninstall.logCleanupScan' -Vars @{
                    root = $cleanup.Root
                }) -Kind 'hint'
            }
            if ($cleanup.Paths.Count -eq 0) {
                Write-NodeBrowseInstallLogLine -Log $log -Text (Get-NodeBrowseUninstallI18n -Key 'node.uninstall.logCleanupNone' -Vars @{
                    version = $ver
                }) -Kind 'hint'
            }
            foreach ($path in @($cleanup.Paths)) {
                Write-NodeBrowseInstallLogLine -Log $log -Text (Get-NodeBrowseUninstallI18n -Key 'node.uninstall.logCleanupRemove' -Vars @{
                    path = $path
                })
            }
            foreach ($path in @($cleanup.Removed)) {
                Write-NodeBrowseInstallLogLine -Log $log -Text (Get-NodeBrowseUninstallI18n -Key 'node.uninstall.logCleanupRemoved' -Vars @{
                    path = $path
                }) -Kind 'success'
            }
            foreach ($fail in @($cleanup.Failed)) {
                Write-NodeBrowseInstallLogLine -Log $log -Text (Get-NodeBrowseUninstallI18n -Key 'node.uninstall.logCleanupFailed' -Vars @{
                    path  = $fail.Path
                    error = $fail.Error
                }) -Kind 'error'
            }

            $absent = Test-VoltaNodeVersionAbsent -Version $ver
            $remainingPaths = Get-VoltaNodeVersionImagePaths -Version $ver
            $success = $absent -and ($remainingPaths.Count -eq 0)

            if ($uninstallExit -ne 0 -and $success) {
                Write-NodeBrowseInstallLogLine -Log $log -Text (Get-NodeBrowseUninstallI18n -Key 'node.uninstall.logVoltaExitIgnored' -Vars @{
                    version = $ver
                    code    = [string]$uninstallExit
                }) -Kind 'hint' -WithTimestamp
            }

            if ($success) {
                $successCount++
                Write-NodeBrowseInstallLogLine -Log $log -Text (Get-NodeBrowseUninstallI18n -Key 'node.uninstall.logSuccess' -Vars @{
                    version = $ver
                }) -Kind 'success' -WithTimestamp
            }
            else {
                $failedCount++
                if (-not $absent) {
                    Write-NodeBrowseInstallLogLine -Log $log -Text (Get-NodeBrowseUninstallI18n -Key 'node.uninstall.logVerifyListed' -Vars @{
                        version = $ver
                    }) -Kind 'error' -WithTimestamp
                }
                if ($remainingPaths.Count -gt 0) {
                    Write-NodeBrowseInstallLogLine -Log $log -Text (Get-NodeBrowseUninstallI18n -Key 'node.uninstall.logVerifyImageRemain' -Vars @{
                        version = $ver
                        paths   = ($remainingPaths -join '; ')
                    }) -Kind 'error' -WithTimestamp
                }
            }

            $ui.ProgressCurrent = $i + 1
            & $RedrawView
        }

        if (-not $cancelled) {
            $ui.ProgressCurrent = $total
            $ui.StatusPlain = $true
            $ui.StatusText = ''
            $ui.StatusSegments = Get-ToolkitDepBatchSummarySegments -Intent uninstall `
                -TotalCount $total -SuccessCount $successCount -FailedCount $failedCount
        }

        $log.AutoScroll = $false
        Set-ToolkitShellToolbarLocked -Shell $Shell -Locked $false
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

                if (-not (Test-ToolkitShellToolbarLocked -Shell $Shell)) {
                    Prepare-ToolkitShellBodyDraw -Shell $Shell
                    $key = [Console]::ReadKey($true)
                    Set-CursorVisible $false
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
            }

            Start-Sleep -Milliseconds 20
        }
    }
    finally {
        Set-ToolkitShellToolbarLocked -Shell $Shell -Locked $false
        & $fnClearExitExtension -Shell $Shell
    }
}
