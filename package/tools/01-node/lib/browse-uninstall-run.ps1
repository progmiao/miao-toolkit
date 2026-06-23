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

    $batchOpPath = Join-Path $coreLib 'ui\shell\ToolkitDepBatchOperation.ps1'
    if (-not (Get-Command Initialize-ToolkitDepBatchOperationView -ErrorAction SilentlyContinue)) {
        . $batchOpPath
    }
}

function Update-NodeBrowseUninstallProgressFrame {
    param(
        $Ui,
        $LoadingState,
        [string]$Version,
        [ValidateSet('uninstall', 'promote', 'cleanup', 'verify')]
        [string]$Phase = 'uninstall',
        [int]$MaxPercent = 40,
        [string]$StatusKey = ''
    )

    if ($null -eq $Ui -or -not $Ui.ItemInFlight) { return }

    if ([string]::IsNullOrWhiteSpace($StatusKey)) {
        if ($Phase -eq 'promote') {
            $StatusKey = if ($LoadingState['OutputSeen']) {
                'node.uninstall.promoteStatusWorking'
            }
            else {
                'node.uninstall.promoteStatusStarting'
            }
        }
        elseif ($Phase -eq 'cleanup') {
            $StatusKey = 'node.uninstall.cleanupStatus'
        }
        elseif ($Phase -eq 'verify') {
            $StatusKey = 'node.uninstall.verifyStatus'
        }
        else {
            $StatusKey = if ($LoadingState['OutputSeen']) {
                'node.uninstall.uninstallStatusWorking'
            }
            else {
                'node.uninstall.uninstallStatusStarting'
            }
        }
    }

    $mainText = Get-NodeBrowseUninstallI18n -Key $StatusKey -Vars @{
        spinner = '{spinner}'
        version = $Version
    }
    Update-ToolkitDepOperationSpinnerStatus -Ui $Ui -LoadingState $LoadingState -MainText $mainText

    if ([int]$Ui.ExecuteStartTick -gt 0 -and $MaxPercent -gt 0) {
        $elapsedMs = [Math]::Max(0, [Environment]::TickCount - [int]$Ui.ExecuteStartTick)
        $percent = [Math]::Min($MaxPercent, [int][Math]::Floor($elapsedMs / 100.0))
        if ($percent -lt 1) { $percent = 1 }
        if ([int]$Ui.ItemSubPercent -lt $percent) {
            $Ui.ItemSubPercent = $percent
        }
    }
}

