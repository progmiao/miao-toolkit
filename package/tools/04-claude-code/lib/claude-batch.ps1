# claude-code — 批量执行（WinGet / 插件 / 配置）

function Write-ClaudeCodeBatchLogLine {
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

function Invoke-ClaudeCodeBatchOperation {
    param(
        [hashtable]$Shell,
        [string]$SectionTitle,
        [string]$ReadyStatusText,
        [array]$Items,
        [scriptblock]$InvokeItem,
        [scriptblock]$GetItemLabel,
        [scriptblock]$GetSuccessLog,
        [scriptblock]$GetFailureLog,
        [ValidateSet('install', 'update', 'uninstall', 'init', 'configure')]
        [string]$Intent = 'install',
        [ValidateSet('back', 'none')]
        [string]$QuitNavAction = 'back'
    )

    $total = @($Items).Count
    if ($total -le 0) {
        return $null
    }

    $ctx = Initialize-ToolkitDepBatchOperationView -Shell $Shell -SectionTitle $SectionTitle `
        -ProgressTotal $total -ReadyStatusText $ReadyStatusText

    $log = $ctx.Log
    $ui = $ctx.Ui
    $RedrawView = $ctx.RedrawView
    $successCount = 0
    $failedCount = 0

    try {
        & $ctx.FnDrainStaleInput
        if (Get-Command Clear-ConsoleInputBuffer -ErrorAction SilentlyContinue) {
            Clear-ConsoleInputBuffer
        }

        Set-ToolkitShellToolbarLocked -Shell $Shell -Locked $true
        Start-ToolkitDepOperationBatch -Ui $ui
        & $RedrawView

        for ($i = 0; $i -lt $total; $i++) {
            $item = $Items[$i]
            $label = & $GetItemLabel $item
            if ($ui.ProgressCurrent -gt 0) {
                Write-ClaudeCodeBatchLogLine -Log $log -Text '' -Kind 'separator'
            }

            $sectionText = Get-I18n -Key 'page.depOperation.logSectionPackage' -Vars @{
                name  = $label
                index = ($i + 1)
                total = $total
            }
            Write-ClaudeCodeBatchLogLine -Log $log -Text $sectionText -Kind 'section' -WithTimestamp

            $ui.ProgressName = $label
            $ui.ItemInFlight = $true
            $ui.ExecuteStartTick = [Environment]::TickCount
            Set-ToolkitDepOperationInFlightStatus -Ui $ui -MainText $label -AdvanceSpinner
            & $RedrawView

            $itemPump = {
                Invoke-ToolkitDepBatchOperationUiPump -Context $ctx
            }.GetNewClosure()

            try {
                $result = & $InvokeItem $item $itemPump
                $ok = $true
                if ($null -ne $result) {
                    if ($result -is [bool]) {
                        $ok = [bool]$result
                    }
                    elseif ($result.PSObject.Properties['Success']) {
                        $ok = [bool]$result.Success
                    }
                    elseif ($result.PSObject.Properties['ExitCode']) {
                        $ok = ([int]$result.ExitCode -eq 0)
                    }
                }

                if ($ok) {
                    $successCount++
                    $line = & $GetSuccessLog $item $result
                    Write-ClaudeCodeBatchLogLine -Log $log -Text $line -Kind 'success' -WithTimestamp
                }
                else {
                    $failedCount++
                    $line = & $GetFailureLog $item $result
                    Write-ClaudeCodeBatchLogLine -Log $log -Text $line -Kind 'error' -WithTimestamp
                }
            }
            catch {
                $failedCount++
                $detail = $_.Exception.Message
                if ([string]::IsNullOrWhiteSpace($detail)) {
                    $detail = $_.Exception.GetType().FullName
                }
                Write-ClaudeCodeBatchLogLine -Log $log -Text (& $GetFailureLog $item $detail) `
                    -Kind 'error' -WithTimestamp
            }
            finally {
                $ui.ItemInFlight = $false
                $ui.ItemSubPercent = -1
                $ui.ProgressCurrent = $i + 1
                & $RedrawView
            }
        }

        Set-ToolkitDepOperationBatchCompleteUi -Ui $ui -Intent $Intent `
            -TotalCount $total -SuccessCount $successCount -FailedCount $failedCount `
            -ProgressCurrent $total

        return Invoke-ToolkitDepBatchOperationWaitLoop -Context $ctx -QuitNavAction $QuitNavAction
    }
    finally {
        Clear-ToolkitDepBatchOperationView -Context $ctx
    }
}

