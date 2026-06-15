# 初始化进度页（复用依赖操作视图绘制）

function Invoke-ToolkitInitView {
    param([hashtable]$Shell)

    $toolbar = New-ShellSystemToolbarConfig -HideSystem -HideHelp
    $renderFooter = New-ShellSystemToolbarFooterRenderer -Shell $Shell -ToolbarConfig $toolbar
    Register-ToolkitShellFooter -Shell $Shell -Renderer $renderFooter

    Initialize-ToolkitShellBodyView -Shell $Shell `
        -SectionTitle (Get-I18n -Key 'page.init.pageTitle') `
        -FooterTemplate SystemToolbarOnly

    $layout = $Shell.Layout
    $logLayout = Get-ToolkitDepOperationLogLayout -Layout $layout
    $logSeparatorRow = [int]$logLayout.SeparatorRow
    $logContentViewportRows = [int]$logLayout.ContentViewportRows

    $log = New-ToolkitDepOperationLog
    $contentMetrics = if ($Shell.Layout.ContentMetrics) { $Shell.Layout.ContentMetrics } else {
        Sync-ToolkitShellContentMetrics -Shell $Shell
    }
    $barWidth = [int]$contentMetrics.InnerWidth
    $log.BrandInnerWidth = $barWidth
    $log.ViewportRows = $logContentViewportRows

    $buildProgress = @{ Total = 8 }
    $ui = @{
        ProgressCurrent  = 0
        ItemInFlight     = $false
        ItemSubPercent   = -1
        ProgressName     = ''
        StatusText       = (Get-I18n -Key 'page.init.statusReady')
        StatusPlain      = $false
        StatusSegments   = $null
        ExecuteStartTick = 0
    }

    $fnEnterBatch = Resolve-DepOperationFn 'Enter-ConsoleDrawBatch'
    $fnCompleteBatch = Resolve-DepOperationFn 'Complete-ConsoleDrawBatch'
    $fnDrawView = Resolve-DepOperationFn 'Draw-ToolkitDepOperationView'
    $fnDrawLogViewport = Resolve-DepOperationFn 'Draw-ToolkitDepOperationLogViewport'
    $fnAddLog = Resolve-DepOperationFn 'Add-ToolkitDepLogLine'
    $fnDrainStaleInput = Resolve-DepOperationFn 'Drain-ConsoleStaleToolbarInput'
    $fnReadExitIfActive = Resolve-DepOperationFn 'Read-ShellExitIfActive'
    $fnLogInput = Resolve-DepOperationFn 'Invoke-ToolkitDepLogInputIfAvailable'
    $fnRegisterExitExtension = Resolve-DepOperationFn 'Register-ShellExitExtension'
    $fnClearExitExtension = Resolve-DepOperationFn 'Clear-ShellExitExtension'
    $fnProcessEscInput = Resolve-DepOperationFn 'Process-ShellEscInputIfAvailable'
    $fnPeekKey = Resolve-DepOperationFn 'Get-ConsoleVirtualKeyPeek'

    $useBufferDraw = $false
    if ($env:MIAO_BUFFER_DRAW -eq '1') {
        try { $useBufferDraw = ($null -ne $Host.UI.RawUI) } catch {}
    }

    $RedrawView = {
        $itemSubPercent = if ($ui.ItemInFlight) { [int]$ui.ItemSubPercent } else { -1 }
        $statusSegments = if ($ui.StatusSegments) { @($ui.StatusSegments) } else { $null }
        if ($useBufferDraw) { & $fnEnterBatch }
        & $fnDrawView -Shell $Shell -Log $log -ProgressCurrent $ui.ProgressCurrent `
            -ProgressTotal $buildProgress.Total -ProgressName $ui.ProgressName -StatusText $ui.StatusText `
            -LogViewportRows 0 -LogStartRow $logSeparatorRow `
            -ProgressItemSubPercent $itemSubPercent -StatusPlain:([bool]$ui.StatusPlain) `
            -StatusSegments $statusSegments
        & $fnDrawLogViewport -Shell $Shell -Log $log `
            -LogSeparatorRow $logSeparatorRow -LogContentViewportRows $logContentViewportRows
        Invoke-ToolkitShellRegisteredFooter -Shell $Shell
        if ($useBufferDraw) {
            $null = & $fnCompleteBatch -ToolkitShell $Shell
        }
    }.GetNewClosure()

    $buildFailed = $false
    $complete = $false
    $exitConfirmArmed = $false
    $onExitConfirmed = { $exitConfirmArmed = $true }.GetNewClosure()
    & $fnRegisterExitExtension -Shell $Shell -OnExitConfirmed $onExitConfirmed

    $onExitKey = {
        $null = & $fnProcessEscInput -Shell $Shell
    }.GetNewClosure()

    $uiPollState = @{
        LastScrollTick      = 0
        MinScrollIntervalMs = 55
    }

    try {
        & $fnDrainStaleInput
        if (Get-Command Clear-ConsoleInputBuffer -ErrorAction SilentlyContinue) {
            Clear-ConsoleInputBuffer
        }

        Set-ToolkitShellToolbarLocked -Shell $Shell -Locked $true
        & $RedrawView

        try {
            $null = Invoke-ToolkitInitBuild -OnProgress {
                param($Info)

                if ($Info.Total -gt 0) {
                    $buildProgress.Total = [int]$Info.Total
                }
                $ui.ProgressCurrent = [Math]::Min([int]$Info.Step, $buildProgress.Total)
                $ui.StatusText = [string]$Info.Message
                & $fnAddLog -Log $log -Text ([string]$Info.Message) -WithTimestamp
                & $RedrawView
            }
            $ui.ProgressCurrent = $buildProgress.Total
            $ui.StatusPlain = $true
            $ui.StatusText = ''
            $ui.StatusSegments = Get-ToolkitDepBatchSummarySegments -Intent init `
                -TotalCount $buildProgress.Total -SuccessCount $buildProgress.Total -FailedCount 0
            Update-ToolkitShellBrandHeader -Shell $Shell
        }
        catch {
            $buildFailed = $true
            $ui.StatusPlain = $true
            $ui.StatusText = (Get-I18n -Key 'page.init.statusFailed')
            $ui.StatusSegments = $null
            $detail = $_.Exception.Message
            if ([string]::IsNullOrWhiteSpace($detail)) {
                $detail = $_.Exception.GetType().FullName
            }
            & $fnAddLog -Log $log -Text (Get-I18n -Key 'page.init.logFailed' -Vars @{ detail = $detail }) `
                -Kind 'error' -WithTimestamp
        }

        $complete = $true
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
                    $scrollInput = & $fnLogInput -Shell $Shell -Log $log `
                        -ViewportRows $logContentViewportRows -OnExitKey $onExitKey -ScrollState $uiPollState
                    if ($scrollInput -in @('scroll', 'exit')) {
                        & $RedrawView
                    }
                    continue
                }

                if ($complete -and -not (Test-ToolkitShellToolbarLocked -Shell $Shell)) {
                    Prepare-ToolkitShellBodyDraw -Shell $Shell
                    $key = [Console]::ReadKey($true)
                    Set-CursorVisible $false
                    if ($key.KeyChar -match '^[qQ]$') {
                        $Shell.Layout['BodyDirty'] = $true
                        return (Get-ShellNavMarker -Action 'back')
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

function Invoke-ShellInitView {
    param([hashtable]$Shell)

    return Invoke-ToolkitInitView -Shell $Shell
}

function Invoke-ToolkitInitQuiet {
    try {
        Invoke-ToolkitInitBuild | Out-Null
        return 0
    }
    catch {
        return 1
    }
}

function Start-ToolkitInitSession {
    param(
        [array]$Tools,
        [switch]$FromSys
    )

    $initial = if ($FromSys) { 'InitFromSys' } else { 'Init' }
    return (Start-ToolkitShellSession -Tools $Tools -InitialView $initial)
}

# 兼容旧名称
function Invoke-ToolkitCacheInitView { param([hashtable]$Shell) Invoke-ToolkitInitView -Shell $Shell }
function Invoke-ShellCacheInitView { param([hashtable]$Shell) Invoke-ShellInitView -Shell $Shell }
function Invoke-ToolkitCacheInitQuiet { Invoke-ToolkitInitQuiet }
function Start-ToolkitCacheInitSession { param([array]$Tools, [switch]$FromSys) Start-ToolkitInitSession -Tools $Tools -FromSys:$FromSys }
