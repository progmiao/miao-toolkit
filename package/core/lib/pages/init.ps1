# 初始化进度页（复用批量依赖操作视图壳）

function Invoke-ToolkitInitView {
    param([hashtable]$Shell)

    $exitConfirmArmed = $false
    $onExitConfirmed = { $exitConfirmArmed = $true }.GetNewClosure()

    $ctx = Initialize-ToolkitDepBatchOperationView -Shell $Shell `
        -SectionTitle (Get-I18n -Key 'page.init.pageTitle') `
        -ProgressTotal 8 `
        -ReadyStatusText (Get-I18n -Key 'page.init.statusReady') `
        -OnExitConfirmed $onExitConfirmed

    $ui = $ctx.Ui
    $log = $ctx.Log
    $RedrawView = $ctx.RedrawView
    $fnDrainStaleInput = $ctx.FnDrainStaleInput
    $fnAddLog = Resolve-DepOperationFn 'Add-ToolkitDepLogLine'

    $buildFailed = $false

    try {
        & $fnDrainStaleInput
        if (Get-Command Clear-ConsoleInputBuffer -ErrorAction SilentlyContinue) {
            Clear-ConsoleInputBuffer
        }

        Set-ToolkitShellToolbarLocked -Shell $Shell -Locked $true
        $ui.ItemInFlight = $true
        $ui.TaskPhase = 'init'
        Start-ToolkitDepOperationBatch -Ui $ui
        & $RedrawView

        try {
            $null = Invoke-ToolkitInitBuild -OnProgress {
                param($Info)

                if ([int]$Info.Total -gt 0) {
                    $ctx.ProgressTotal = [int]$Info.Total
                }
                $ui.ProgressCurrent = [Math]::Max(0, [int]$Info.Step - 1)
                Set-ToolkitDepOperationInFlightStatus -Ui $ui -MainText ([string]$Info.Message) -AdvanceSpinner
                & $fnAddLog -Log $log -Text ([string]$Info.Message) -WithTimestamp
                & $RedrawView
            }

            $total = [int]$ctx.ProgressTotal
            Set-ToolkitDepOperationBatchCompleteUi -Ui $ui -Intent init `
                -TotalCount $total -SuccessCount $total -FailedCount 0 -ProgressCurrent $total
            Initialize-ToolkitHomeBundle -Shell $Shell | Out-Null
        }
        catch {
            $buildFailed = $true
            $ui.ItemInFlight = $false
            $ui.ItemSubPercent = -1
            $ui.StatusSpinnerActive = $false
            $ui.StatusMainText = ''
            $ui.StatusPlain = $true
            $ui.StatusText = (Get-I18n -Key 'page.init.statusFailed')
            $ui.StatusSegments = $null
            $ui.StatusRightText = Format-ToolkitDepOperationElapsedLabel -Seconds (Get-ToolkitDepOperationElapsedSeconds -Ui $ui) `
                -Mode total
            $detail = $_.Exception.Message
            if ([string]::IsNullOrWhiteSpace($detail)) {
                $detail = $_.Exception.GetType().FullName
            }
            & $fnAddLog -Log $log -Text (Get-I18n -Key 'page.init.logFailed' -Vars @{ detail = $detail }) `
                -Kind 'error' -WithTimestamp
        }

        $waitResult = Invoke-ToolkitDepBatchOperationWaitLoop -Context $ctx -QuitNavAction back
        if (Test-ShellNavMarker $waitResult) {
            return $waitResult
        }
        return (Get-ShellNavMarker -Action 'back')
    }
    finally {
        Clear-ToolkitDepBatchOperationView -Context $ctx
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
