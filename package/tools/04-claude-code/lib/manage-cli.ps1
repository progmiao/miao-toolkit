# claude-code — 安装/更新 CLI 统一流程（先进入页面，再检测与执行）

function Invoke-ClaudeCodeCliSyncPage {
    param(
        [hashtable]$Shell,
        [string]$SectionTitle,
        [string]$ToolRoot,
        [string]$CoreLib,
        [ValidateSet('install', 'update')]
        [string]$EntryPoint = 'install'
    )

    Import-ClaudeCodeWingetCore -CoreLib $CoreLib

    $readyKey = if ($EntryPoint -eq 'update') {
        'claude-code.cli.updateStatusReady'
    }
    else {
        'claude-code.cli.installStatusReady'
    }
    $readyText = Get-ClaudeCodeI18n -ToolRoot $ToolRoot -Key $readyKey

    $ctx = Initialize-ToolkitDepBatchOperationView -Shell $Shell -SectionTitle $SectionTitle `
        -ProgressTotal 1 -ReadyStatusText $readyText

    $log = $ctx.Log
    $ui = $ctx.Ui
    $RedrawView = $ctx.RedrawView
    $outcome = @{
        Intent        = 'install'
        SuccessCount  = 0
        FailedCount   = 0
        WorkPerformed = $false
    }

    try {
        & $ctx.FnDrainStaleInput
        if (Get-Command Clear-ConsoleInputBuffer -ErrorAction SilentlyContinue) {
            Clear-ConsoleInputBuffer
        }

        Set-ToolkitShellToolbarLocked -Shell $Shell -Locked $true
        $ui.ItemInFlight = $true
        $ui.ExecuteStartTick = [Environment]::TickCount
        Start-ToolkitDepOperationBatch -Ui $ui
        & $RedrawView

        $wingetOutputState = New-ClaudeCodeWingetOutputState -Verb 'install'
        $fnApplyProgress = ${function:Update-ClaudeCodeDepProgressFromDecision}
        $fnSyncProgress = ${function:Sync-ClaudeCodeDepProgressChrome}

        $pump = {
            Invoke-ToolkitDepBatchOperationUiPump -Context $ctx
            & $fnSyncProgress -Ui $ui -WingetOutputState $wingetOutputState
        }.GetNewClosure()
        $fnWriteLog = ${function:Write-ClaudeCodeBatchLogLine}

        & $fnApplyProgress -Ui $ui -WingetOutputState $wingetOutputState `
            -Decision @{ ProgressPhase = 'detect'; RedrawOnly = $true }

        $detectText = Get-ClaudeCodeI18n -ToolRoot $ToolRoot -Key 'claude-code.cli.detectStatus'
        Set-ToolkitDepOperationInFlightStatus -Ui $ui -MainText $detectText -AdvanceSpinner
        & $RedrawView
        & $pump

        & $fnWriteLog -Log $log -Text $detectText -Kind 'heading' -WithTimestamp

        if (Test-ClaudeCodeCliAvailable) {
            $versionLine = Get-ClaudeCodeCliVersionOutput
            if ($versionLine) {
                & $fnWriteLog -Log $log -Text (Get-ClaudeCodeI18n -ToolRoot $ToolRoot `
                    -Key 'claude-code.cli.detectVersionCommand' -Vars @{ line = $versionLine }) `
                    -Kind 'text' -WithTimestamp
            }
        }
        & $pump

        & $fnApplyProgress -Ui $ui -WingetOutputState $wingetOutputState `
            -Decision @{ ProgressPhase = 'run'; RedrawOnly = $true }

        $installed = Test-ClaudeCodeInstalled -CoreLib $CoreLib
        & $pump

        if (-not $installed) {
            & $fnWriteLog -Log $log -Text (Get-ClaudeCodeI18n -ToolRoot $ToolRoot `
                -Key 'claude-code.cli.detectNotInstalled') -Kind 'text' -WithTimestamp
            $outcome.Intent = 'install'
            $outcome.WorkPerformed = $true

            $streamResult = Invoke-ClaudeCodeWingetStreamWork -Context $ctx -Verb install `
                -ToolRoot $ToolRoot -SuccessLogKey 'claude-code.cli.installSuccess' `
                -FailureLogKey 'claude-code.cli.installFailed' -Pump $pump `
                -WingetOutputState $wingetOutputState
            if ($streamResult.Ok) { $outcome.SuccessCount = 1 }
            else { $outcome.FailedCount = 1 }
        }
        else {
            $version = Get-ClaudeCodeInstalledVersion
            $versionLabel = if ($version) { $version } else { '?' }
            & $fnWriteLog -Log $log -Text (Get-ClaudeCodeI18n -ToolRoot $ToolRoot `
                -Key 'claude-code.cli.detectInstalled' -Vars @{ version = $versionLabel }) `
                -Kind 'text' -WithTimestamp
            & $pump

            Set-ToolkitDepOperationInFlightStatus -Ui $ui -MainText (Get-ClaudeCodeI18n -ToolRoot $ToolRoot `
                -Key 'claude-code.cli.detectUpdateStatus') -AdvanceSpinner
            & $RedrawView
            & $pump

            & $fnApplyProgress -Ui $ui -WingetOutputState $wingetOutputState `
                -Decision @{ ProgressPhase = 'preflight'; RedrawOnly = $true }

            $updateAvailable = Test-ClaudeCodeUpdateAvailable -CoreLib $CoreLib
            & $pump

            if ($updateAvailable) {
                $wingetVerb = Resolve-ClaudeCodeWingetInstallVerb
                & $fnWriteLog -Log $log -Text (Get-ClaudeCodeI18n -ToolRoot $ToolRoot `
                    -Key 'claude-code.cli.detectUpdateAvailable') -Kind 'text' -WithTimestamp
                $outcome.Intent = if ($wingetVerb -eq 'upgrade') { 'update' } else { 'install' }
                $outcome.WorkPerformed = $true

                $successKey = if ($wingetVerb -eq 'upgrade') {
                    'claude-code.cli.updateSuccess'
                }
                else {
                    'claude-code.cli.installSuccess'
                }
                $failureKey = if ($wingetVerb -eq 'upgrade') {
                    'claude-code.cli.updateFailed'
                }
                else {
                    'claude-code.cli.installFailed'
                }

                $streamResult = Invoke-ClaudeCodeWingetStreamWork -Context $ctx -Verb $wingetVerb `
                    -ToolRoot $ToolRoot -SuccessLogKey $successKey -FailureLogKey $failureKey -Pump $pump `
                    -WingetOutputState $wingetOutputState
                if ($streamResult.Ok) { $outcome.SuccessCount = 1 }
                else { $outcome.FailedCount = 1 }
            }
            else {
                & $fnApplyProgress -Ui $ui -WingetOutputState $wingetOutputState `
                    -Decision @{ ProgressPhase = 'wingetSuccess'; RedrawOnly = $true }
                & $fnWriteLog -Log $log -Text (Get-ClaudeCodeI18n -ToolRoot $ToolRoot `
                    -Key 'claude-code.cli.alreadyLatest' -Vars @{ version = $versionLabel }) `
                    -Kind 'success' -WithTimestamp
                $outcome.Intent = if ($EntryPoint -eq 'update') { 'update' } else { 'install' }
                $outcome.SuccessCount = 1
            }
        }

        $ui.ItemInFlight = $false
        $ui.ItemSubPercent = -1
        $ui.ProgressCurrent = 1

        Set-ToolkitDepOperationBatchCompleteUi -Ui $ui -Intent $outcome.Intent `
            -TotalCount 1 -SuccessCount $outcome.SuccessCount -FailedCount $outcome.FailedCount `
            -ProgressCurrent 1

        return Invoke-ToolkitDepBatchOperationWaitLoop -Context $ctx
    }
    finally {
        Clear-ToolkitDepBatchOperationView -Context $ctx
    }
}
