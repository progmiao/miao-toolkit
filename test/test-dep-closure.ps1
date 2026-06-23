$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$lib = Join-Path $root 'package\core\lib'
$bin = Join-Path $root 'package\bin'
$toolRoot = Join-Path $root 'package\tools\01-node'

. (Join-Path $lib 'bootstrap\Load-Core.ps1') -LibDirectory $lib
. (Join-Path $lib 'config\Paths.ps1')
Initialize-Paths -BinDirectory $bin
Import-MiaoModule -Name Tool

$tool = Get-ToolFromDirectory -ToolRoot $toolRoot

# Child scope dot-source (same as index.ps1 -> & main.ps1)
& {
    $coreLib = Join-Path $toolRoot '..\..\core\lib'
    foreach ($rel in @(
            'domain\Check-Update.ps1'
            'domain\Ensure-ToolDeps.ps1'
            'config\Deps-State.ps1'
            'domain\Invoke-ToolDepPackage.ps1'
            'domain\Invoke-ToolkitRuntime.ps1'
            'domain\Invoke-ToolkitDepOperation.ps1'
            'ui\shell\DepOperationView.ps1'
            'ui\shell\ToolkitDepBatchOperation.ps1'
            'domain\Invoke-ToolkitDeps.ps1'
        )) {
        . (Join-Path $coreLib $rel)
    }

    $fn = Resolve-DepOperationFn 'Get-ToolkitDepStatusText'
    $plan = Build-ToolDepSyncPlan -Tool $tool -Intent install
    $item = $plan.Items[0]
    $onProgress = {
        param($Info)
        & $fn -PlanItem $Info.Item -Phase 'detect'
    }.GetNewClosure()

    $text = & $onProgress @{ Item = $item }
    if ([string]::IsNullOrWhiteSpace($text)) {
        throw 'closure returned empty status text'
    }

    $outputState = @{
        LastLoggedPercent      = -1
        LoggedPhases           = @{}
        ElapsedSeconds         = 0
        PercentStage           = 'download'
        LoggedDownloadComplete = $false
        LoggedInstallComplete  = $false
    }
    $decision = Get-ToolkitDepWingetOutputDecision -Line 'Found Volta [Volta.Volta]' -OutputState $outputState
    if ([string]::IsNullOrWhiteSpace([string]$decision.LogText)) {
        throw 'winget output decision should resolve i18n in module scope'
    }

    $outputState.LastLoggedPercent = -1
    $dDl = Get-ToolkitDepWingetOutputDecision -Line ' 45%' -OutputState $outputState
    if ($dDl.LogText -notmatch '45') {
        throw 'download percent milestone should log partial download progress'
    }
    $outputState.LastLoggedPercent = -1
    $dVisual = Get-ToolkitDepWingetOutputDecision -Line '  ██████████████████████████████  45%' -OutputState $outputState
    if ($dVisual.LogText) {
        throw 'progress bar visuals should not be written to install log'
    }
    if ($dVisual.Percent -ne 45) {
        throw 'progress bar visuals should still expose parsed percent'
    }
    $outputState.LastLoggedPercent = 90
    $dDone = Get-ToolkitDepWingetOutputDecision -Line ' 100%' -OutputState $outputState
    if (-not $outputState.LoggedDownloadComplete) {
        throw '100% in download stage should mark download complete'
    }

    $outputState.LastLoggedPercent = -1
    $outputState.LoggedDownloadComplete = $false
    $outputState.LoggedInstallComplete = $false
    $block = [string][char]0x2588
    $shade = [string][char]0x2592
    $barLine = "  $($block * 24)$($shade * 6)  4.32 MB"
    $dBar = Get-ToolkitDepWingetOutputDecision -Line $barLine -OutputState $outputState
    if ($dBar.LogText) {
        throw 'progress bar visuals should not be written to install log'
    }
    if ($dBar.Percent -lt 70) {
        throw 'progress bar visuals should expose estimated percent from block fill'
    }

    $log = New-ToolkitDepOperationLog
    $log.BrandInnerWidth = 48
    $log.ViewportRows = 3
    $longCmd = 'winget install --id Volta.Volta -e --accept-package-agreements --accept-source-agreements --silent'
    Add-ToolkitDepLogLine -Log $log -Text $longCmd -WithTimestamp
    if ($log.Lines.Count -lt 2) {
        throw 'long log lines should wrap to multiple rows'
    }
    Add-ToolkitDepLogLine -Log $log -Text 'line-a' -WithTimestamp
    Add-ToolkitDepLogLine -Log $log -Text 'line-b' -WithTimestamp
    Add-ToolkitDepLogLine -Log $log -Text 'line-c' -WithTimestamp
    Add-ToolkitDepLogLine -Log $log -Text 'line-d' -WithTimestamp
    Sync-ToolkitDepLogScrollToEnd -Log $log
    $max = Get-ToolkitDepLogMaxScroll -Log $log -ViewportRows 3
    if ($log.ScrollOffset -ne $max) {
        throw 'autoscroll should align to last viewport page'
    }

    $scrollOffset = 0
    $maxScroll = 5
    function BumpScroll([ref]$v) { if ($v.Value -lt $maxScroll) { $v.Value++ } }
    BumpScroll ([ref]$scrollOffset)
    $log.ScrollOffset = $scrollOffset
    if ($log.ScrollOffset -ne 1) {
        throw 'scroll offset should sync from local ref variable'
    }

    $promptState = @{
        LoggedPhases             = @{}
        InstallerAwaitingDialog  = $false
        InstallerPromptDismissed = $false
        InstallStarted           = $false
        WingetInstallSilent      = $false
        ExecuteAction            = 'Install'
    }
    $null = Get-ToolkitDepWingetOutputDecision -Line 'Starting package install' -OutputState $promptState
    if ($promptState.InstallerAwaitingDialog) {
        throw 'startInstall should not enter installer prompt wait for interactive installs'
    }
    if ($promptState.InstallStarted -or $promptState.InstallerPromptDismissed) {
        throw 'startInstall should not mark install started before confirmation'
    }
    $null = Get-ToolkitDepWingetOutputDecision -Line 'Installing' -OutputState $promptState
    if (-not $promptState.InstallerAwaitingDialog) {
        throw 'install phase should await installer confirmation for interactive installs'
    }
    $latePkg = Get-ToolkitDepWingetOutputDecision -Line 'C:\temp\setup.msi' -OutputState $promptState
    if (-not $promptState.InstallerAwaitingDialog) {
        throw 'installer package line should keep prompt wait active'
    }

    $awaitState = @{
        LoggedPhases             = @{}
        InstallerAwaitingDialog  = $false
        InstallerPromptDismissed = $false
        InstallStarted           = $false
        WingetInstallSilent      = $false
        ExecuteAction            = 'Install'
        PackageDisplayName       = 'Volta'
    }
    $null = Get-ToolkitDepWingetOutputDecision -Line 'C:\temp\setup.msi' -OutputState $awaitState
    if (-not $awaitState.InstallerAwaitingDialog) {
        throw 'installer package path should start prompt wait for interactive installs'
    }
    $suppressed = Get-ToolkitDepWingetOutputDecision -Line 'Downloading https://github.com/example/app.msi' -OutputState $awaitState
    if ($suppressed.LogText) {
        throw 'download lines should be suppressed while awaiting installer confirmation'
    }

    $uninstallFlow = @{
        LoggedPhases             = @{}
        InstallerAwaitingDialog  = $false
        InstallerPromptDismissed = $false
        InstallStarted           = $false
        ExecuteAction            = 'Uninstall'
        PackageDisplayName       = 'Volta'
        MaxPhaseRank             = 0
    }
    $null = Get-ToolkitDepWingetOutputDecision -Line 'Starting package uninstall' -OutputState $uninstallFlow
    if ($uninstallFlow.InstallerAwaitingDialog) {
        throw 'startUninstall should not enter uninstall prompt wait early'
    }
    $startUninstallDecision = Get-ToolkitDepWingetOutputDecision -Line 'Starting package uninstall' -OutputState @{
        LoggedPhases             = @{}
        InstallerAwaitingDialog  = $false
        InstallerPromptDismissed = $false
        ExecuteAction            = 'Uninstall'
        MaxPhaseRank             = 0
    }
    if ($startUninstallDecision.LogText) {
        throw 'startUninstall winget line should not log before uninstall confirmation'
    }
    $earlyPromptFlow = @{
        LoggedPhases             = @{}
        InstallerAwaitingDialog  = $false
        InstallerPromptDismissed = $false
        InstallStarted           = $false
        ExecuteAction            = 'Uninstall'
        PackageDisplayName       = 'Volta'
        MaxPhaseRank             = 0
    }
    $uninstallPrompt = Get-ToolkitDepWingetOutputDecision -Line 'C:\Temp\Volta\uninstall.exe' -OutputState $earlyPromptFlow
    if (-not $earlyPromptFlow.InstallerAwaitingDialog) {
        throw 'installer package should start uninstall prompt wait'
    }
    if (-not $uninstallPrompt.PendingLogTexts -or @($uninstallPrompt.PendingLogTexts).Count -lt 1) {
        throw 'uninstall prompt should backfill found log before prompt'
    }
    $afterConfirm = @{
        LoggedPhases             = @{ found = $true; interactivePrompt = $true }
        InstallerAwaitingDialog  = $true
        InstallerPromptDismissed = $false
        ExecuteAction            = 'Uninstall'
        PackageDisplayName       = 'Volta'
        MaxPhaseRank             = 50
    }
    $executeDecision = Get-ToolkitDepWingetOutputDecision -Line 'Uninstalling' -OutputState $afterConfirm
    if ([string]$executeDecision.LogText -notmatch '执行程序包卸载|Executing package uninstall') {
        throw 'execute uninstall log should appear after confirmation'
    }
    $silentUninstall = @{
        LoggedPhases             = @{ found = $true; startUninstall = $true }
        InstallerAwaitingDialog  = $false
        InstallerPromptDismissed = $false
        ExecuteAction            = 'Uninstall'
        PackageDisplayName       = 'Volta'
        MaxPhaseRank             = 20
    }
    $silentExecute = Get-ToolkitDepWingetOutputDecision -Line 'Uninstalling' -OutputState $silentUninstall
    if ([string]$silentExecute.LogText -notmatch '执行程序包卸载|Executing package uninstall') {
        throw 'silent uninstall should log execute package on uninstall phase'
    }
    $staleUninstall = @{
        LoggedPhases             = @{}
        InstallerPromptDismissed = $true
        MaxPhaseRank             = 60
        ExecuteAction            = 'Uninstall'
    }
    $staleFound = Get-ToolkitDepWingetOutputDecision -Line 'Found Volta [Volta.Volta]' -OutputState $staleUninstall
    if ($staleFound.LogText) {
        throw 'late found lines should be suppressed after uninstall confirmation'
    }
    $staleStart = Get-ToolkitDepWingetOutputDecision -Line 'Starting package uninstall' -OutputState $staleUninstall
    if ($staleStart.LogText) {
        throw 'late startUninstall lines should be suppressed after uninstall confirmation'
    }

    $verifyState = @{
        LoggedPhases             = @{}
        InstallerAwaitingDialog  = $false
        InstallerPromptDismissed = $false
        InstallStarted           = $false
    }
    $null = Get-ToolkitDepWingetOutputDecision -Line 'Successfully verified installer hash' -OutputState $verifyState
    if ($verifyState.InstallStarted -or $verifyState.InstallerPromptDismissed) {
        throw 'verify complete should not dismiss installer prompt early'
    }

    $uiProgress = New-ToolkitDepOperationUiState
    $uiProgress.ItemInFlight = $true
    $uiProgress.ItemSubPercent = 0
    $wingetProgress = @{
        InstallerAwaitingDialog  = $false
        InstallerPromptDismissed = $false
        WingetInstallSilent      = $false
        SubstantiveLogCount      = 0
        PercentStage             = 'download'
    }
    $dlDecision = @{ ProgressPhase = 'download'; Percent = -1; LogText = 'downloading'; RedrawOnly = $false }
    Update-ToolkitDepWingetProgressFromDecision -Ui $uiProgress -WingetOutputState $wingetProgress -Decision $dlDecision
    if ([int]$uiProgress.ItemSubPercent -lt 4) {
        throw "download phase should bump progress from log, got $($uiProgress.ItemSubPercent)"
    }
    for ($i = 0; $i -lt 5; $i++) {
        Update-ToolkitDepWingetProgressFromDecision -Ui $uiProgress -WingetOutputState $wingetProgress `
            -Decision @{ Percent = 50; RedrawOnly = $true }
    }
    if ([int]$uiProgress.ItemSubPercent -lt 20) {
        throw "winget percent should map into progress band, got $($uiProgress.ItemSubPercent)"
    }
    $awaitProgress = @{
        InstallerAwaitingDialog  = $true
        InstallerPromptDismissed = $false
        WingetInstallSilent      = $false
        SubstantiveLogCount      = 0
        PercentStage             = 'install'
    }
    $uiAwait = New-ToolkitDepOperationUiState
    $uiAwait.ItemInFlight = $true
    $uiAwait.ItemSubPercent = 48
    Update-ToolkitDepWingetProgressFromDecision -Ui $uiAwait -WingetOutputState $awaitProgress `
        -Decision @{ Percent = 80; RedrawOnly = $true }
    if ([int]$uiAwait.ItemSubPercent -gt 55) {
        throw "progress should hold during installer dialog, got $($uiAwait.ItemSubPercent)"
    }

    $creepUi = New-ToolkitDepOperationUiState
    $creepUi.ItemInFlight = $true
    $creepUi.ItemSubPercent = 60
    $creepUi.ExecuteStartTick = [Environment]::TickCount - 60000
    $creepState = @{
        WingetOutputSeen         = $true
        InstallerAwaitingDialog  = $false
        InstallerPromptDismissed = $true
        InstallStarted           = $true
        InstallStartedTick       = [Environment]::TickCount - 45000
    }
    $creepTarget = Get-ToolkitDepWingetTimeCreepTarget -Ui $creepUi -WingetOutputState $creepState
    if ($creepTarget -lt 80) {
        throw "install phase time creep should reach high eighties during long MSI, got $creepTarget"
    }
    for ($i = 0; $i -lt 8; $i++) {
        Sync-ToolkitDepWingetItemProgress -Ui $creepUi -WingetOutputState $creepState
    }
    if ([int]$creepUi.ItemSubPercent -lt 80) {
        throw "sync should advance item progress from time creep, got $($creepUi.ItemSubPercent)"
    }

    $successDecision = Get-ToolkitDepWingetOutputDecision -Line 'Successfully installed' -OutputState @{
        LoggedPhases = @{}
    }
    if ([string]$successDecision.ProgressPhase -ne 'wingetSuccess') {
        throw 'successful install line should map to wingetSuccess progress phase'
    }

    $installSteps = Get-ToolkitDepWingetProgressSteps -ExecuteAction 'Install'
    $foundTarget = Get-ToolkitDepWingetPhaseProgressTarget -Phase 'found' -ExecuteAction 'Install'
    $successTarget = Get-ToolkitDepWingetPhaseProgressTarget -Phase 'wingetSuccess' -ExecuteAction 'Install'
    $foundIndex = [array]::IndexOf($installSteps, 'found') + 1
    $expectedFound = [int][Math]::Floor(($foundIndex / $installSteps.Count) * 95)
    $expectedSuccess = 95
    if ($foundTarget -ne $expectedFound -or $successTarget -ne $expectedSuccess) {
        throw "install progress should be evenly stepped, got found=$foundTarget success=$successTarget"
    }

    $successState = @{ LoggedPhases = @{} }
    $null = Get-ToolkitDepWingetOutputDecision -Line '已成功安装' -OutputState $successState
    if (-not $successState.WingetOperationSucceeded) {
        throw 'success result should mark WingetOperationSucceeded'
    }

    $brandW = 48
    $bar = Format-ToolkitDepProgressBar -Current 0 -Total 1 -Name 'volta' -BrandInnerWidth $brandW
    $barItem = Format-ToolkitDepProgressBar -Total 2 -BrandInnerWidth $brandW -ItemIndex 1 -ItemSubPercent 45
    if ($barItem -notmatch ' 1/ 2$') {
        throw "item progress bar should show two-digit reserved count suffix, got: [$barItem]"
    }
    if ($barItem -match '01/02') {
        throw 'item progress bar should not zero-pad count suffix'
    }
    $barItemWide = Format-ToolkitDepProgressBar -Total 99 -BrandInnerWidth $brandW -ItemIndex 12 -ItemSubPercent 45
    if ((Get-DisplayWidth $barItem) -ne (Get-DisplayWidth $barItemWide)) {
        throw 'item progress bar width should stay fixed regardless of count digits'
    }
    $disp = Resolve-DepOperationProgressDisplay -ProgressCurrent 0 -ProgressTotal 2 `
        -ItemInFlight $true -ItemSubPercent 50
    if ($disp.ItemIndex -ne 1 -or $disp.ItemSubPercent -ne 25) {
        throw 'in-flight item 1 at 50% should show overall 25% on a 2-item batch'
    }
    $dispSingle = Resolve-DepOperationProgressDisplay -ProgressCurrent 0 -ProgressTotal 1 `
        -ItemInFlight $true -ItemSubPercent 100
    if ($dispSingle.ItemSubPercent -ne 100) {
        throw 'single in-flight item at 100% sub should show 100% overall'
    }
    $dispDone = Resolve-DepOperationProgressDisplay -ProgressCurrent 1 -ProgressTotal 1 `
        -ItemInFlight $false -ItemSubPercent -1
    if ($dispDone.ItemSubPercent -ne 100) {
        throw 'completed single-item batch should stay at 100%'
    }
    $sep = Format-ToolkitShellLayoutSeparator -BrandInnerWidth $brandW
    if ((Get-DisplayWidth $bar) -ne (Get-DisplayWidth $sep)) {
        throw 'progress bar width should match log separator width'
    }
    $brandWrite = Get-BrandContentWriteWidth -BrandInnerWidth $brandW
    $contentWrite = Get-ToolkitShellLayoutLineWidth -BrandInnerWidth $brandW
    if ($brandWrite -ne $contentWrite) {
        throw "brand and content write widths should match, brand=$brandWrite content=$contentWrite"
    }

    $mockShell = @{
        BrandDrawn = $true
        Layout     = @{ ContentStartRow = 14 }
    }
    if (-not (Test-ToolkitShellBrandRowWriteBlocked -Row 5 -Shell $mockShell)) {
        throw 'brand row guard should block writes inside brand panel rows'
    }
    if (Test-ToolkitShellBrandRowWriteBlocked -Row 14 -Shell $mockShell) {
        throw 'brand row guard should allow writes at content start row'
    }

    $mayPrompt = Get-I18nRaw -Key 'page.depOperation.logMayPrompt'
    $wrapWidth = Get-ToolkitDepLogWrapWidth -Kind heading -BrandInnerWidth $brandW
    $wrapped = Split-DisplayTextToLines -Text $mayPrompt -MaxWidth $wrapWidth
    if (@($wrapped).Count -lt 2) {
        throw 'logMayPrompt should wrap to multiple log lines at standard brand width'
    }
    $mockLayout = @{
        ListStartRow    = 15
        ListEndRow      = 28
        MessageRow          = 29
        ContentStartRow = 13
    }
    $logLayout = Get-ToolkitDepOperationLogLayout -Layout $mockLayout
    if ([int]$logLayout.SeparatorRow -lt 13) {
        throw 'log separator row must stay below brand content start row'
    }

    $elapsedRunning = Format-ToolkitDepOperationElapsedLabel -Seconds 1 -Mode running
    $elapsedTotal = Format-ToolkitDepOperationElapsedLabel -Seconds 1111 -Mode total
    if ($elapsedRunning -notmatch '已执行:\s+1s$') {
        throw "expected spaced elapsed slot for 1s, got: [$elapsedRunning]"
    }
    if ($elapsedTotal -ne '共执行:1111s') {
        throw "expected total elapsed 1111s without zero pad, got: [$elapsedTotal]"
    }
    if ((Get-DisplayWidth $elapsedRunning) -ne (Get-DisplayWidth $elapsedTotal)) {
        throw 'elapsed label width should stay fixed across digit counts'
    }

    $summary = Get-ToolkitDepBatchSummarySegments -Intent install -TotalCount 11 -SuccessCount 10 -FailedCount 11
    $summaryText = ($summary | ForEach-Object { $_.Text }) -join ''
    if ($summaryText -notmatch '完成: 共计 11 项 \| 成功 10 项 \| 失败 11 项') {
        throw "unexpected batch summary text for two-digit counts: [$summaryText]"
    }
    $summaryOne = Get-ToolkitDepBatchSummarySegments -Intent install -TotalCount 1 -SuccessCount 1 -FailedCount 1
    $summaryOneText = ($summaryOne | ForEach-Object { $_.Text }) -join ''
    if ($summaryOneText -notmatch '完成: 共计  1 项 \| 成功  1 项 \| 失败  1 项') {
        throw "unexpected batch summary text for one-digit counts: [$summaryOneText]"
    }

    $lockLine = 'remove: The process cannot access the file because it is being used by another process.'
    if (-not (Test-WingetDepStreamLineIsFileLockRemoveError -Line $lockLine)) {
        throw 'file lock remove line should be detected'
    }
    if (Test-WingetDepStreamLineIsNonStallActivity -Line $lockLine) {
        throw 'file lock remove line should not reset stall idle timer'
    }
    $lockResult = @{
        Success  = $false
        ExitCode = -1978335229
        Lines    = @($lockLine)
    }
    if (-not (Test-WingetDepResultIsTempFileLockFailure -Result $lockResult)) {
        throw 'file lock result should be classified as temp file lock failure'
    }

    $policy = Get-WingetDepPolicyConstants
    if ([int]$policy.FileLockMaxRetries -lt 1) {
        throw 'file lock retry policy should allow at least one attempt'
    }
    $tempPaths = Get-WingetDepStaleTempPaths
    if ($null -eq $tempPaths) {
        throw 'Get-WingetDepStaleTempPaths should return an array'
    }

    $ui = New-ToolkitDepOperationUiState
    Set-ToolkitDepOperationInFlightStatus -Ui $ui -MainText '正在检测 volta…'
    if ($ui.StatusText -notmatch '^[\|\\/\-\s] 正在检测 volta…$') {
        throw "expected spinner-prefixed in-flight status, got: [$($ui.StatusText)]"
    }

    $logLayout = Get-ToolkitDepOperationLogLayout -Layout @{
        ListStartRow = 5
        ListEndRow   = 20
        MessageRow       = -1
    }
    if ($logLayout.ContentStartRow -ne $logLayout.SeparatorRow) {
        throw 'log content should start at first log row without a fixed separator line'
    }

    $uninstallAbort = @{
        Success  = $false
        ExitCode = 1603
        Lines    = @('卸载失败，退出代码为: 1603')
    }
    if (-not (Test-WingetDepResultIsUserCancelled $uninstallAbort)) {
        throw 'MSI exit 1603 should count as user abort'
    }
    if ((Get-WingetDepResultDeclineKind $uninstallAbort) -ne 'user') {
        throw 'MSI exit 1603 should classify as user decline'
    }

    $runnerState = @{
        SuccessCount = 0
        FailedCount  = 0
        Cancelled    = $false
        Failed       = $false
    }
    Register-ToolkitDepRunnerItemResult -RunnerState $runnerState -Result 'failed'
    $runner = [pscustomobject]@{ State = $runnerState }
    if (Test-ToolkitDepRunnerSuccess -Runner $runner) {
        throw 'runner with failed item should not report success'
    }

    $installDecline = Get-ToolkitDepDeclineLogText -DeclineKind user -ExecuteAction Install
    $upgradeDecline = Get-ToolkitDepDeclineLogText -DeclineKind user -ExecuteAction Upgrade
    $uninstallDecline = Get-ToolkitDepDeclineLogText -DeclineKind user -ExecuteAction Uninstall
    if ($installDecline -ne (Get-I18nRaw -Key 'page.depOperation.logInstallerDeclined.Install')) {
        throw 'install decline log should use install-specific i18n'
    }
    if ($upgradeDecline -ne (Get-I18nRaw -Key 'page.depOperation.logInstallerDeclined.Upgrade')) {
        throw 'upgrade decline log should use upgrade-specific i18n'
    }
    if ($uninstallDecline -ne (Get-I18nRaw -Key 'page.depOperation.logInstallerDeclined.Uninstall')) {
        throw 'uninstall decline log should use uninstall-specific i18n'
    }

    $chromeUi = New-ToolkitDepOperationUiState
    Start-ToolkitDepOperationBatch -Ui $chromeUi
    $chromePoll = @{ LastSpinnerTick = 0 }
    $spinnerBefore = [string]$chromeUi.StatusText
    Start-Sleep -Milliseconds 220
    $null = Sync-ToolkitDepOperationStatusChrome -Ui $chromeUi -PollState $chromePoll
    $spinnerAfter = [string]$chromeUi.StatusText
    if ($spinnerBefore -eq $spinnerAfter) {
        throw 'status chrome sync should advance spinner independently of status text changes'
    }
    if ([string]::IsNullOrWhiteSpace([string]$chromeUi.StatusRightText)) {
        throw 'status chrome sync should refresh elapsed label'
    }
    if ([int]$chromeUi.ElapsedDisplaySecond -ne 0) {
        throw 'elapsed display should stay at 0 before the first full second'
    }
    Start-Sleep -Milliseconds 900
    $null = Sync-ToolkitDepOperationStatusChrome -Ui $chromeUi -PollState $chromePoll
    $elapsedAfter = [int]$chromeUi.ElapsedDisplaySecond
    if ($elapsedAfter -ne 1) {
        throw "elapsed display should reach 1 only after a full second, got $elapsedAfter"
    }
    for ($pulse = 0; $pulse -lt 5; $pulse++) {
        $null = Sync-ToolkitDepOperationStatusChrome -Ui $chromeUi -PollState $chromePoll
        Start-Sleep -Milliseconds 50
    }
    if ([int]$chromeUi.ElapsedDisplaySecond -ne 1) {
        throw 'elapsed display should not advance multiple seconds within one wall second'
    }

    $completeUi = New-ToolkitDepOperationUiState
    Start-ToolkitDepOperationBatch -Ui $completeUi
    $completeUi.ItemInFlight = $true
    Start-Sleep -Milliseconds 1100
    $null = Sync-ToolkitDepOperationStatusChrome -Ui $completeUi -PollState @{ LastSpinnerTick = 0 }
    Set-ToolkitDepOperationBatchCompleteUi -Ui $completeUi -Intent install -TotalCount 1 -SuccessCount 1 -FailedCount 0
    $totalLabel = [string]$completeUi.StatusRightText
    if ($totalLabel -notmatch '共执行:|Total elapsed:') {
        throw "batch complete should show total elapsed label, got: [$totalLabel]"
    }
    $null = Sync-ToolkitDepOperationStatusChrome -Ui $completeUi -PollState @{ LastSpinnerTick = 0 }
    if ([string]$completeUi.StatusRightText -ne $totalLabel) {
        throw "completed batch elapsed should stay on total label, got: [$($completeUi.StatusRightText)]"
    }
}

Write-Host 'test-dep-closure: OK'
