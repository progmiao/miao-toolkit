# 批量依赖操作视图：进度区 + 日志区的公共壳（安装/卸载/后续同类操作复用）

function New-ToolkitDepOperationUiState {
    param([string]$ReadyStatusText = '')

    $fnGetI18n = if (Get-Command Get-I18n -ErrorAction SilentlyContinue) {
        ${function:Get-I18n}
    }
    else { $null }

    $ready = if ($ReadyStatusText) {
        $ReadyStatusText
    }
    elseif ($fnGetI18n) {
        & $fnGetI18n -Key 'page.depOperation.statusReady'
    }
    else {
        ''
    }

    return @{
        ProgressCurrent      = 0
        ItemInFlight         = $false
        ItemSubPercent       = -1
        ProgressName         = ''
        StatusText           = $ready
        StatusMainText       = ''
        StatusRightText      = ''
        StatusPlain          = $false
        StatusSegments       = $null
        StatusSpinnerActive  = $false
        SpinnerFrames        = @('|', '/', '-', '\')
        SpinnerIndex         = 0
        ExecuteStartTick     = 0
        OperationStartTick   = 0
        OperationStartUtc    = $null
        ElapsedDisplaySecond = 0
        TaskPhase            = ''
    }
}

function New-ToolkitDepOperationLoadingState {
    return @{
        SpinnerFrames  = @('|', '/', '-', '\')
        SpinnerIndex   = 0
        OutputSeen     = $false
        LastOutputTick = 0
        TaskPhase      = ''
    }
}

function Get-ToolkitDepOperationElapsedSecondsFromStart {
    param(
        [int]$StartTick = 0,
        $StartUtc = $null
    )

    if ($null -ne $StartUtc -and $StartUtc -is [DateTime]) {
        $elapsed = ([DateTime]::UtcNow - $StartUtc).TotalSeconds
        if ($elapsed -lt 0) { return 0 }
        return [int][Math]::Floor($elapsed)
    }

    if ($StartTick -le 0) { return 0 }
    $elapsedMs = [Environment]::TickCount - $StartTick
    if ($elapsedMs -lt 0) { $elapsedMs = 0 }
    return [int][Math]::Floor($elapsedMs / 1000.0)
}

function Get-ToolkitDepOperationElapsedSeconds {
    param($Ui)

    if ($null -eq $Ui -or [int]$Ui.OperationStartTick -le 0) { return 0 }

    return (Get-ToolkitDepOperationElapsedSecondsFromStart -StartTick ([int]$Ui.OperationStartTick) `
        -StartUtc $Ui.OperationStartUtc)
}

function Get-ToolkitDepOperationWallElapsedSecond {
    param($Ui)

    if ($null -eq $Ui -or [int]$Ui.OperationStartTick -le 0) { return 0 }

    $startUtc = $Ui.OperationStartUtc
    if ($null -ne $startUtc -and $startUtc -is [DateTime]) {
        $elapsed = ([DateTime]::UtcNow - $startUtc).TotalSeconds
        if ($elapsed -lt 0) { return 0 }
        return [int][Math]::Floor($elapsed)
    }

    return (Get-ToolkitDepOperationElapsedSecondsFromStart -StartTick ([int]$Ui.OperationStartTick))
}

function Update-ToolkitDepOperationDisplayElapsedIfDue {
    param($Ui)

    if ($null -eq $Ui -or [int]$Ui.OperationStartTick -le 0) { return $false }
    if ($Ui.StatusSegments -and @($Ui.StatusSegments).Count -gt 0) { return $false }
    if (-not [bool]$Ui.ItemInFlight -and -not [bool]$Ui.StatusSpinnerActive) { return $false }

    $startUtc = $Ui.OperationStartUtc
    if ($null -eq $startUtc -or -not ($startUtc -is [DateTime])) {
        return $false
    }

    $displayed = if ($null -ne $Ui.ElapsedDisplaySecond) { [int]$Ui.ElapsedDisplaySecond } else { 0 }
    $trueSecond = Get-ToolkitDepOperationWallElapsedSecond -Ui $Ui
    if ($trueSecond -le $displayed) { return $false }

    $nextSecond = $displayed + 1
    if ($nextSecond -gt $trueSecond) { return $false }
    if ([DateTime]::UtcNow -lt $startUtc.AddSeconds($nextSecond)) { return $false }

    $Ui.ElapsedDisplaySecond = $nextSecond
    $Ui.StatusRightText = Format-ToolkitDepOperationElapsedLabel -Seconds $nextSecond -Mode running
    return $true
}

function Resolve-ToolkitDepOperationMainStatusText {
    param([string]$TemplateText)

    $text = [string]$TemplateText
    if ($text -match '^\{spinner\}\s*(.+)$') {
        return $Matches[1]
    }
    return $text
}

function Update-ToolkitDepOperationSpinnerText {
    param(
        $Ui,
        [switch]$AdvanceSpinner
    )

    if ($null -eq $Ui -or -not $Ui.StatusSpinnerActive) { return }

    if ($AdvanceSpinner) {
        $Ui.SpinnerIndex = [int]$Ui.SpinnerIndex + 1
    }

    $frames = @('|', '/', '-', '\')
    if ($Ui.SpinnerFrames) { $frames = @($Ui.SpinnerFrames) }
    $spinner = $frames[[int]$Ui.SpinnerIndex % $frames.Count]
    $main = [string]$Ui.StatusMainText
    if ([string]::IsNullOrWhiteSpace($main)) {
        $main = Get-I18n -Key 'page.depOperation.statusLoadingPlain'
    }

    $Ui.StatusText = Get-I18n -Key 'page.depOperation.statusSpinnerLine' -Vars @{
        spinner = $spinner
        text    = $main
    }
}

function Set-ToolkitDepOperationInFlightStatus {
    param(
        $Ui,
        [string]$MainText,
        [switch]$AdvanceSpinner
    )

    if ($null -eq $Ui) { return }

    $Ui.StatusSpinnerActive = $true
    $Ui.StatusPlain = $false
    $Ui.StatusMainText = Resolve-ToolkitDepOperationMainStatusText -TemplateText $MainText
    Update-ToolkitDepOperationSpinnerText -Ui $Ui -AdvanceSpinner:$AdvanceSpinner
}

function Update-ToolkitDepOperationSpinnerIfDue {
    param(
        $Ui,
        [hashtable]$PollState = $null,
        [int]$IntervalMs = 200
    )

    return (Update-ToolkitDepOperationStatusChrome -Ui $Ui -PollState $PollState -SpinnerIntervalMs $IntervalMs)
}

function Update-ToolkitDepOperationStatusChrome {
    param(
        $Ui,
        [hashtable]$PollState = $null,
        [int]$SpinnerIntervalMs = 200
    )

    if ($null -eq $Ui) { return $false }

    $chromeActive = ([bool]$Ui.ItemInFlight -or [bool]$Ui.StatusSpinnerActive)
    if (-not $chromeActive) { return $false }

    $now = [Environment]::TickCount
    $changed = $false

    if (Update-ToolkitDepOperationDisplayElapsedIfDue -Ui $Ui) {
        $changed = $true
    }

    if (-not $Ui.StatusSpinnerActive) { return $changed }

    $lastSpinner = 0
    if ($PollState -and $PollState.ContainsKey('LastSpinnerTick')) {
        $lastSpinner = [int]$PollState.LastSpinnerTick
    }
    if ($lastSpinner -le 0 -or (($now - $lastSpinner) -ge $SpinnerIntervalMs)) {
        Update-ToolkitDepOperationSpinnerText -Ui $Ui -AdvanceSpinner
        if ($PollState) { $PollState.LastSpinnerTick = $now }
        $changed = $true
    }

    return $changed
}

function Sync-ToolkitDepOperationStatusChrome {
    param(
        $Ui,
        [hashtable]$PollState = $null,
        [int]$SpinnerIntervalMs = 200
    )

    return (Update-ToolkitDepOperationStatusChrome -Ui $Ui -PollState $PollState -SpinnerIntervalMs $SpinnerIntervalMs)
}

function Test-ToolkitDepOperationChromePumpActive {
    param($Ui)

    if ($null -eq $Ui) { return $false }
    return ([bool]$Ui.ItemInFlight -or [bool]$Ui.StatusSpinnerActive)
}

function Invoke-ToolkitDepBatchOperationUiPump {
    param(
        $Context,
        [switch]$Force
    )

    if ($null -eq $Context) { return $false }

    $ui = $Context.Ui
    if (-not $Force -and -not (Test-ToolkitDepOperationChromePumpActive -Ui $ui)) {
        return $false
    }

    $null = Sync-ToolkitDepOperationStatusChrome -Ui $ui -PollState $Context.PollState
    if ($Context.UseBufferDraw) {
        & $Context.FnEnterBatch
    }
    & $Context.RedrawDepChrome
    if ($Context.UseBufferDraw) {
        $null = & $Context.FnCompleteBatch -ToolkitShell $Context.Shell
    }
    return $true
}

function Invoke-ToolkitDepBatchOperationRunWork {
    param(
        [Parameter(Mandatory)]
        $Context,
        [Parameter(Mandatory)]
        [scriptblock]$Work
    )

    $pump = {
        Invoke-ToolkitDepBatchOperationUiPump -Context $Context
    }.GetNewClosure()

    & $Work $pump
}

function Set-ToolkitDepOperationProgressMessage {
    param(
        $Ui,
        [string]$Message
    )

    if ($null -eq $Ui) { return }
    Set-ToolkitDepOperationInFlightStatus -Ui $Ui -MainText $Message
}

function Update-ToolkitDepOperationProgressStep {
    param(
        $Ui,
        [int]$ProgressCurrent,
        [string]$Message
    )

    if ($null -eq $Ui) { return }
    if ([int]$ProgressCurrent -ge 0) {
        $Ui.ProgressCurrent = $ProgressCurrent
    }
    if (-not [string]::IsNullOrWhiteSpace($Message)) {
        Set-ToolkitDepOperationProgressMessage -Ui $Ui -Message $Message
    }
}

function Format-ToolkitDepOperationElapsedSecondsSlot {
    param([int]$Seconds)

    $text = [Math]::Max(0, $Seconds).ToString()
    $reserved = 4
    if ($text.Length -ge $reserved) { return $text }

    return (' ' * ($reserved - $text.Length)) + $text
}

function Format-ToolkitDepOperationElapsedLabel {
    param(
        [int]$Seconds,
        [ValidateSet('running', 'total')]
        [string]$Mode = 'running'
    )

    $slot = Format-ToolkitDepOperationElapsedSecondsSlot -Seconds $Seconds
    $key = if ($Mode -eq 'total') { 'page.depOperation.statusTotalElapsed' } else { 'page.depOperation.statusElapsed' }
    return (Get-I18n -Key $key -Vars @{ elapsed = $slot })
}

function Update-ToolkitDepOperationStatusElapsed {
    param($Ui)

    if ($null -eq $Ui) { return }
    $seconds = if ($null -ne $Ui.ElapsedDisplaySecond -and [int]$Ui.OperationStartTick -gt 0) {
        [int]$Ui.ElapsedDisplaySecond
    }
    else {
        (Get-ToolkitDepOperationElapsedSeconds -Ui $Ui)
    }
    $Ui.StatusRightText = Format-ToolkitDepOperationElapsedLabel -Seconds $seconds -Mode running
}

function Update-ToolkitDepOperationTotalElapsed {
    param($Ui)

    if ($null -eq $Ui) { return }
    $Ui.StatusRightText = Format-ToolkitDepOperationElapsedLabel -Seconds (Get-ToolkitDepOperationElapsedSeconds -Ui $Ui) `
        -Mode total
}

function Start-ToolkitDepOperationBatch {
    param($Ui)

    if ($null -eq $Ui) { return }
    $Ui.OperationStartTick = [Environment]::TickCount
    $Ui.OperationStartUtc = [DateTime]::UtcNow
    $Ui.ElapsedDisplaySecond = 0
    $ready = Resolve-ToolkitDepOperationMainStatusText -TemplateText ([string]$Ui.StatusText)
    if ([string]::IsNullOrWhiteSpace($ready)) {
        $ready = Get-I18n -Key 'page.depOperation.statusLoadingPlain'
    }
    Set-ToolkitDepOperationInFlightStatus -Ui $Ui -MainText $ready
    Update-ToolkitDepOperationStatusElapsed -Ui $Ui
}

function Update-ToolkitDepOperationSpinnerStatus {
    param(
        $Ui,
        $LoadingState,
        [string]$MainText
    )

    if ($null -eq $Ui -or -not $Ui.ItemInFlight) { return }

    Set-ToolkitDepOperationInFlightStatus -Ui $Ui -MainText $MainText -AdvanceSpinner
}

function Set-ToolkitDepOperationBatchCompleteUi {
    param(
        $Ui,
        [ValidateSet('install', 'update', 'uninstall', 'init')]
        [string]$Intent,
        [int]$TotalCount,
        [int]$SuccessCount,
        [int]$FailedCount,
        [int]$ProgressCurrent = -1
    )

    if ($null -eq $Ui) { return }

    if ($ProgressCurrent -ge 0) {
        $Ui.ProgressCurrent = $ProgressCurrent
    }

    $Ui.ItemInFlight = $false
    $Ui.ItemSubPercent = -1
    $Ui.StatusSpinnerActive = $false
    $Ui.StatusMainText = ''
    $Ui.StatusPlain = $false
    $Ui.StatusText = ''
    $Ui.StatusSegments = Get-ToolkitDepBatchSummarySegments -Intent $Intent `
        -TotalCount $TotalCount -SuccessCount $SuccessCount -FailedCount $FailedCount
    Update-ToolkitDepOperationTotalElapsed -Ui $Ui
}

function Initialize-ToolkitDepBatchOperationView {
    param(
        [hashtable]$Shell,
        [string]$SectionTitle,
        [int]$ProgressTotal,
        [string]$ReadyStatusText = '',
        $Log = $null,
        [scriptblock]$OnExitConfirmed = $null
    )

    $toolbar = New-ShellSystemToolbarConfig -HideSystem -HideHelp
    $renderFooter = New-ShellSystemToolbarFooterRenderer -Shell $Shell -ToolbarConfig $toolbar
    Register-ToolkitShellFooter -Shell $Shell -Renderer $renderFooter

    Initialize-ToolkitShellBodyView -Shell $Shell -SectionTitle $SectionTitle -FooterTemplate SystemToolbarOnly
    $Shell['SuppressBelowFooterClear'] = $true

    $fnEnsureDepBuffer = Get-Command Ensure-ToolkitDepOperationConsoleBuffer -ErrorAction SilentlyContinue
    if ($fnEnsureDepBuffer) { & $fnEnsureDepBuffer }

    $fnGetBrandSnapshot = Get-Command Get-ToolkitShellBrandSnapshot -ErrorAction SilentlyContinue
    if ($fnGetBrandSnapshot -and -not $Shell.BrandSnapshot) {
        $Shell['BrandSnapshot'] = & $fnGetBrandSnapshot -Shell $Shell
    }

    $layout = $Shell.Layout
    $logLayout = Get-ToolkitDepOperationLogLayout -Layout $layout
    $logSeparatorRow = [int]$logLayout.SeparatorRow
    $logContentViewportRows = [int]$logLayout.ContentViewportRows

    $contentMetrics = if ($Shell.Layout.LayoutLineMetrics) { $Shell.Layout.LayoutLineMetrics } else {
        Sync-ToolkitShellLayoutLineMetrics -Shell $Shell
    }
    $barWidth = [int]$contentMetrics.InnerWidth
    if ($null -eq $Log) {
        $log = New-ToolkitDepOperationLog
    }
    else {
        $log = $Log
    }
    $log.BrandInnerWidth = $barWidth
    $log.ViewportRows = $logContentViewportRows

    for ($clearRow = $logSeparatorRow; $clearRow -le $layout.ListEndRow; $clearRow++) {
        Write-ToolkitDepContentFixedLine -Row $clearRow -Text '' -Color DarkGray `
            -Shell $Shell -BrandInnerWidth $barWidth
    }

    $ui = New-ToolkitDepOperationUiState -ReadyStatusText $ReadyStatusText

    $fnEnterBatch = Resolve-DepOperationFn 'Enter-ConsoleDrawBatch'
    $fnCompleteBatch = Resolve-DepOperationFn 'Complete-ConsoleDrawBatch'
    $fnDrainStaleInput = Resolve-DepOperationFn 'Drain-ConsoleStaleToolbarInput'
    $fnReadExitIfActive = Resolve-DepOperationFn 'Read-ShellExitIfActive'
    $fnLogInput = Resolve-DepOperationFn 'Invoke-ToolkitDepLogInputIfAvailable'
    $fnRegisterExitExtension = Resolve-DepOperationFn 'Register-ShellExitExtension'
    $fnClearExitExtension = Resolve-DepOperationFn 'Clear-ShellExitExtension'
    $fnProcessEscInput = Resolve-DepOperationFn 'Process-ShellEscInputIfAvailable'
    $fnDrawLogViewport = Resolve-DepOperationFn 'Draw-ToolkitDepOperationLogViewport'
    $fnPeekKey = Resolve-DepOperationFn 'Get-ConsoleVirtualKeyPeek'
    $fnWriteExitFooter = Get-Command Write-ShellExitFooter -CommandType Function -ErrorAction Stop

    $useBufferDraw = $false
    if ($env:MIAO_BUFFER_DRAW -eq '1') {
        try { $useBufferDraw = ($null -ne $Host.UI.RawUI) } catch {}
    }

    $pollState = @{
        LastScrollTick           = 0
        LastSpinnerTick     = 0
        MinScrollIntervalMs = 55
    }

    $brandRepairState = @{ Requested = $false }

    $ctx = @{
        Shell                  = $Shell
        SectionTitle           = $SectionTitle
        ProgressTotal          = [int]$ProgressTotal
        Log                    = $log
        Ui                     = $ui
        LogSeparatorRow        = $logSeparatorRow
        LogContentViewportRows = $logContentViewportRows
        RenderFooter           = $renderFooter
        UseBufferDraw          = $useBufferDraw
        FnEnterBatch           = $fnEnterBatch
        FnCompleteBatch        = $fnCompleteBatch
        FnDrainStaleInput      = $fnDrainStaleInput
        FnReadExitIfActive     = $fnReadExitIfActive
        FnLogInput             = $fnLogInput
        FnClearExitExtension   = $fnClearExitExtension
        FnDrawLogViewport      = $fnDrawLogViewport
        FnPeekKey              = $fnPeekKey
        FnWriteExitFooter      = $fnWriteExitFooter
        PollState              = $pollState
        BrandRepairState       = $brandRepairState
    }

    $onExitConfirmed = if ($OnExitConfirmed) {
        $OnExitConfirmed
    }
    else {
        { }.GetNewClosure()
    }
    & $fnRegisterExitExtension -Shell $Shell -OnExitConfirmed $onExitConfirmed

    $ctx.OnExitKey = {
        $null = & $fnProcessEscInput -Shell $Shell
    }.GetNewClosure()

    $footerState = @{ Drawn = $false }

    $drawDepOperationChrome = {
        param([switch]$ChromeOnly)
        $itemSubPercent = if ($ui.ItemInFlight) { [int]$ui.ItemSubPercent } else { -1 }
        $statusSegments = if ($ui.StatusSegments) { @($ui.StatusSegments) } else { $null }
        Draw-ToolkitDepOperationView -Shell $Shell -Log $log -ProgressCurrent $ui.ProgressCurrent `
            -ProgressTotal $ctx.ProgressTotal -ProgressName $ui.ProgressName -StatusText $ui.StatusText `
            -StatusRightText ([string]$ui.StatusRightText) -LogViewportRows 0 -LogStartRow $logSeparatorRow `
            -ProgressItemSubPercent $itemSubPercent -ProgressItemInFlight:([bool]$ui.ItemInFlight) `
            -StatusPlain:([bool]$ui.StatusPlain) -StatusSegments $statusSegments -ChromeOnly:$ChromeOnly
    }.GetNewClosure()

    $ctx.RedrawDepChrome = {
        & $drawDepOperationChrome -ChromeOnly
    }.GetNewClosure()

    $ctx.RedrawView = {
        $null = Sync-ToolkitDepOperationStatusChrome -Ui $ui -PollState $pollState
        $repairBrandAfterLogs = [bool]$brandRepairState.Requested
        if ($repairBrandAfterLogs) {
            $brandRepairState.Requested = $false
        }
        if ($useBufferDraw) {
            & $fnEnterBatch
        }
        & $drawDepOperationChrome
        & $fnDrawLogViewport -Shell $Shell -Log $log `
            -LogSeparatorRow $logSeparatorRow -LogContentViewportRows $logContentViewportRows `
            -RepairBrandTextRowsAfterDraw:$repairBrandAfterLogs
        if ($Shell.ExitMode) {
            & $fnWriteExitFooter -Shell $Shell
            $footerState.Drawn = $false
        }
        elseif (-not $footerState.Drawn) {
            & $renderFooter
            $footerState.Drawn = $true
        }
        if ($useBufferDraw) {
            $null = & $fnCompleteBatch -ToolkitShell $Shell
        }
    }.GetNewClosure()

    $ctx.OnExitConfirmed = $onExitConfirmed
    return $ctx
}

function Invoke-ToolkitDepBatchOperationWaitLoop {
    param(
        $Context,
        [ValidateSet('back', 'none')]
        [string]$QuitNavAction = 'none'
    )

    if ($null -eq $Context) { return $null }

    $Shell = $Context.Shell
    $log = $Context.Log
    $RedrawView = $Context.RedrawView
    $fnReadExitIfActive = $Context.FnReadExitIfActive
    $fnLogInput = $Context.FnLogInput
    $fnDrainStaleInput = $Context.FnDrainStaleInput
    $onExitKey = $Context.OnExitKey
    $fnPeekKey = $Context.FnPeekKey
    $uiPollState = $Context.PollState
    $logContentViewportRows = $Context.LogContentViewportRows

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
                    if ($QuitNavAction -eq 'back') {
                        return (Get-ShellNavMarker -Action 'back')
                    }
                    return $null
                }
                if ($key.Key -eq 'Escape') {
                    $null = & $onExitKey
                    & $RedrawView
                }
                continue
            }
        }

        $null = Invoke-ToolkitDepBatchOperationUiPump -Context $Context
        Start-Sleep -Milliseconds 20
    }
}

function Clear-ToolkitDepBatchOperationView {
    param($Context)

    if ($null -eq $Context) { return }
    Set-ToolkitShellToolbarLocked -Shell $Context.Shell -Locked $false
    if ($Context.Shell) {
        $Context.Shell['SuppressBelowFooterClear'] = $false
    }
    & $Context.FnClearExitExtension -Shell $Context.Shell
}
