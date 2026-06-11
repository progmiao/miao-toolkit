$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$lib = Join-Path $root 'package\core\lib'
$bin = Join-Path $root 'package\bin'
$toolRoot = Join-Path $root 'package\tools\node'

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
            'domain\Invoke-ToolkitDepOperation.ps1'
            'ui\shell\DepOperationView.ps1'
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
    $dDl = Get-ToolkitDepWingetOutputDecision -Line '  ██████████████████████████████  45%' -OutputState $outputState
    if ($dDl.LogText -notmatch '45') {
        throw 'download percent milestone should log partial download progress'
    }
    $outputState.LastLoggedPercent = 90
    $dDone = Get-ToolkitDepWingetOutputDecision -Line '  ██████████████████████████████  100%' -OutputState $outputState
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

    $log = New-ToolkitDepOperationLog
    $log.BrandInnerWidth = 48
    $log.ViewportRows = 3
    $longCmd = 'winget install --id Volta.Volta --exact --disable-interactivity --accept-package-agreements --accept-source-agreements'
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
    }
    $null = Get-ToolkitDepWingetOutputDecision -Line 'Starting package install' -OutputState $promptState
    $latePkg = Get-ToolkitDepWingetOutputDecision -Line 'C:\temp\setup.msi' -OutputState $promptState
    if ($promptState.InstallerAwaitingDialog) {
        throw 'installer package line after startInstall should not re-enable prompt'
    }
    if (-not $promptState.InstallerPromptDismissed) {
        throw 'startInstall should dismiss installer prompt phase'
    }

    $brandW = 48
    $bar = Format-ToolkitDepProgressBar -Current 0 -Total 1 -Name 'volta' -BrandInnerWidth $brandW
    $sep = Format-ToolkitShellContentSeparator -BrandInnerWidth $brandW
    if ((Get-DisplayWidth $bar) -ne (Get-DisplayWidth $sep)) {
        throw 'progress bar width should match log separator width'
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
}

Write-Host 'test-dep-closure: OK'
