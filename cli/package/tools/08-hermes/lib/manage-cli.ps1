# hermes — 安装/更新 CLI 统一流程（先进入页面，再检测与执行）

function Invoke-HermesCliSyncPage {
    param(
        [hashtable]$Shell,
        [string]$SectionTitle,
        [string]$ToolRoot,
        [string]$CoreLib
    )

    Import-HermesDepProgressCore -CoreLib $CoreLib

    $readyText = Get-HermesI18n -ToolRoot $ToolRoot -Key 'hermes.cli.installStatusReady'

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
        $ui.ItemSubPercent = 0
        $ui.ExecuteStartTick = [Environment]::TickCount
        Start-ToolkitDepOperationBatch -Ui $ui
        & $RedrawView

        $installed = Test-HermesInstalled
        $progressFlow = if ($installed) { 'sync' } else { 'fresh-install' }
        $progress = New-HermesProgressState -Flow $progressFlow
        Set-HermesProgressPhase -State $progress -Ui $ui -Phase 'detect' -Jump

        $pump = New-HermesProgressPump -Context $ctx -State $progress -Ui $ui

        $detectText = Get-HermesI18n -ToolRoot $ToolRoot -Key 'hermes.cli.detectStatus'
        Set-ToolkitDepOperationInFlightStatus -Ui $ui -MainText $detectText -AdvanceSpinner
        & $RedrawView
        & $pump

        Write-HermesProgressLogLine -Log $log -Text $detectText -Kind 'heading' -WithTimestamp `
            -ProgressState $progress -Ui $ui

        Write-HermesDesktopNoticeIfNeeded -Log $log -ToolRoot $ToolRoot -CoreLib $CoreLib
        if (Test-HermesWingetDesktopInstalled -CoreLib $CoreLib) {
            Bump-HermesProgressFromLog -State $progress -Ui $ui
        }
        & $pump

        if ($installed) {
            Set-HermesProgressPhase -State $progress -Ui $ui -Phase 'version'
            $versionLine = Get-HermesCliVersionOutput
            if ($versionLine) {
                Write-HermesProgressLogLine -Log $log -Text (Get-HermesI18n -ToolRoot $ToolRoot `
                    -Key 'hermes.cli.detectVersionCommand' -Vars @{ line = $versionLine }) `
                    -Kind 'text' -WithTimestamp -ProgressState $progress -Ui $ui
            }
            & $pump
        }

        & $pump

        if (-not $installed) {
            Write-HermesProgressLogLine -Log $log -Text (Get-HermesI18n -ToolRoot $ToolRoot `
                -Key 'hermes.cli.detectNotInstalled') -Kind 'text' -WithTimestamp `
                -ProgressState $progress -Ui $ui
            $outcome.Intent = 'install'
            $outcome.WorkPerformed = $true

            $streamResult = Invoke-HermesInstallStreamWork -Context $ctx -ToolRoot $ToolRoot `
                -SuccessLogKey 'hermes.cli.installSuccess' -FailureLogKey 'hermes.cli.installFailed' `
                -Pump $pump -ProgressState $progress
            if ($streamResult.Ok) { $outcome.SuccessCount = 1 }
            else { $outcome.FailedCount = 1 }
        }
        else {
            $version = Get-HermesInstalledVersion
            $versionLabel = if ($version) { $version } else { '?' }
            Write-HermesProgressLogLine -Log $log -Text (Get-HermesI18n -ToolRoot $ToolRoot `
                -Key 'hermes.cli.detectInstalled' -Vars @{ version = $versionLabel }) `
                -Kind 'text' -WithTimestamp -ProgressState $progress -Ui $ui
            & $pump

            Set-HermesProgressPhase -State $progress -Ui $ui -Phase 'preflight'
            $preflightText = Get-HermesI18n -ToolRoot $ToolRoot -Key 'hermes.cli.detectUpdatePreflight'
            Set-ToolkitDepOperationInFlightStatus -Ui $ui -MainText $preflightText -AdvanceSpinner
            & $RedrawView
            & $pump

            Write-HermesProgressLogLine -Log $log -Text $preflightText -Kind 'text' -WithTimestamp `
                -ProgressState $progress -Ui $ui

            Set-HermesProgressPhase -State $progress -Ui $ui -Phase 'update-check'
            $updateStatusText = Get-HermesI18n -ToolRoot $ToolRoot -Key 'hermes.cli.detectUpdateStatus'
            Set-ToolkitDepOperationInFlightStatus -Ui $ui -MainText $updateStatusText -AdvanceSpinner
            & $RedrawView
            & $pump

            Write-HermesProgressLogLine -Log $log -Text $updateStatusText -Kind 'text' -WithTimestamp `
                -ProgressState $progress -Ui $ui

            $updateCheck = Resolve-HermesUpdateCheck -OnPulse $pump
            & $pump

            if ($updateCheck.Skipped) {
                $skipKey = if ([string]$updateCheck.SkipReason -eq 'timeout') {
                    'hermes.cli.detectUpdateSkippedTimeout'
                }
                elseif ([string]$updateCheck.SkipReason -eq 'network') {
                    'hermes.cli.detectUpdateSkippedNetwork'
                }
                else {
                    'hermes.cli.detectUpdateSkippedError'
                }
                Write-HermesProgressLogLine -Log $log -Text (Get-HermesI18n -ToolRoot $ToolRoot -Key $skipKey `
                    -Vars @{ version = $versionLabel }) -Kind 'success' -WithTimestamp `
                    -ProgressState $progress -Ui $ui
                $outcome.Intent = 'install'
                $outcome.SuccessCount = 1
            }
            elseif ($updateCheck.Available) {
                Write-HermesProgressLogLine -Log $log -Text (Get-HermesI18n -ToolRoot $ToolRoot `
                    -Key 'hermes.cli.detectUpdateAvailable') -Kind 'text' -WithTimestamp `
                    -ProgressState $progress -Ui $ui
                $outcome.Intent = 'update'
                $outcome.WorkPerformed = $true

                $streamResult = Invoke-HermesCliStreamWork -Context $ctx -ToolRoot $ToolRoot `
                    -Intent 'update' -SuccessLogKey 'hermes.cli.updateSuccess' `
                    -FailureLogKey 'hermes.cli.updateFailed' -Pump $pump -ProgressState $progress
                if ($streamResult.Ok) { $outcome.SuccessCount = 1 }
                else { $outcome.FailedCount = 1 }
            }
            else {
                Write-HermesProgressLogLine -Log $log -Text (Get-HermesI18n -ToolRoot $ToolRoot `
                    -Key 'hermes.cli.alreadyLatest' -Vars @{ version = $versionLabel }) `
                    -Kind 'success' -WithTimestamp -ProgressState $progress -Ui $ui
                $outcome.Intent = 'install'
                $outcome.SuccessCount = 1
            }
        }

        Complete-HermesProgress -State $progress -Ui $ui
        & $RedrawView

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

function Invoke-HermesUninstallPage {
    param(
        [hashtable]$Shell,
        [string]$SectionTitle,
        [string]$ToolRoot,
        [string]$CoreLib
    )

    Import-HermesDepProgressCore -CoreLib $CoreLib

    $readyText = Get-HermesI18n -ToolRoot $ToolRoot -Key 'hermes.cli.uninstallStatusReady'

    $ctx = Initialize-ToolkitDepBatchOperationView -Shell $Shell -SectionTitle $SectionTitle `
        -ProgressTotal 1 -ReadyStatusText $readyText

    $log = $ctx.Log
    $ui = $ctx.Ui
    $RedrawView = $ctx.RedrawView
    $outcome = @{
        Intent        = 'uninstall'
        SuccessCount  = 0
        FailedCount   = 0
        WorkPerformed = $true
    }

    try {
        & $ctx.FnDrainStaleInput
        if (Get-Command Clear-ConsoleInputBuffer -ErrorAction SilentlyContinue) {
            Clear-ConsoleInputBuffer
        }

        Set-ToolkitShellToolbarLocked -Shell $Shell -Locked $true
        $ui.ItemInFlight = $true
        $ui.ItemSubPercent = 0
        $ui.ExecuteStartTick = [Environment]::TickCount
        Start-ToolkitDepOperationBatch -Ui $ui
        & $RedrawView

        $progress = New-HermesProgressState -Flow 'uninstall'
        Set-HermesProgressPhase -State $progress -Ui $ui -Phase 'install-run' -Jump

        $pump = New-HermesProgressPump -Context $ctx -State $progress -Ui $ui

        $streamResult = Invoke-HermesCliStreamWork -Context $ctx -ToolRoot $ToolRoot `
            -Intent 'uninstall' -SuccessLogKey 'hermes.cli.uninstallSuccess' `
            -FailureLogKey 'hermes.cli.uninstallFailed' -Pump $pump -ProgressState $progress

        if ($streamResult.Ok) { $outcome.SuccessCount = 1 }
        else { $outcome.FailedCount = 1 }

        Complete-HermesProgress -State $progress -Ui $ui
        & $RedrawView

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
