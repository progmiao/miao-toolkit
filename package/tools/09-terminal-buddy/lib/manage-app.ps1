# terminal-buddy — 安装/更新/卸载流程

function Invoke-TerminalBuddyAppSyncPage {
    param(
        [hashtable]$Shell,
        [string]$SectionTitle,
        [string]$ToolRoot,
        [string]$CoreLib
    )

    Import-TerminalBuddyDepProgressCore -CoreLib $CoreLib

    $readyText = Get-TerminalBuddyI18n -ToolRoot $ToolRoot -Key 'terminal-buddy.app.installStatusReady'
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

    $pump = {
        $null = Update-ToolkitDepOperationSpinnerIfDue -Ui $ui -PollState $ctx.PollState
        & $RedrawView
        Start-Sleep -Milliseconds 80
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

        $detectText = Get-TerminalBuddyI18n -ToolRoot $ToolRoot -Key 'terminal-buddy.app.detectStatus'
        Set-ToolkitDepOperationInFlightStatus -Ui $ui -MainText $detectText -AdvanceSpinner
        Write-TerminalBuddyBatchLogLine -Log $log -Text $detectText -Kind 'heading' -WithTimestamp
        & $RedrawView
        & $pump

        $installed = Test-TerminalBuddyInstalled
        if (-not $installed) {
            Write-TerminalBuddyBatchLogLine -Log $log -Text (Get-TerminalBuddyI18n -ToolRoot $ToolRoot `
                -Key 'terminal-buddy.app.detectNotInstalled') -Kind 'text' -WithTimestamp
            $outcome.Intent = 'install'
            $outcome.WorkPerformed = $true

            $result = Invoke-TerminalBuddyInstallOrUpdateWork -ToolRoot $ToolRoot -Log $log -Ui $ui `
                -RedrawView $RedrawView -Pump $pump -Intent 'install'
            if ($result.Ok) { $outcome.SuccessCount = 1 } else { $outcome.FailedCount = 1 }
        }
        else {
            $version = Get-TerminalBuddyInstalledVersion
            $versionLabel = if ($version) { $version } else { '?' }
            Write-TerminalBuddyBatchLogLine -Log $log -Text (Get-TerminalBuddyI18n -ToolRoot $ToolRoot `
                -Key 'terminal-buddy.app.detectInstalled' -Vars @{ version = $versionLabel }) `
                -Kind 'text' -WithTimestamp
            & $pump

            $preflightText = Get-TerminalBuddyI18n -ToolRoot $ToolRoot -Key 'terminal-buddy.app.detectUpdatePreflight'
            Set-ToolkitDepOperationInFlightStatus -Ui $ui -MainText $preflightText -AdvanceSpinner
            Write-TerminalBuddyBatchLogLine -Log $log -Text $preflightText -Kind 'text' -WithTimestamp
            & $RedrawView
            & $pump

            $updateStatusText = Get-TerminalBuddyI18n -ToolRoot $ToolRoot -Key 'terminal-buddy.app.detectUpdateStatus'
            Set-ToolkitDepOperationInFlightStatus -Ui $ui -MainText $updateStatusText -AdvanceSpinner
            Write-TerminalBuddyBatchLogLine -Log $log -Text $updateStatusText -Kind 'text' -WithTimestamp
            & $RedrawView

            $updateCheck = Resolve-TerminalBuddyUpdateCheck -ToolRoot $ToolRoot -OnPulse $pump
            & $pump

            if ($updateCheck.Skipped) {
                $skipKey = if ([string]$updateCheck.SkipReason -eq 'network') {
                    'terminal-buddy.app.detectUpdateSkippedNetwork'
                }
                else {
                    'terminal-buddy.app.detectUpdateSkippedError'
                }
                Write-TerminalBuddyBatchLogLine -Log $log -Text (Get-TerminalBuddyI18n -ToolRoot $ToolRoot `
                    -Key $skipKey -Vars @{ version = $versionLabel }) -Kind 'success' -WithTimestamp
                $outcome.Intent = 'install'
                $outcome.SuccessCount = 1
            }
            elseif ($updateCheck.Available) {
                $latestLabel = if ($updateCheck.Latest) { $updateCheck.Latest.Tag } else { '?' }
                Write-TerminalBuddyBatchLogLine -Log $log -Text (Get-TerminalBuddyI18n -ToolRoot $ToolRoot `
                    -Key 'terminal-buddy.app.detectUpdateAvailable' -Vars @{ version = $latestLabel }) `
                    -Kind 'text' -WithTimestamp
                $outcome.Intent = 'update'
                $outcome.WorkPerformed = $true

                $result = Invoke-TerminalBuddyInstallOrUpdateWork -ToolRoot $ToolRoot -Log $log -Ui $ui `
                    -RedrawView $RedrawView -Pump $pump -Intent 'update' -Release $updateCheck.Latest
                if ($result.Ok) { $outcome.SuccessCount = 1 } else { $outcome.FailedCount = 1 }
            }
            else {
                Write-TerminalBuddyBatchLogLine -Log $log -Text (Get-TerminalBuddyI18n -ToolRoot $ToolRoot `
                    -Key 'terminal-buddy.app.alreadyLatest' -Vars @{ version = $versionLabel }) `
                    -Kind 'success' -WithTimestamp
                $outcome.Intent = 'install'
                $outcome.SuccessCount = 1
            }
        }

        $ui.ItemInFlight = $false
        $ui.ItemSubPercent = 100
        $ui.ProgressCurrent = 1
        Set-ToolkitDepOperationBatchCompleteUi -Ui $ui -Intent $outcome.Intent `
            -TotalCount 1 -SuccessCount $outcome.SuccessCount -FailedCount $outcome.FailedCount `
            -ProgressCurrent 1
        & $RedrawView

        return Invoke-ToolkitDepBatchOperationWaitLoop -Context $ctx
    }
    finally {
        Clear-ToolkitDepBatchOperationView -Context $ctx
    }
}

function Invoke-TerminalBuddyInstallOrUpdateWork {
    param(
        [string]$ToolRoot,
        $Log,
        $Ui,
        $RedrawView,
        $Pump,
        [ValidateSet('install', 'update')]
        [string]$Intent,
        $Release = $null
    )

    $successKey = if ($Intent -eq 'update') {
        'terminal-buddy.app.updateSuccess'
    }
    else {
        'terminal-buddy.app.installSuccess'
    }
    $failureKey = if ($Intent -eq 'update') {
        'terminal-buddy.app.updateFailed'
    }
    else {
        'terminal-buddy.app.installFailed'
    }

    try {
        if (-not $Release) {
            $Release = Get-TerminalBuddyLatestRelease -ToolRoot $ToolRoot
        }

        $paths = Get-TerminalBuddyKnownPaths
        Write-TerminalBuddyBatchLogLine -Log $Log -Text (Get-TerminalBuddyI18n -ToolRoot $ToolRoot `
            -Key 'terminal-buddy.app.downloadStart' -Vars @{
                version = $Release.Tag
                url     = $Release.DownloadUrl
            }) -Kind 'text' -WithTimestamp

        Set-ToolkitDepOperationInFlightStatus -Ui $Ui -MainText (Get-TerminalBuddyI18n -ToolRoot $ToolRoot `
            -Key 'terminal-buddy.app.downloadProgress' -Vars @{
                version = $Release.Tag
                percent = '0'
            }) -AdvanceSpinner
        & $RedrawView

        Write-TerminalBuddyBatchLogLine -Log $Log -Text (Get-TerminalBuddyI18n -ToolRoot $ToolRoot `
            -Key 'terminal-buddy.app.installInProgress' -Vars @{ path = $paths.InstallDir }) `
            -Kind 'text' -WithTimestamp

        $installResult = Install-TerminalBuddyRelease -ToolRoot $ToolRoot -Release $Release `
            -Ui $Ui -RedrawView $RedrawView -OnPulse $Pump

        Write-TerminalBuddyBatchLogLine -Log $Log -Text (Get-TerminalBuddyI18n -ToolRoot $ToolRoot `
            -Key 'terminal-buddy.app.downloadSuccess') -Kind 'text' -WithTimestamp
        if ($installResult.Shortcuts.StartMenu -or $installResult.Shortcuts.Desktop) {
            Write-TerminalBuddyBatchLogLine -Log $Log -Text (Get-TerminalBuddyI18n -ToolRoot $ToolRoot `
                -Key 'terminal-buddy.app.shortcutCreated') -Kind 'text' -WithTimestamp
        }
        Write-TerminalBuddyBatchLogLine -Log $Log -Text (Get-TerminalBuddyI18n -ToolRoot $ToolRoot `
            -Key $successKey) -Kind 'success' -WithTimestamp

        return [pscustomobject]@{ Ok = $true; Version = $installResult.Version }
    }
    catch {
        $detail = [string]$_.Exception.Message
        Write-TerminalBuddyBatchLogLine -Log $Log -Text (Get-TerminalBuddyI18n -ToolRoot $ToolRoot `
            -Key $failureKey -Vars @{ detail = $detail }) -Kind 'error' -WithTimestamp
        return [pscustomobject]@{ Ok = $false; Detail = $detail }
    }
}

function Invoke-TerminalBuddyUninstallPage {
    param(
        [hashtable]$Shell,
        [string]$SectionTitle,
        [string]$ToolRoot,
        [string]$CoreLib
    )

    Import-TerminalBuddyDepProgressCore -CoreLib $CoreLib

    $readyText = Get-TerminalBuddyI18n -ToolRoot $ToolRoot -Key 'terminal-buddy.app.uninstallStatusReady'
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

    $pump = {
        $null = Update-ToolkitDepOperationSpinnerIfDue -Ui $ui -PollState $ctx.PollState
        & $RedrawView
        Start-Sleep -Milliseconds 80
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

        $progressText = Get-TerminalBuddyI18n -ToolRoot $ToolRoot -Key 'terminal-buddy.app.uninstallInProgress'
        Set-ToolkitDepOperationInFlightStatus -Ui $ui -MainText $progressText -AdvanceSpinner
        Write-TerminalBuddyBatchLogLine -Log $log -Text $progressText -Kind 'heading' -WithTimestamp
        & $RedrawView
        & $pump

        try {
            $result = Uninstall-TerminalBuddyManaged -OnPulse $pump
            & $pump

            if ($result.Ok) {
                Write-TerminalBuddyBatchLogLine -Log $log -Text (Get-TerminalBuddyI18n -ToolRoot $ToolRoot `
                    -Key 'terminal-buddy.app.uninstallSuccess') -Kind 'success' -WithTimestamp
                $outcome.SuccessCount = 1
            }
            else {
                Write-TerminalBuddyBatchLogLine -Log $log -Text (Get-TerminalBuddyI18n -ToolRoot $ToolRoot `
                    -Key 'terminal-buddy.app.uninstallFailed' -Vars @{ detail = 'remove failed' }) `
                    -Kind 'error' -WithTimestamp
                $outcome.FailedCount = 1
            }
        }
        catch {
            Write-TerminalBuddyBatchLogLine -Log $log -Text (Get-TerminalBuddyI18n -ToolRoot $ToolRoot `
                -Key 'terminal-buddy.app.uninstallFailed' -Vars @{ detail = [string]$_.Exception.Message }) `
                -Kind 'error' -WithTimestamp
            $outcome.FailedCount = 1
        }

        $ui.ItemInFlight = $false
        $ui.ItemSubPercent = 100
        $ui.ProgressCurrent = 1
        Set-ToolkitDepOperationBatchCompleteUi -Ui $ui -Intent $outcome.Intent `
            -TotalCount 1 -SuccessCount $outcome.SuccessCount -FailedCount $outcome.FailedCount `
            -ProgressCurrent 1
        & $RedrawView

        return Invoke-ToolkitDepBatchOperationWaitLoop -Context $ctx
    }
    finally {
        Clear-ToolkitDepBatchOperationView -Context $ctx
    }
}