function Set-NodeBrowseUninstallItemProgress {
    param(
        $Ui,
        $LoadingState,
        [string]$Version,
        [int]$Percent,
        [ValidateSet('uninstall', 'promote', 'cleanup', 'verify')]
        [string]$Phase = 'uninstall',
        [scriptblock]$Redraw
    )

    if ($null -eq $Ui -or -not $Ui.ItemInFlight) { return }

    Update-NodeBrowseUninstallProgressFrame -Ui $Ui -LoadingState $LoadingState -Version $Version `
        -Phase $Phase -MaxPercent 0
    if ($Percent -gt [int]$Ui.ItemSubPercent) {
        $Ui.ItemSubPercent = $Percent
    }
    if ($Redraw) {
        & $Redraw
    }
}

function Complete-NodeBrowseUninstallProgressAnimation {
    param(
        $Ui,
        $LoadingState,
        [string]$Version,
        [ValidateSet('uninstall', 'promote')]
        [string]$Phase = 'uninstall',
        [scriptblock]$Redraw,
        [int]$MinDurationMs = 900,
        [int]$FromPercent = 0,
        [int]$TargetPercent = 100
    )

    if ($null -eq $Ui -or -not $Ui.ItemInFlight) { return }

    if ([int]$Ui.ItemSubPercent -lt $FromPercent) {
        $Ui.ItemSubPercent = $FromPercent
    }

    $startTick = [Environment]::TickCount

    while ($true) {
        $elapsedMs = [Math]::Max(0, [Environment]::TickCount - $startTick)
        $maxPercent = if ($elapsedMs -lt $MinDurationMs) {
            [Math]::Max($FromPercent, $TargetPercent - 10)
        }
        else {
            $TargetPercent
        }
        Update-NodeBrowseUninstallProgressFrame -Ui $Ui -LoadingState $LoadingState -Version $Version `
            -Phase $Phase -MaxPercent $maxPercent

        if ($elapsedMs -ge $MinDurationMs) {
            if ([int]$Ui.ItemSubPercent -lt $TargetPercent) {
                $Ui.ItemSubPercent = [Math]::Min($TargetPercent, [int]$Ui.ItemSubPercent + 8)
            }
            else {
                break
            }
        }

        & $Redraw
        Start-Sleep -Milliseconds 80
    }

    $Ui.ItemSubPercent = $TargetPercent
    Update-NodeBrowseUninstallProgressFrame -Ui $Ui -LoadingState $LoadingState -Version $Version `
        -Phase $Phase -MaxPercent $TargetPercent
    & $Redraw
}

function Update-NodeBrowseUninstallLoadingStatus {
    param(
        $Ui,
        $LoadingState,
        [string]$Version,
        [ValidateSet('uninstall', 'promote')]
        [string]$Phase = 'uninstall'
    )

    Update-NodeBrowseUninstallProgressFrame -Ui $Ui -LoadingState $LoadingState -Version $Version -Phase $Phase
}

function Update-NodeBrowseUninstallProgressFromElapsed {
    param(
        $Ui,
        [string]$Version,
        [ValidateSet('uninstall', 'promote')]
        [string]$Phase = 'uninstall'
    )

    if ($null -eq $Ui -or -not $Ui.ItemInFlight) { return $false }
    if ([int]$Ui.ExecuteStartTick -le 0) { return $false }

    $elapsedMs = [Math]::Max(0, [Environment]::TickCount - [int]$Ui.ExecuteStartTick)
    $percent = [Math]::Min(90, [int][Math]::Floor($elapsedMs / 100.0))
    if ($percent -lt 1) { $percent = 1 }
    if ([int]$Ui.ItemSubPercent -ge $percent) { return $false }

    $Ui.ItemSubPercent = $percent
    return $true
}

function Start-NodeVoltaUninstallProcess {
    param([string]$Version)

    $norm = Normalize-NodeVersionLabel -Version $Version
    if ([string]::IsNullOrWhiteSpace($norm)) {
        throw 'Node version is required for uninstall'
    }

    $voltaCmd = Get-Command volta -ErrorAction Stop
    $target = "node@$norm"
    $queue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $voltaCmd.Source
    $psi.Arguments = "uninstall --verbose `"$target`""
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
        Mode          = 'redirect'
        Process       = $proc
        Queue         = $queue
        Subscriptions = @($stdoutSub, $stderrSub)
        CommandLine   = "volta uninstall --verbose `"$target`""
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
        [string]$Phase = 'uninstall',
        [int]$ProcessMaxPercent = 40
    )

    while (-not (Test-NodeVoltaInstallProcessExited -State $State)) {
        Drain-NodeVoltaInstallQueue -State $State -Log $Log -LoadingState $LoadingState -Redraw $Redraw

        Update-NodeBrowseUninstallProgressFrame -Ui $Ui -LoadingState $LoadingState -Version $Version `
            -Phase $Phase -MaxPercent $ProcessMaxPercent
        & $Redraw

        if (Test-ToolkitShellToolbarLocked -Shell $Shell) {
            Drain-ShellLockedToolbarKeys -Shell $Shell -AllowLogScroll
        }

        $inputResult = & $FnLogInput -Shell $Shell -Log $Log -ViewportRows $LogViewportRows `
            -OnExitKey $OnExitKey -ScrollState $ScrollState
        if ($inputResult -eq 'scroll') {
            & $Redraw
        }

        Start-Sleep -Milliseconds 80
    }

    if ($State.Mode -eq 'redirect' -and $State.Process) {
        $State.Process.WaitForExit()
        Start-Sleep -Milliseconds 80
    }
    Drain-NodeVoltaInstallQueue -State $State -Log $Log -LoadingState $LoadingState -Redraw $Redraw `
        -Ui $Ui -OutputState @{ LoggedSuccess = $false; MinUnpackPercent = 0 }

    if ([int]$Ui.ItemSubPercent -lt $ProcessMaxPercent) {
        $Ui.ItemSubPercent = $ProcessMaxPercent
    }
    Update-NodeBrowseUninstallProgressFrame -Ui $Ui -LoadingState $LoadingState -Version $Version `
        -Phase $Phase -MaxPercent $ProcessMaxPercent
    & $Redraw

    return @((Complete-NodeVoltaInstallProcess -State $State))[-1]
}

function Invoke-NodeBrowseManualUninstallStep {
    param(
        $Ui,
        $Log,
        [string]$Version,
        $LoadingState,
        [scriptblock]$Redraw
    )

    Write-NodeBrowseInstallLogLine -Log $Log -Text (Get-NodeBrowseUninstallI18n -Key 'node.uninstall.logManualUninstallStart' -Vars @{
        version = $Version
    }) -Kind 'heading' -WithTimestamp
    Update-NodeBrowseUninstallProgressFrame -Ui $Ui -LoadingState $LoadingState -Version $Version -Phase 'uninstall'
    & $Redraw

    $startTick = [Environment]::TickCount
    while ([Environment]::TickCount - $startTick -lt 400) {
        Update-NodeBrowseUninstallProgressFrame -Ui $Ui -LoadingState $LoadingState -Version $Version `
            -Phase 'uninstall' -MaxPercent 40
        & $Redraw
        Start-Sleep -Milliseconds 80
    }
    if ([int]$Ui.ItemSubPercent -lt 40) {
        $Ui.ItemSubPercent = 40
    }
    & $Redraw
    return 0
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
        [scriptblock]$Redraw,
        $LoadingState = $null,
        [switch]$ManageInFlight,
        [int]$ProcessMaxPercent = 40
    )

    if (-not $LoadingState) {
        $loadingState = New-NodeBrowseInstallLoadingState
    }
    else {
        $loadingState = $LoadingState
    }

    $outputLines = $LoadingState['OutputLines']
    if ($null -eq $outputLines) {
        $outputLines = New-Object 'System.Collections.Generic.List[string]'
        $loadingState['OutputLines'] = $outputLines
    }

    if ($ManageInFlight) {
        $ui.ItemInFlight = $true
        $ui.ItemSubPercent = 0
        $ui.ExecuteStartTick = [Environment]::TickCount
        $loadingState['LastOutputTick'] = $ui.ExecuteStartTick
    }

    Update-NodeBrowseUninstallProgressFrame -Ui $Ui -LoadingState $loadingState -Version $Version -Phase $Phase
    & $Redraw

    $procState = & $StartProcess -Version $Version
    Write-NodeBrowseInstallLogLine -Log $Log -Text $procState.CommandLine -WithTimestamp
    & $Redraw

    $processMax = if ($Phase -eq 'promote') { 90 } else { $ProcessMaxPercent }

    return @{
        ExitCode    = @((Wait-NodeVoltaUninstallProcess -State $procState -Ui $Ui -LoadingState $loadingState `
            -Version $Version -Shell $Shell -Log $Log -LogViewportRows $LogViewportRows `
            -OnExitKey $OnExitKey -ScrollState $ScrollState -FnLogInput $FnLogInput `
            -Redraw $Redraw -Phase $Phase -ProcessMaxPercent $processMax))[-1]
        OutputLines = @($outputLines.ToArray())
        LoadingState = $loadingState
    }
}

function Write-NodeBrowseUninstallArtifactCleanupLog {
    param(
        $Log,
        [string]$Version,
        [hashtable]$Cleanup,
        [string]$StartKey,
        [string]$RemovedKey,
        [string]$FailedKey
    )

    Write-NodeBrowseInstallLogLine -Log $Log -Text (Get-NodeBrowseUninstallI18n -Key $StartKey -Vars @{
        version = $Version
    }) -Kind 'heading' -WithTimestamp

    foreach ($path in @($Cleanup.Removed)) {
        Write-NodeBrowseInstallLogLine -Log $Log -Text (Get-NodeBrowseUninstallI18n -Key $RemovedKey -Vars @{
            path = $path
        }) -Kind 'success'
    }
    foreach ($fail in @($Cleanup.Failed)) {
        Write-NodeBrowseInstallLogLine -Log $Log -Text (Get-NodeBrowseUninstallI18n -Key $FailedKey -Vars @{
            path  = $fail.Path
            error = $fail.Error
        }) -Kind 'error'
    }
}

function Invoke-NodeVoltaPostBatchDefaultRestore {
    param(
        $Ui,
        $Log,
        [hashtable]$Shell,
        [int]$LogViewportRows,
        [string]$InitialDefault,
        [array]$SuccessfullyUninstalledVersions,
        [hashtable]$OperationPlan,
        [scriptblock]$OnExitKey,
        [hashtable]$ScrollState,
        $FnLogInput,
        [scriptblock]$Redraw
    )

    if (-not $OperationPlan.DefaultRestorePlanned) { return }

    if (-not (Test-VoltaDefaultVersionWasUninstalled -InitialDefault $InitialDefault `
            -SuccessfullyUninstalledVersions $SuccessfullyUninstalledVersions)) {
        return
    }

    $finalInfo = Get-VoltaNodeVersionInfo
    $replacement = Get-VoltaNodeDefaultRestoreCandidate -InstalledMap $finalInfo.Map
    if ([string]::IsNullOrWhiteSpace($replacement)) { return }

    $stepIndex = [int]$OperationPlan.UninstallCount + 1
    $defaultName = Get-NodeBrowseUninstallI18n -Key 'node.uninstall.defaultRestoreItemName' -Vars @{
        version = $replacement
    }
    $loadingState = New-NodeBrowseInstallLoadingState
    $ui.ItemInFlight = $true
    $ui.ItemSubPercent = 0
    $ui.ExecuteStartTick = [Environment]::TickCount
    $ui.ProgressName = $defaultName
    $loadingState['LastOutputTick'] = $ui.ExecuteStartTick
    Update-NodeBrowseUninstallProgressFrame -Ui $Ui -LoadingState $loadingState -Version $replacement -Phase 'promote'
    & $Redraw

    if (-not (Test-VoltaNodeDefaultNeedsIntervention -InstalledMap $finalInfo.Map `
            -CurrentDefault $finalInfo.Default)) {
        Write-NodeBrowseInstallLogLine -Log $Log -Text '' -Kind 'separator'
        Write-NodeBrowseInstallLogLine -Log $Log -Text (Get-NodeBrowseUninstallI18n -Key 'node.uninstall.logDefaultRestoreVoltaOk' -Vars @{
            version = $replacement
        }) -Kind 'hint' -WithTimestamp
        Complete-NodeBrowseUninstallProgressAnimation -Ui $Ui -LoadingState $loadingState -Version $replacement `
            -Phase 'promote' -Redraw $Redraw -MinDurationMs 500 -FromPercent 0 -TargetPercent 100
        $ui.ProgressCurrent = $stepIndex
        $ui.ItemInFlight = $false
        $ui.ItemSubPercent = -1
        & $Redraw
        return
    }

    Write-NodeBrowseInstallLogLine -Log $Log -Text '' -Kind 'separator'
    Write-NodeBrowseInstallLogLine -Log $Log -Text (Get-NodeBrowseUninstallI18n -Key 'node.uninstall.logDefaultRestoreStart' -Vars @{
        version = $replacement
    }) -Kind 'heading' -WithTimestamp
    & $Redraw

    $promoteResult = Invoke-NodeVoltaProcessStep -Ui $Ui -Log $Log -Shell $Shell `
        -LogViewportRows $LogViewportRows -Version $replacement `
        -Phase 'promote' -StartProcess ${function:Start-NodeVoltaInstallProcess} `
        -OnExitKey $OnExitKey -ScrollState $ScrollState -FnLogInput $FnLogInput `
        -Redraw $Redraw -LoadingState $loadingState
    $promoteExit = [int]$promoteResult.ExitCode

    if ($promoteExit -eq 0) {
        Complete-NodeBrowseUninstallProgressAnimation -Ui $Ui -LoadingState $loadingState -Version $replacement `
            -Phase 'promote' -Redraw $Redraw -MinDurationMs 400 -FromPercent 90 -TargetPercent 100
        Write-NodeBrowseInstallLogLine -Log $Log -Text (Get-NodeBrowseUninstallI18n -Key 'node.uninstall.logDefaultRestoreSuccess' -Vars @{
            version = $replacement
        }) -Kind 'success' -WithTimestamp
    }
    else {
        if ([int]$Ui.ItemSubPercent -lt 90) {
            $Ui.ItemSubPercent = 90
        }
        Write-NodeBrowseInstallLogLine -Log $Log -Text (Get-NodeBrowseUninstallI18n -Key 'node.uninstall.logDefaultRestoreFailed' -Vars @{
            version = $replacement
            code    = [string]$promoteExit
        }) -Kind 'error' -WithTimestamp
    }

    $ui.ProgressCurrent = $stepIndex
    $ui.ItemInFlight = $false
    $ui.ItemSubPercent = -1
    & $Redraw
}

function Run-NodeBrowseUninstallOperation {
    param(
        [hashtable]$Shell,
        [array]$Items,
        [string]$SectionTitle = ''
    )

    Ensure-NodeBrowseUninstallShellUi

    $initialInfo = Get-VoltaNodeVersionInfo
    $ordered = @((Order-NodeVersionsForUninstall -VersionsToUninstall (
        Get-NodeBrowseUninstallPlanVersions -Items $Items -InstalledMap $initialInfo.Map
    ) -DefaultVersion $initialInfo.Default))
    $operationPlan = Get-NodeBrowseUninstallOperationPlan -InitialDefault $initialInfo.Default `
        -InstalledMap $initialInfo.Map -OrderedVersions $ordered
    $totalSteps = [int]$operationPlan.TotalSteps
    $uninstallCount = [int]$operationPlan.UninstallCount
    if ($uninstallCount -le 0) {
        return $null
    }

    $baseTitle = if (-not [string]::IsNullOrWhiteSpace($SectionTitle)) {
        $SectionTitle
    }
    else {
        $script:NodeActionSectionTitle
    }
    $toolRoot = Split-Path $PSScriptRoot -Parent
    $sectionTitle = Extend-NodeActionSectionTitle -BaseTitle $baseTitle -ToolRoot $toolRoot `
        -SubPhaseKey 'node.section.uninstallExecute'
    $ctx = Initialize-ToolkitDepBatchOperationView -Shell $Shell -SectionTitle $sectionTitle `
        -ProgressTotal $totalSteps -ReadyStatusText (Get-NodeBrowseUninstallI18n -Key 'node.uninstall.statusReady')

    $log = $ctx.Log
    $ui = $ctx.Ui
    $RedrawView = $ctx.RedrawView
    $onExitKey = $ctx.OnExitKey
    $uiPollState = $ctx.PollState
    $logContentViewportRows = $ctx.LogContentViewportRows
    $fnLogInput = $ctx.FnLogInput

    $successCount = 0
    $failedCount = 0
    $cancelled = $false
    $initialDefault = $initialInfo.Default
    $successfullyUninstalled = @()

    try {
        & $ctx.FnDrainStaleInput
        if (Get-Command Clear-ConsoleInputBuffer -ErrorAction SilentlyContinue) {
            Clear-ConsoleInputBuffer
        }

        Set-ToolkitShellToolbarLocked -Shell $Shell -Locked $true
        Start-ToolkitDepOperationBatch -Ui $ui
        Write-NodeBrowseInstallLogLine -Log $log -Text (Get-NodeBrowseUninstallI18n -Key 'node.uninstall.logBatchSelected' -Vars @{
            versions = ($ordered -join ', ')
            total    = $totalSteps
        }) -Kind 'heading' -WithTimestamp
        & $RedrawView

        for ($i = 0; $i -lt $uninstallCount; $i++) {
            if ($cancelled) { break }

            $ver = Normalize-NodeVersionLabel -Version ([string]$ordered[$i])
            if ([string]::IsNullOrWhiteSpace($ver)) {
                $failedCount++
                Write-NodeBrowseInstallLogLine -Log $log -Text (Get-NodeBrowseUninstallI18n -Key 'node.uninstall.logInvalidVersion' -Vars @{
                    index = ($i + 1)
                }) -Kind 'error' -WithTimestamp
                $ui.ProgressCurrent = $i + 1
                & $RedrawView
                continue
            }
            $target = "node@$ver"

            if ($ui.ProgressCurrent -gt 0) {
                Write-NodeBrowseInstallLogLine -Log $log -Text '' -Kind 'separator'
            }
            $sectionText = Get-I18n -Key 'page.depOperation.logSectionPackage' -Vars @{
                name  = $target
                index = ($i + 1)
                total = $totalSteps
            }
            Write-NodeBrowseInstallLogLine -Log $log -Text $sectionText -Kind 'section' -WithTimestamp

            $loadingState = New-NodeBrowseInstallLoadingState
            $ui.ProgressName = $target
            $ui.ItemInFlight = $true
            $ui.ItemSubPercent = 0
            $ui.ExecuteStartTick = [Environment]::TickCount
            $loadingState['LastOutputTick'] = $ui.ExecuteStartTick
            Update-NodeBrowseUninstallProgressFrame -Ui $ui -LoadingState $loadingState -Version $ver -Phase 'uninstall'
            Write-NodeBrowseInstallLogLine -Log $log -Text (Get-NodeBrowseUninstallI18n -Key 'node.uninstall.logStart' -Vars @{
                version = $ver
            }) -Kind 'heading' -WithTimestamp
            & $RedrawView

            $uninstallExit = 0
            $voltaCliUsed = $false
            if (Get-VoltaNodeCliUninstallSupported) {
                $voltaCliUsed = $true
                $stepResult = Invoke-NodeVoltaProcessStep -Ui $ui -Log $log -Shell $Shell `
                    -LogViewportRows $logContentViewportRows -Version $ver -Phase 'uninstall' `
                    -StartProcess ${function:Start-NodeVoltaUninstallProcess} -OnExitKey $onExitKey `
                    -ScrollState $uiPollState -FnLogInput $fnLogInput -Redraw $RedrawView `
                    -LoadingState $loadingState
                $uninstallExit = [int]$stepResult.ExitCode
                if (Test-VoltaNodeUninstallExitIgnorable -ExitCode $uninstallExit -OutputLines $stepResult.OutputLines) {
                    Set-VoltaNodeCliUninstallUnsupported
                    Write-NodeBrowseInstallLogLine -Log $log -Text (Get-NodeBrowseUninstallI18n -Key 'node.uninstall.logVoltaCliUnsupported' -Vars @{
                        version = $ver
                        code    = [string]$uninstallExit
                    }) -Kind 'hint' -WithTimestamp
                    & $RedrawView
                }
            }
            else {
                $uninstallExit = Invoke-NodeBrowseManualUninstallStep -Ui $ui -Log $log -Version $ver `
                    -LoadingState $loadingState -Redraw $RedrawView
            }

            Set-NodeBrowseUninstallItemProgress -Ui $ui -LoadingState $loadingState -Version $ver `
                -Percent 45 -Phase 'cleanup' -Redraw $RedrawView

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
            Set-NodeBrowseUninstallItemProgress -Ui $ui -LoadingState $loadingState -Version $ver `
                -Percent 55 -Phase 'cleanup' -Redraw $RedrawView

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

            Set-NodeBrowseUninstallItemProgress -Ui $ui -LoadingState $loadingState -Version $ver `
                -Percent 70 -Phase 'cleanup' -Redraw $RedrawView

            $invCleanup = Remove-VoltaNodeVersionInventoryFiles -Version $ver
            Write-NodeBrowseUninstallArtifactCleanupLog -Log $log -Version $ver -Cleanup $invCleanup `
                -StartKey 'node.uninstall.logInventoryCleanupStart' `
                -RemovedKey 'node.uninstall.logInventoryRemoved' `
                -FailedKey 'node.uninstall.logInventoryFailed'
            if ($invCleanup.Paths.Count -eq 0) {
                Write-NodeBrowseInstallLogLine -Log $log -Text (Get-NodeBrowseUninstallI18n -Key 'node.uninstall.logInventoryCleanupNone' -Vars @{
                    version = $ver
                }) -Kind 'hint'
            }

            $tmpCleanup = Remove-VoltaNodeVersionTmpArtifacts -Version $ver
            foreach ($path in @($tmpCleanup.Removed)) {
                Write-NodeBrowseInstallLogLine -Log $log -Text (Get-NodeBrowseUninstallI18n -Key 'node.uninstall.logTmpCleanupRemoved' -Vars @{
                    path = $path
                }) -Kind 'success'
            }
            foreach ($fail in @($tmpCleanup.Failed)) {
                Write-NodeBrowseInstallLogLine -Log $log -Text (Get-NodeBrowseUninstallI18n -Key 'node.uninstall.logCleanupFailed' -Vars @{
                    path  = $fail.Path
                    error = $fail.Error
                }) -Kind 'error'
            }

            Set-NodeBrowseUninstallItemProgress -Ui $ui -LoadingState $loadingState -Version $ver `
                -Percent 85 -Phase 'verify' -Redraw $RedrawView

            $absent = Test-VoltaNodeVersionAbsent -Version $ver
            $remainingPaths = Get-VoltaNodeVersionImagePaths -Version $ver
            $remainingInventory = Get-VoltaNodeVersionInventoryPaths -Version $ver
            $remainingTmp = Get-VoltaNodeVersionTmpArtifactPaths -Version $ver
            $artifactsAbsent = Test-VoltaNodeVersionLocalArtifactsAbsent -Version $ver
            $success = $absent -and $artifactsAbsent

            if ($success -and $voltaCliUsed -and $uninstallExit -ne 0) {
                Write-NodeBrowseInstallLogLine -Log $log -Text (Get-NodeBrowseUninstallI18n -Key 'node.uninstall.logVoltaExitIgnored' -Vars @{
                    version = $ver
                    code    = [string]$uninstallExit
                }) -Kind 'hint' -WithTimestamp
            }

            if ($success) {
                $successCount++
                $successfullyUninstalled += $ver
                Write-NodeBrowseInstallLogLine -Log $log -Text (Get-NodeBrowseUninstallI18n -Key 'node.uninstall.logSuccess' -Vars @{
                    version = $ver
                }) -Kind 'success' -WithTimestamp
                Set-NodeBrowseUninstallItemProgress -Ui $ui -LoadingState $loadingState -Version $ver `
                    -Percent 100 -Phase 'verify' -Redraw $RedrawView
            }
            else {
                $failedCount++
                if ($voltaCliUsed -and $uninstallExit -ne 0 -and -not $success) {
                    Write-NodeBrowseInstallLogLine -Log $log -Text (Get-NodeBrowseUninstallI18n -Key 'node.uninstall.logFailed' -Vars @{
                        version = $ver
                        code    = [string]$uninstallExit
                    }) -Kind 'error' -WithTimestamp
                }
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
                if ($remainingInventory.Count -gt 0) {
                    Write-NodeBrowseInstallLogLine -Log $log -Text (Get-NodeBrowseUninstallI18n -Key 'node.uninstall.logVerifyInventoryRemain' -Vars @{
                        version = $ver
                        paths   = ($remainingInventory -join '; ')
                    }) -Kind 'error' -WithTimestamp
                }
                if ($remainingTmp.Count -gt 0) {
                    Write-NodeBrowseInstallLogLine -Log $log -Text (Get-NodeBrowseUninstallI18n -Key 'node.uninstall.logVerifyTmpRemain' -Vars @{
                        version = $ver
                        paths   = ($remainingTmp -join '; ')
                    }) -Kind 'error' -WithTimestamp
                }
                Set-NodeBrowseUninstallItemProgress -Ui $ui -LoadingState $loadingState -Version $ver `
                    -Percent 90 -Phase 'verify' -Redraw $RedrawView
            }

            $ui.ProgressCurrent = $i + 1
            $ui.ItemInFlight = $false
            $ui.ItemSubPercent = -1
            & $RedrawView
        }

        if (-not $cancelled) {
            Invoke-NodeVoltaPostBatchDefaultRestore -Ui $ui -Log $log -Shell $Shell `
                -LogViewportRows $logContentViewportRows -InitialDefault $initialDefault `
                -SuccessfullyUninstalledVersions $successfullyUninstalled -OperationPlan $operationPlan `
                -OnExitKey $onExitKey -ScrollState $uiPollState -FnLogInput $fnLogInput -Redraw $RedrawView
        }

        if (-not $cancelled) {
            Set-ToolkitDepOperationBatchCompleteUi -Ui $ui -Intent uninstall -TotalCount $uninstallCount `
                -SuccessCount $successCount -FailedCount $failedCount -ProgressCurrent $totalSteps
        }

        return Invoke-ToolkitDepBatchOperationWaitLoop -Context $ctx
    }
    finally {
        Clear-ToolkitDepBatchOperationView -Context $ctx
    }
}
