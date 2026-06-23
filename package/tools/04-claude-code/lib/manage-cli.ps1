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
        Start-ToolkitDepOperationBatch -Ui $ui
        & $RedrawView

        Invoke-ToolkitDepBatchOperationRunWork -Context $ctx -Work {
            param($Pump)

            $detectText = Get-ClaudeCodeI18n -ToolRoot $ToolRoot -Key 'claude-code.cli.detectStatus'
            Set-ToolkitDepOperationInFlightStatus -Ui $ui -MainText $detectText -AdvanceSpinner
            & $RedrawView
            & $Pump

            Write-ClaudeCodeBatchLogLine -Log $log -Text $detectText -Kind 'heading' -WithTimestamp

            $installed = Test-ClaudeCodeInstalled
            & $Pump

            if (-not $installed) {
                Write-ClaudeCodeBatchLogLine -Log $log -Text (Get-ClaudeCodeI18n -ToolRoot $ToolRoot `
                    -Key 'claude-code.cli.detectNotInstalled') -Kind 'text' -WithTimestamp
                $outcome.Intent = 'install'
                $outcome.WorkPerformed = $true

                $streamResult = Invoke-ClaudeCodeWingetStreamWork -Context $ctx -Verb install `
                    -ToolRoot $ToolRoot -SuccessLogKey 'claude-code.cli.installSuccess' `
                    -FailureLogKey 'claude-code.cli.installFailed' -Pump $Pump
                if ($streamResult.Ok) { $outcome.SuccessCount = 1 }
                else { $outcome.FailedCount = 1 }
                return
            }

            $version = Get-ClaudeCodeInstalledVersion
            $versionLabel = if ($version) { $version } else { '?' }
            Write-ClaudeCodeBatchLogLine -Log $log -Text (Get-ClaudeCodeI18n -ToolRoot $ToolRoot `
                -Key 'claude-code.cli.detectInstalled' -Vars @{ version = $versionLabel }) `
                -Kind 'text' -WithTimestamp
            & $Pump

            Set-ToolkitDepOperationInFlightStatus -Ui $ui -MainText (Get-ClaudeCodeI18n -ToolRoot $ToolRoot `
                -Key 'claude-code.cli.detectUpdateStatus') -AdvanceSpinner
            & $RedrawView
            & $Pump

            $updateAvailable = Test-ClaudeCodeUpdateAvailable -CoreLib $CoreLib
            & $Pump

            if ($updateAvailable) {
                Write-ClaudeCodeBatchLogLine -Log $log -Text (Get-ClaudeCodeI18n -ToolRoot $ToolRoot `
                    -Key 'claude-code.cli.detectUpdateAvailable') -Kind 'text' -WithTimestamp
                $outcome.Intent = 'update'
                $outcome.WorkPerformed = $true

                $streamResult = Invoke-ClaudeCodeWingetStreamWork -Context $ctx -Verb upgrade `
                    -ToolRoot $ToolRoot -SuccessLogKey 'claude-code.cli.updateSuccess' `
                    -FailureLogKey 'claude-code.cli.updateFailed' -Pump $Pump
                if ($streamResult.Ok) { $outcome.SuccessCount = 1 }
                else { $outcome.FailedCount = 1 }
                return
            }

            $idleKey = if ($EntryPoint -eq 'update') {
                'claude-code.cli.alreadyLatest'
            }
            else {
                'claude-code.cli.alreadyInstalled'
            }
            Write-ClaudeCodeBatchLogLine -Log $log -Text (Get-ClaudeCodeI18n -ToolRoot $ToolRoot -Key $idleKey `
                -Vars @{ version = $versionLabel }) -Kind 'success' -WithTimestamp
            $outcome.SuccessCount = 1
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
