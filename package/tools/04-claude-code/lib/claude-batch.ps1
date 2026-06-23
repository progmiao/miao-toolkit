# claude-code — 批量操作视图（WinGet / 插件 / 配置）

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
        [string]$Intent = 'install'
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

            try {
                $result = & $InvokeItem $item
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

        return Invoke-ToolkitDepBatchOperationWaitLoop -Context $ctx
    }
    finally {
        Clear-ToolkitDepBatchOperationView -Context $ctx
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

    $label = Get-ClaudeCodeWingetPackageId
    return Invoke-ClaudeCodeBatchOperation -Shell $Shell -SectionTitle $SectionTitle `
        -ReadyStatusText $ReadyStatusText -Intent $(if ($Verb -eq 'upgrade') { 'update' } else { $Verb }) `
        -Items @($label) `
        -GetItemLabel { param($Item) [string]$Item } `
        -InvokeItem {
            param($Item)
            $result = Invoke-ClaudeCodeWingetProcess -Verb $Verb -OnOutputLine {
                param($Line)
                if (-not [string]::IsNullOrWhiteSpace($Line)) {
                    $null = $Line
                }
            }
            return $result
        } `
        -GetSuccessLog {
            param($Item, $Result)
            Get-ClaudeCodeI18n -ToolRoot $ToolRoot -Key $SuccessLogKey
        } `
        -GetFailureLog {
            param($Item, $Result)
            $detail = if ($Result -is [string]) { $Result } elseif ($Result.Lines) {
                ($Result.Lines | Select-Object -Last 3 | ForEach-Object { [string]$_ }) -join ' '
            }
            else { [string]$Result.Output }
            if ([string]::IsNullOrWhiteSpace($detail)) { $detail = "exit $($Result.ExitCode)" }
            Get-ClaudeCodeI18n -ToolRoot $ToolRoot -Key $FailureLogKey -Vars @{ detail = $detail }
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

    return Invoke-ClaudeCodeBatchOperation -Shell $Shell -SectionTitle $SectionTitle `
        -ReadyStatusText (Get-ClaudeCodeI18n -ToolRoot $ToolRoot -Key 'claude-code.init.statusReady') `
        -Intent init -Items $steps `
        -GetItemLabel {
            param($Item)
            Get-ClaudeCodeI18n -ToolRoot $ToolRoot -Key ([string]$Item.Key)
        } `
        -InvokeItem {
            param($Item)
            $output = & $Item.Action
            $ok = $true
            if ($output -is [bool]) {
                $ok = [bool]$output
            }
            elseif ($null -eq $output) {
                $ok = $false
            }
            return [pscustomobject]@{
                Success = $ok
                Path    = if ($output -is [string]) { $output } else { '' }
            }
        } `
        -GetSuccessLog {
            param($Item, $Result)
            Get-ClaudeCodeI18n -ToolRoot $ToolRoot -Key 'claude-code.init.logSuccess' `
                -Vars @{ step = (Get-ClaudeCodeI18n -ToolRoot $ToolRoot -Key ([string]$Item.Key)) }
        } `
        -GetFailureLog {
            param($Item, $Result)
            $detail = if ($Result -is [string]) { $Result } else { [string]$Result }
            Get-ClaudeCodeI18n -ToolRoot $ToolRoot -Key 'claude-code.init.logFailed' -Vars @{
                step   = (Get-ClaudeCodeI18n -ToolRoot $ToolRoot -Key ([string]$Item.Key))
                detail = $detail
            }
        }
}