function New-ClaudeCodeWingetOutputState {
    param(
        [ValidateSet('install', 'upgrade', 'uninstall')]
        [string]$Verb
    )

    $executeAction = if ($Verb -eq 'uninstall') { 'Uninstall' } else { 'Install' }
    return @{
        LastLoggedPercent        = -1
        LoggedPhases             = @{}
        SubstantiveLogCount      = 0
        PercentStage             = ''
        LoggedDownloadComplete   = $false
        LoggedInstallComplete    = $false
        WingetOutputSeen         = $false
        WingetInstallSilent      = $true
        ExecuteAction            = $executeAction
        InstallerAwaitingDialog  = $false
        InstallerPromptDismissed = $false
        InstallStarted           = $false
        InstallStartedTick       = 0
        WingetOperationSucceeded = $false
    }
}

function Update-ClaudeCodeDepProgressFromDecision {
    param(
        $Ui,
        $WingetOutputState,
        $Decision
    )

    if ($null -eq $Ui -or $null -eq $WingetOutputState -or $null -eq $Decision) { return }

    if (Get-Command Update-ToolkitDepWingetProgressFromDecision -ErrorAction SilentlyContinue) {
        Update-ToolkitDepWingetProgressFromDecision -Ui $Ui -WingetOutputState $WingetOutputState -Decision $Decision
        return
    }

    if ([int]$Decision.Percent -lt 0) { return }

    $executeAction = if ([string]$WingetOutputState['ExecuteAction'] -eq 'Uninstall') { 'Uninstall' } else { 'Install' }
    $stage = [string]$WingetOutputState['PercentStage']
    if ([string]::IsNullOrWhiteSpace($stage)) { $stage = 'download' }

    if (-not (Get-Command Convert-ToolkitDepWingetPercentToProgress -ErrorAction SilentlyContinue)) {
        return
    }

    $mapped = Convert-ToolkitDepWingetPercentToProgress -Percent ([int]$Decision.Percent) -Stage $stage `
        -ExecuteAction $executeAction
    if ($mapped -ge 0 -and (Get-Command Apply-ToolkitDepWingetProgressUpdate -ErrorAction SilentlyContinue)) {
        Apply-ToolkitDepWingetProgressUpdate -Ui $Ui -WingetOutputState $WingetOutputState -Target $mapped
    }
}

function Sync-ClaudeCodeDepProgressChrome {
    param(
        $Ui,
        $WingetOutputState
    )

    if ($null -eq $Ui -or $null -eq $WingetOutputState -or -not $Ui.ItemInFlight) { return }

    if (-not (Get-Command Sync-ToolkitDepWingetItemProgress -ErrorAction SilentlyContinue)) { return }

    $elapsed = 0
    if ([int]$Ui.ExecuteStartTick -gt 0) {
        $elapsed = [int][Math]::Floor(([Environment]::TickCount - [int]$Ui.ExecuteStartTick) / 1000.0)
    }
    Sync-ToolkitDepWingetItemProgress -Ui $Ui -WingetOutputState $WingetOutputState -ElapsedSeconds $elapsed
}

function Invoke-ClaudeCodeWingetStreamWork {
    param(
        $Context,
        [ValidateSet('install', 'upgrade', 'uninstall')]
        [string]$Verb,
        [string]$ToolRoot,
        [string]$SuccessLogKey,
        [string]$FailureLogKey,
        [scriptblock]$Pump,
        $WingetOutputState = $null
    )

    $log = $Context.Log
    $ui = $Context.Ui
    $RedrawView = $Context.RedrawView
    $label = Get-ClaudeCodeWingetPackageId
    $fnWriteLog = ${function:Write-ClaudeCodeBatchLogLine}

    $sectionText = Get-I18n -Key 'page.depOperation.logSectionPackage' -Vars @{
        name  = $label
        index = 1
        total = 1
    }
    & $fnWriteLog -Log $log -Text $sectionText -Kind 'section' -WithTimestamp

    $ui.ProgressName = $label
    $ui.ItemInFlight = $true
    $ui.ExecuteStartTick = [Environment]::TickCount
    Set-ToolkitDepOperationInFlightStatus -Ui $ui -MainText $label -AdvanceSpinner
    & $RedrawView

    $wingetOutputState = if ($WingetOutputState) { $WingetOutputState } else { New-ClaudeCodeWingetOutputState -Verb $Verb }
    $fnCleanLine = Get-Command Get-WingetStreamLineCleanText -ErrorAction SilentlyContinue
    $fnIsSpinner = Get-Command Test-WingetStreamLineIsSpinnerOnly -ErrorAction SilentlyContinue
    $fnIsProgressVisual = Get-Command Test-WingetDepStreamLineIsProgressVisual -ErrorAction SilentlyContinue
    $fnGetPercent = Get-Command Get-WingetDepStreamLinePercent -ErrorAction SilentlyContinue
    $fnGetTransfer = Get-Command Format-WingetDepStreamLineTransferStatus -ErrorAction SilentlyContinue
    $fnGetOutputDecision = Get-Command Get-ToolkitDepWingetOutputDecision -ErrorAction SilentlyContinue
    $fnApplyProgress = ${function:Update-ClaudeCodeDepProgressFromDecision}

    $onOutputLine = {
        param($Line)

        if ([string]::IsNullOrWhiteSpace($Line)) { return }

        $raw = if ($fnCleanLine) {
            & $fnCleanLine -Line $Line
        }
        else {
            [string]$Line
        }
        if ([string]::IsNullOrWhiteSpace($raw)) { return }

        if ($fnIsSpinner -and (& $fnIsSpinner -Line $raw)) {
            $wingetOutputState['WingetOutputSeen'] = $true
            & $Pump
            & $RedrawView
            return
        }

        if ($fnIsProgressVisual -and (& $fnIsProgressVisual -Line $raw)) {
            $wingetOutputState['WingetOutputSeen'] = $true
            $pct = if ($fnGetPercent) { [int](& $fnGetPercent -Line $raw) } else { -1 }
            $decision = if ($fnGetOutputDecision) {
                & $fnGetOutputDecision -Line $Line -OutputState $wingetOutputState
            }
            else {
                @{ Percent = $pct; RedrawOnly = $true; LogText = $null; StatusText = $null }
            }
            if ($pct -ge 0) { $decision.Percent = $pct }
            & $fnApplyProgress -Ui $ui -WingetOutputState $wingetOutputState -Decision $decision

            $statusText = if ($fnGetTransfer) { & $fnGetTransfer -Line $raw } else { $null }
            if ([string]::IsNullOrWhiteSpace($statusText)) {
                $overallPct = [int]$ui.ItemSubPercent
                if ($overallPct -ge 0) {
                    $statusText = Get-I18n -Key 'page.depOperation.statusDownload' -Vars @{ percent = $overallPct }
                }
            }
            if (-not [string]::IsNullOrWhiteSpace($statusText)) {
                Set-ToolkitDepOperationInFlightStatus -Ui $ui -MainText $statusText -AdvanceSpinner
            }

            & $Pump
            & $RedrawView
            return
        }

        $wingetOutputState['WingetOutputSeen'] = $true
        $decision = if ($fnGetOutputDecision) {
            & $fnGetOutputDecision -Line $Line -OutputState $wingetOutputState
        }
        else {
            @{
                LogText    = $raw
                StatusText = $raw
                Percent    = -1
                RedrawOnly = $false
            }
        }

        if ([int]$decision.Percent -ge 0 -or $decision.ProgressPhase) {
            & $fnApplyProgress -Ui $ui -WingetOutputState $wingetOutputState -Decision $decision
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$decision.StatusText)) {
            Set-ToolkitDepOperationInFlightStatus -Ui $ui -MainText ([string]$decision.StatusText) -AdvanceSpinner
        }

        $needsRedraw = $false
        if ($decision.PendingLogTexts) {
            foreach ($pendingText in @($decision.PendingLogTexts)) {
                if ([string]::IsNullOrWhiteSpace([string]$pendingText)) { continue }
                & $fnWriteLog -Log $log -Text ([string]$pendingText) -Kind 'text' -WithTimestamp
                $needsRedraw = $true
            }
        }

        if ($decision.LogText -and -not $decision.RedrawOnly) {
            $logText = [string]$decision.LogText
            $skipSpinner = ($fnIsSpinner -and (& $fnIsSpinner -Line $raw)) -and ($logText -eq $raw)
            if (-not $skipSpinner) {
                & $fnWriteLog -Log $log -Text $logText -Kind 'text' -WithTimestamp
                $needsRedraw = $true
            }
        }

        if ($needsRedraw) {
            & $RedrawView
        }
        else {
            & $Pump
            & $RedrawView
        }
    }.GetNewClosure()

    $wingetResult = Invoke-ClaudeCodeWingetProcess -Verb $Verb -OnUiPoll $Pump `
        -OnChromePulse { & $RedrawView } -OnOutputLine $onOutputLine

    $ok = $false
    if ($wingetResult) {
        if ($wingetResult.PSObject.Properties['AlreadyLatest'] -and [bool]$wingetResult.AlreadyLatest) {
            $ok = $true
            & $fnWriteLog -Log $log -Text (Get-ClaudeCodeI18n -ToolRoot $ToolRoot `
                -Key 'claude-code.cli.alreadyLatest' -Vars @{
                    version = if (Get-ClaudeCodeInstalledVersion) { Get-ClaudeCodeInstalledVersion } else { '?' }
                }) -Kind 'success' -WithTimestamp
        }
        elseif ($wingetResult.PSObject.Properties['Success']) {
            $ok = [bool]$wingetResult.Success
        }
        else {
            $ok = ([int]$wingetResult.ExitCode -eq 0)
        }
    }

    if ($ok -and -not ($wingetResult -and $wingetResult.AlreadyLatest)) {
        & $fnWriteLog -Log $log -Text (Get-ClaudeCodeI18n -ToolRoot $ToolRoot -Key $SuccessLogKey) `
            -Kind 'success' -WithTimestamp
    }
    else {
        $detail = ''
        if ($wingetResult) {
            if ($wingetResult.Lines) {
                $detail = ($wingetResult.Lines | Select-Object -Last 3 | ForEach-Object { [string]$_ }) -join ' '
            }
            if ([string]::IsNullOrWhiteSpace($detail) -and $wingetResult.Output) {
                $detail = [string]$wingetResult.Output
            }
            if ([string]::IsNullOrWhiteSpace($detail) -and $null -ne $wingetResult.ExitCode) {
                $detail = "exit $($wingetResult.ExitCode)"
            }
        }
        if ([string]::IsNullOrWhiteSpace($detail)) { $detail = 'unknown error' }
        & $fnWriteLog -Log $log -Text (Get-ClaudeCodeI18n -ToolRoot $ToolRoot -Key $FailureLogKey `
            -Vars @{ detail = $detail }) -Kind 'error' -WithTimestamp
    }

    return @{
        Ok     = $ok
        Result = $wingetResult
    }
}

function Invoke-ClaudeCodeWingetBatchPage {
    param(
        [hashtable]$Shell,
        [string]$SectionTitle,
        [string]$ReadyStatusText,
        [ValidateSet('install', 'upgrade', 'uninstall')]
        [string]$Verb,
        [string]$SuccessLogKey,
        [string]$FailureLogKey,
        [string]$ToolRoot,
        [string]$CoreLib
    )

    Import-ClaudeCodeWingetCore -CoreLib $CoreLib

    $intent = if ($Verb -eq 'upgrade') { 'update' } else { $Verb }
    $ctx = Initialize-ToolkitDepBatchOperationView -Shell $Shell -SectionTitle $SectionTitle `
        -ProgressTotal 1 -ReadyStatusText $ReadyStatusText

    $ui = $ctx.Ui
    $RedrawView = $ctx.RedrawView
    $successCount = 0
    $failedCount = 0

    try {
        & $ctx.FnDrainStaleInput
        if (Get-Command Clear-ConsoleInputBuffer -ErrorAction SilentlyContinue) {
            Clear-ConsoleInputBuffer
        }

        Set-ToolkitShellToolbarLocked -Shell $Shell -Locked $true
        Start-ToolkitDepOperationBatch -Ui $ui
        & $RedrawView

        $wingetOutputState = New-ClaudeCodeWingetOutputState -Verb $Verb
        $fnSyncProgress = ${function:Sync-ClaudeCodeDepProgressChrome}
        $pump = {
            Invoke-ToolkitDepBatchOperationUiPump -Context $ctx
            & $fnSyncProgress -Ui $ui -WingetOutputState $wingetOutputState
        }.GetNewClosure()
        $streamResult = Invoke-ClaudeCodeWingetStreamWork -Context $ctx -Verb $Verb `
            -ToolRoot $ToolRoot -SuccessLogKey $SuccessLogKey -FailureLogKey $FailureLogKey `
            -Pump $pump -WingetOutputState $wingetOutputState
        if ($streamResult -and $streamResult.Ok) { $successCount = 1 }
        else { $failedCount = 1 }

        $ui.ItemInFlight = $false
        $ui.ItemSubPercent = -1
        $ui.ProgressCurrent = 1

        Set-ToolkitDepOperationBatchCompleteUi -Ui $ui -Intent $intent `
            -TotalCount 1 -SuccessCount $successCount -FailedCount $failedCount -ProgressCurrent 1

        return Invoke-ToolkitDepBatchOperationWaitLoop -Context $ctx
    }
    finally {
        Clear-ToolkitDepBatchOperationView -Context $ctx
    }
}

function Invoke-ClaudeCodeInitBatchPage {
    param(
        [hashtable]$Shell,
        [string]$SectionTitle,
        [string]$ToolRoot
    )

    $steps = @(
        @{
            Key    = 'claude-code.init.stepDisableLogin'
            Action = { Apply-ClaudeCodeInitDefaults }
        },
        @{
            Key    = 'claude-code.init.stepWriteSettings'
            Action = { Sync-ClaudeCodeSettingsFromSecrets | Out-Null; Test-ClaudeCodeSettingsFile }
        },
        @{
            Key    = 'claude-code.init.stepVerify'
            Action = {
                if (Test-ClaudeCodeCliAvailable) {
                    return ($null -ne (Get-ClaudeCodeCliVersion))
                }
                return (Test-ClaudeCodeSettingsFile)
            }
        }
    )

    foreach ($preset in @(Get-ClaudeCodeMarketplacePresets -ToolRoot $ToolRoot)) {
        $source = [string]$preset.Source
        $label = [string]$preset.Label
        $steps += @{
            Key    = 'claude-code.init.stepRegisterMarketplace'
            Vars   = @{ source = $label }
            Source = $source
        }
    }

    return Invoke-ClaudeCodeBatchOperation -Shell $Shell -SectionTitle $SectionTitle `
        -ReadyStatusText (Get-ClaudeCodeI18n -ToolRoot $ToolRoot -Key 'claude-code.init.statusReady') `
        -Intent init -Items $steps `
        -GetItemLabel {
            param($Item)
            if ($Item.Vars) {
                return Get-ClaudeCodeI18n -ToolRoot $ToolRoot -Key ([string]$Item.Key) -Vars $Item.Vars
            }
            return Get-ClaudeCodeI18n -ToolRoot $ToolRoot -Key ([string]$Item.Key)
        } `
        -InvokeItem {
            param($Item, $Pump)
            if ($Item.Source) {
                $output = Invoke-ClaudeCodeMarketplacePresetRegister -Source ([string]$Item.Source) `
                    -OnUiPoll $Pump -OnChromePulse $Pump
            }
            else {
                $output = & $Item.Action
            }
            $ok = $true
            $detail = ''
            if ($output -is [bool]) {
                $ok = [bool]$output
            }
            elseif ($output -is [pscustomobject] -and $output.PSObject.Properties['Success']) {
                $ok = [bool]$output.Success
                if ($output.PSObject.Properties['Path']) {
                    $detail = [string]$output.Path
                }
            }
            elseif ($null -eq $output) {
                $ok = $false
            }
            elseif ($output -is [string]) {
                $detail = $output
            }
            if (-not $ok -and [string]::IsNullOrWhiteSpace($detail) -and $Item.Source `
                    -and -not (Test-ClaudeCodeCliAvailable)) {
                $detail = (Get-ClaudeCodeI18n -ToolRoot $ToolRoot -Key 'claude-code.cli.notInstalled')
            }
            return [pscustomobject]@{
                Success = $ok
                Path    = $detail
            }
        } `
        -GetSuccessLog {
            param($Item, $Result)
            $stepLabel = if ($Item.Vars) {
                Get-ClaudeCodeI18n -ToolRoot $ToolRoot -Key ([string]$Item.Key) -Vars $Item.Vars
            }
            else {
                Get-ClaudeCodeI18n -ToolRoot $ToolRoot -Key ([string]$Item.Key)
            }
            Get-ClaudeCodeI18n -ToolRoot $ToolRoot -Key 'claude-code.init.logSuccess' `
                -Vars @{ step = $stepLabel }
        } `
        -GetFailureLog {
            param($Item, $Result)
            $detail = if ($Result -is [string]) {
                $Result
            }
            elseif ($Result -is [pscustomobject] -and $Result.PSObject.Properties['Path']) {
                [string]$Result.Path
            }
            else {
                [string]$Result
            }
            $stepLabel = if ($Item.Vars) {
                Get-ClaudeCodeI18n -ToolRoot $ToolRoot -Key ([string]$Item.Key) -Vars $Item.Vars
            }
            else {
                Get-ClaudeCodeI18n -ToolRoot $ToolRoot -Key ([string]$Item.Key)
            }
            Get-ClaudeCodeI18n -ToolRoot $ToolRoot -Key 'claude-code.init.logFailed' -Vars @{
                step   = $stepLabel
                detail = $detail
            }
        }
}
