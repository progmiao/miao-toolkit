# 批量执行 — 视图绘制（进度条、状态行、日志区）
# 官方组件名：**批量执行**。入口与 API 别名见同目录 BatchExecution.ps1。

$script:ToolkitDepLogMaxLines = 500
$script:ToolkitDepLogTimeWidth = 8
$script:DepOperationFnCache = $null

function Initialize-DepOperationFnCache {
    if ($null -ne $script:DepOperationFnCache) { return }
    $script:DepOperationFnCache = @{}
}

function Register-DepOperationFnCache {
    Initialize-DepOperationFnCache
    foreach ($name in @(
            'Enter-ConsoleDrawBatch'
            'Complete-ConsoleDrawBatch'
            'Write-FixedLine'
            'Get-I18n'
            'Format-ToolkitDepProgressBar'
            'Format-ToolkitDepOperationStatusLine'
            'Resolve-DepOperationProgressDisplay'
            'Format-ToolkitDepLogLineText'
            'Get-BrandSeparatorLineWidth'
            'Format-ToolkitShellLayoutSeparator'
            'Pad-DisplayText'
            'Get-DisplayWidth'
            'Truncate-DisplayText'
            'Split-DisplayTextToLines'
            'Get-ToolkitDepLogMaxScroll'
            'Sync-ToolkitDepLogScrollToEnd'
            'Get-ToolkitDepLogWrapWidth'
            'Get-ToolkitDepOperationLogLayout'
            'Update-ToolkitDepLoadingStatus'
            'Invoke-ToolkitDepLogInputIfAvailable'
            'Draw-ToolkitDepOperationView'
            'Draw-ToolkitDepOperationLogViewport'
            'Write-ToolkitDepFixedLineSegments'
            'Get-ToolkitDepBatchSummarySegments'
            'Get-ToolkitDepStatusText'
            'Add-ToolkitDepLogLine'
            'Add-ToolkitDepLogSeparator'
            'Add-ToolkitDepLogSection'
            'Write-ToolkitDepPlanDetectLog'
            'Invoke-ToolDepPackageExecute'
            'Invoke-ToolkitRuntimeExecute'
            'Set-ToolDepPackageVersion'
            'Remove-GlobalDepPackage'
            'Update-ToolDepSessionPath'
            'Test-ToolDepCommandAvailable'
            'Resolve-ToolDepPackageVersionAfterAction'
            'Resolve-ToolDepCheckCommandVersion'
            'Get-ToolDepPackageRecordableVersion'
            'Sync-ToolDepInstalledState'
            'Complete-ToolkitDepUninstallRecord'
            'Get-ToolkitDepOperationSummaryKey'
            'Test-WingetDepResultIsAlreadyRemoved'
            'Test-WingetDepResultReportsUninstallSuccess'
            'Test-ToolDepPackageRemovedAfterAction'
            'Test-WingetDepStreamLineIsEphemeral'
            'Test-WingetDepResultIsUserCancelled'
            'Get-WingetDepResultDeclineKind'
            'Test-WingetDepStreamLineIsDeclined'
            'Get-WingetDepStreamLineDeclineKind'
            'Test-WingetDepResultNoApplicableInstaller'
            'Get-WingetDepResultSummaryLine'
            'Get-WingetDepStreamLinePercent'
            'Test-WingetDepZhStreamPhrase'
            'Get-WingetDepStreamLinePhase'
            'Test-WingetDepStreamLineIsProgressVisual'
            'Test-WingetDepStreamLineIsFileLockRemoveError'
            'Test-ToolDepWingetInstallUsesSilent'
            'Test-ToolDepPackageNetworkPreflight'
            'Test-WingetDepResultNeedsInteractiveRetry'
            'Get-WingetDepPolicyConstants'
            'Test-WingetDepResultIsTempFileLockFailure'
            'Repair-WingetDepFileLockEnvironment'
            'Get-WingetDepStaleTempPaths'
            'Test-WingetStreamLineIsSpinnerOnly'
            'Get-WingetStreamLineCleanText'
            'Test-ConsoleKeyAvailable'
            'Get-ToolDepWingetCommandLine'
            'Get-ToolkitDepWingetOutputDecision'
            'Read-ShellSystemToolbarKey'
            'Clear-ShellExit'
            'Clear-ShellExitExtension'
            'Register-ShellExitExtension'
            'Process-ShellEscInputIfAvailable'
            'Get-ConsoleVirtualKeyPeek'
            'Read-ConsoleVirtualKeyConsume'
            'Clear-ConsoleInputBuffer'
            'Drain-ConsoleEscInputIfAvailable'
            'Drain-ConsoleStaleToolbarInput'
            'Read-ShellExitIfActive'
        )) {
        if ($script:DepOperationFnCache.ContainsKey($name)) { continue }
        $cmd = Get-Command -Name $name -CommandType Function -ErrorAction SilentlyContinue
        if (-not $cmd) { continue }
        $script:DepOperationFnCache[$name] = $cmd.ScriptBlock
    }
}

function Resolve-DepOperationFn {
    param([string]$Name)

    Initialize-DepOperationFnCache
    if (-not $script:DepOperationFnCache) {
        $script:DepOperationFnCache = @{}
    }
    if ($script:DepOperationFnCache.ContainsKey($Name)) {
        return $script:DepOperationFnCache[$Name]
    }

    $cmd = Get-Command -Name $Name -CommandType Function -ErrorAction Stop
    $script:DepOperationFnCache[$Name] = $cmd.ScriptBlock
    return $cmd.ScriptBlock
}

function New-ToolkitDepOperationLog {
    return [ordered]@{
        Lines           = [System.Collections.Generic.List[object]]::new()
        AutoScroll      = $true
        ScrollOffset    = 0
        ViewportRows    = 0
        BrandInnerWidth = 0
    }
}

function Get-ToolkitDepOperationLogLines {
    param($Log)

    if ($null -eq $Log) { return $null }

    # 必须用一元逗号返回 List，否则 PowerShell 会枚举/解包，空列表变 $null、单条变元素本身
    if ($Log -is [System.Collections.IDictionary] -and $Log.Contains('Lines')) {
        return ,$Log['Lines']
    }

    if ($null -ne $Log.Lines) {
        return ,$Log.Lines
    }

    return $null
}

function Get-ToolkitDepOperationLogLayout {
    param([hashtable]$Layout)

    $listStart = [int]$Layout.ListStartRow
    $listEnd = [int]$Layout.ListEndRow
    $messageRow = [int]$Layout.MessageRow
    $maxPaintRow = if ($messageRow -ge 0) { [Math]::Min($listEnd, $messageRow - 1) } else { $listEnd }

    $idealContentStartRow = $listStart + 3
    $contentStartRow = [Math]::Min($idealContentStartRow, $maxPaintRow)
    if ($contentStartRow -lt ($listStart + 2)) {
        $contentStartRow = [Math]::Min($listStart + 2, $maxPaintRow)
    }

    $brandEnd = if ($Layout.ContentStartRow -gt 0) { [int]$Layout.ContentStartRow } else { 0 }
    if ($brandEnd -gt 0 -and $contentStartRow -lt $brandEnd) {
        $contentStartRow = [Math]::Min($brandEnd, $maxPaintRow)
    }
    if ($contentStartRow -lt $listStart) {
        $contentStartRow = [Math]::Min($listStart, $maxPaintRow)
    }

    $contentViewportRows = 0
    if ($contentStartRow -le $maxPaintRow) {
        $contentViewportRows = $maxPaintRow - $contentStartRow + 1
    }

    return @{
        SeparatorRow          = $contentStartRow
        ContentStartRow       = $contentStartRow
        ContentViewportRows   = $contentViewportRows
        MaxPaintRow           = $maxPaintRow
    }
}

function Get-ToolkitDepLogWrapWidth {
    param(
        [string]$Kind,
        [int]$BrandInnerWidth,
        [int]$TimeWidth = $script:ToolkitDepLogTimeWidth
    )

    if ($BrandInnerWidth -le 0) { return 0 }

    $fnLineWidth = Resolve-DepOperationFn 'Get-BrandSeparatorLineWidth'
    $inner = if (Get-Command Get-BrandSeparatorLineWidth -CommandType Function -ErrorAction SilentlyContinue) {
        Get-BrandSeparatorLineWidth -BrandInnerWidth $BrandInnerWidth
    }
    else {
        & $fnLineWidth -BrandInnerWidth $BrandInnerWidth
    }
    if ($Kind -eq 'separator') {
        return $inner
    }
    if ($Kind -in @('hint', 'spacer')) {
        return [Math]::Max(8, $inner - $TimeWidth - 1)
    }

    return [Math]::Max(8, $inner - $TimeWidth - 1)
}

function Sync-ToolkitDepLogScrollToEnd {
    param($Log)

    if ($null -eq $Log) { return }
    if ([int]$Log.ViewportRows -le 0) { return }

    $fnMaxScroll = Resolve-DepOperationFn 'Get-ToolkitDepLogMaxScroll'
    $Log.ScrollOffset = & $fnMaxScroll -Log $Log -ViewportRows ([int]$Log.ViewportRows)
}

function Add-ToolkitDepLogLine {
    param(
        $Log,
        [string]$Text,
        [string]$Kind = 'text',
        [System.ConsoleColor]$Color = [System.ConsoleColor]::Gray,
        [switch]$WithTimestamp
    )

    if ($null -eq $Log) { return }

    $lineList = Get-ToolkitDepOperationLogLines -Log $Log
    if ($null -eq $lineList) { return }

    $lineColor = $Color
    if ($Kind -eq 'section') { $lineColor = [System.ConsoleColor]::Cyan }
    elseif ($Kind -in @('separator', 'hint')) { $lineColor = [System.ConsoleColor]::DarkGray }

    $brandInnerWidth = [int]$Log.BrandInnerWidth
    $wrapWidth = if ($Kind -ne 'separator' -and $brandInnerWidth -gt 0) {
        Get-ToolkitDepLogWrapWidth -Kind $Kind -BrandInnerWidth $brandInnerWidth
    }
    else { 0 }

    $fnSplit = Resolve-DepOperationFn 'Split-DisplayTextToLines'
    $textLines = if ($wrapWidth -gt 0 -and -not [string]::IsNullOrEmpty($Text)) {
        if (Get-Command Split-DisplayTextToLines -CommandType Function -ErrorAction SilentlyContinue) {
            @(Split-DisplayTextToLines -Text $Text -MaxWidth $wrapWidth)
        }
        else {
            @(& $fnSplit -Text $Text -MaxWidth $wrapWidth)
        }
    }
    else {
        @([string]$Text)
    }

    $isFirst = $true
    foreach ($textLine in $textLines) {
        $timestamp = if ($WithTimestamp -and $isFirst) { (Get-Date).ToString('HH:mm:ss') } else { '' }
        $lineList.Add([pscustomobject]@{
            Timestamp = $timestamp
            Text      = [string]$textLine
            Kind      = $Kind
            Color     = $lineColor
        }) | Out-Null
        $isFirst = $false
    }

    while ($lineList.Count -gt $script:ToolkitDepLogMaxLines) {
        if ($lineList.Count -le 0) { break }
        $lineList.RemoveAt(0) | Out-Null
        if ($Log.ScrollOffset -gt 0) { $Log.ScrollOffset-- }
    }

    if ($Log.AutoScroll) {
        Sync-ToolkitDepLogScrollToEnd -Log $Log
    }
}

function Get-ToolkitDepLogMaxScroll {
    param($Log, [int]$ViewportRows)

    $lineList = Get-ToolkitDepOperationLogLines -Log $Log
    $lineCount = if ($lineList) { [int]$lineList.Count } else { 0 }
    return [Math]::Max(0, $lineCount - $ViewportRows)
}

function Get-ToolkitDepWingetPhaseRank {
    param([string]$Phase)

    switch ($Phase) {
        'found' { return 10 }
        'waitOther' { return 15 }
        'startInstall' { return 20 }
        'startUninstall' { return 20 }
        'download' { return 30 }
        'verify' { return 40 }
        'installerPackage' { return 50 }
        'install' { return 60 }
        'uninstall' { return 60 }
        'result' { return 100 }
        default { return 0 }
    }
}

function Update-ToolkitDepWingetMaxPhaseRank {
    param(
        $OutputState,
        [int]$Rank
    )

    if ($Rank -le 0) { return }
    $current = if ($null -ne $OutputState['MaxPhaseRank']) { [int]$OutputState['MaxPhaseRank'] } else { 0 }
    if ($Rank -gt $current) {
        $OutputState['MaxPhaseRank'] = $Rank
    }
}

function Test-ToolkitDepShouldSuppressWingetStalePhaseLog {
    param(
        $OutputState,
        [string]$Phase
    )

    $rank = Get-ToolkitDepWingetPhaseRank -Phase $Phase
    if ($rank -le 0) { return $false }

    $maxRank = if ($null -ne $OutputState['MaxPhaseRank']) { [int]$OutputState['MaxPhaseRank'] } else { 0 }
    if ($rank -lt $maxRank) { return $true }

    if ([bool]$OutputState['InstallerPromptDismissed'] -and $rank -lt 60) {
        return $true
    }

    return $false
}

function Get-ToolkitDepWingetPromptStatusText {
    param(
        $OutputState,
        $GetI18n
    )

    if ([string]$OutputState['ExecuteAction'] -eq 'Uninstall') {
        return (& $GetI18n -Key 'page.depOperation.statusUninstallPromptPlain')
    }

    return (& $GetI18n -Key 'page.depOperation.statusInstallerPromptPlain')
}

function Resolve-ToolkitDepWingetFoundLogText {
    param(
        [string]$Line,
        $OutputState,
        $GetI18n
    )

    $name = [string]$OutputState['PackageDisplayName']
    if ([string]::IsNullOrWhiteSpace($name) -and -not [string]::IsNullOrWhiteSpace($Line)) {
        if ($Line -match '^(?:Found|已找到)\s+(.+?)(?:\s+\[|\s+Version|\s+版本|\s*$)') {
            $name = [string]$Matches[1].Trim()
        }
    }

    if ([string]::IsNullOrWhiteSpace($name)) {
        return (& $GetI18n -Key 'page.depOperation.logFoundPackage')
    }

    return (& $GetI18n -Key 'page.depOperation.logFoundPackageNamed' -Vars @{ name = $name })
}

function Add-ToolkitDepExecutePackageLogIfDue {
    param(
        $OutputState,
        $Decision,
        $GetI18n
    )

    if ($OutputState.LoggedPhases.ContainsKey('executePackage')) { return $false }

    $executeAction = [string]$OutputState['ExecuteAction']
    $installSilent = [bool]$OutputState['WingetInstallSilent']
    $promptDismissed = [bool]$OutputState['InstallerPromptDismissed']

    if ($executeAction -eq 'Uninstall') {
        if (-not $promptDismissed -and (Test-ToolkitDepWingetOutputAwaitingUser -OutputState $OutputState)) {
            return $false
        }
    }
    elseif (-not $installSilent -and -not $promptDismissed) {
        return $false
    }

    $OutputState.LoggedPhases['executePackage'] = $true
    $OutputState.LoggedPhases['startInstall'] = $true
    $OutputState.LoggedPhases['startUninstall'] = $true
    Update-ToolkitDepWingetMaxPhaseRank -OutputState $OutputState -Rank 20

    $key = if ($executeAction -eq 'Uninstall') {
        'page.depOperation.logExecuteUninstall'
    }
    else {
        'page.depOperation.logExecuteInstall'
    }
    $text = & $GetI18n -Key $key

    if ([string]::IsNullOrWhiteSpace([string]$Decision.LogText)) {
        $Decision.LogText = $text
    }
    else {
        $pending = if ($Decision.PendingLogTexts) { @($Decision.PendingLogTexts) } else { @() }
        $Decision.PendingLogTexts = @(@($text) + @($pending))
    }
    $Decision.ProgressPhase = 'executePackage'

    return $true
}

function Add-ToolkitDepWingetPrerequisiteLogTexts {
    param(
        $OutputState,
        $Decision,
        $GetI18n
    )

    $pending = New-Object 'System.Collections.Generic.List[string]'

    if (-not $OutputState.LoggedPhases.ContainsKey('found')) {
        $OutputState.LoggedPhases['found'] = $true
        Update-ToolkitDepWingetMaxPhaseRank -OutputState $OutputState -Rank 10
        [void]$pending.Add((Resolve-ToolkitDepWingetFoundLogText -Line '' -OutputState $OutputState -GetI18n $GetI18n))
    }

    if ($pending.Count -gt 0) {
        $Decision.PendingLogTexts = @($pending.ToArray())
    }
}

function Enter-ToolkitDepWingetInteractivePromptPhase {
    param(
        $OutputState,
        $Decision,
        $GetI18n,
        [string]$PromptLogKey
    )

    Add-ToolkitDepWingetPrerequisiteLogTexts -OutputState $OutputState -Decision $Decision -GetI18n $GetI18n
    Update-ToolkitDepWingetMaxPhaseRank -OutputState $OutputState -Rank 50

    if ([int]$OutputState['InstallerPromptStartTick'] -le 0) {
        $OutputState['InstallerPromptStartTick'] = [Environment]::TickCount
    }
    $OutputState['InstallerAwaitingDialog'] = $true

    if (-not $OutputState.LoggedPhases.ContainsKey('interactivePrompt')) {
        $OutputState.LoggedPhases['interactivePrompt'] = $true
        $Decision.LogText = & $GetI18n -Key $PromptLogKey
    }

    $Decision.StatusText = Get-ToolkitDepWingetPromptStatusText -OutputState $OutputState -GetI18n $GetI18n
}

function Test-ToolkitDepWingetOutputAwaitingUser {
    param($OutputState)

    return ([bool]$OutputState['InstallerAwaitingDialog'] -and -not [bool]$OutputState['InstallerPromptDismissed'])
}

function Test-ToolkitDepShouldSuppressWingetDownloadLog {
    param(
        $OutputState,
        [string]$Phase = ''
    )

    if (-not (Test-ToolkitDepWingetOutputAwaitingUser -OutputState $OutputState)) {
        return $false
    }

    return ($Phase -in @('download', 'info', 'progress', 'verify', 'found', 'startInstall', 'startUninstall', 'waitOther'))
}

function Complete-ToolkitDepInstallerPromptPhase {
    param($OutputState)

    $OutputState['InstallerPromptDismissed'] = $true
    $OutputState['InstallerAwaitingDialog'] = $false
    $OutputState['InstallStarted'] = $true
    if ([int]$OutputState['InstallStartedTick'] -le 0) {
        $OutputState['InstallStartedTick'] = [Environment]::TickCount
    }
    Update-ToolkitDepWingetMaxPhaseRank -OutputState $OutputState -Rank 60
}

function Get-ToolkitDepWingetProgressSteps {
    param(
        [string]$ExecuteAction = 'Install'
    )

    if ([string]$ExecuteAction -eq 'Uninstall') {
        return @(
            'detect'
            'run'
            'found'
            'waitOther'
            'executePackage'
            'installerPackageInteractive'
            'uninstall'
            'wingetSuccess'
        )
    }

    return @(
        'detect'
        'preflight'
        'run'
        'found'
        'waitOther'
        'executePackage'
        'download'
        'verify'
        'verifyComplete'
        'installerPackageInteractive'
        'install'
        'wingetSuccess'
    )
}

function Resolve-ToolkitDepWingetProgressPhaseName {
    param([string]$Phase)

    switch ([string]$Phase) {
        'startInstall' { return 'executePackage' }
        'startUninstall' { return 'executePackage' }
        'installerPackage' { return 'installerPackageInteractive' }
        'installerPackageSilent' { return 'installerPackageInteractive' }
        default { return [string]$Phase }
    }
}

function Get-ToolkitDepWingetProgressStepIndex {
    param(
        [string]$Phase,
        [string]$ExecuteAction = 'Install'
    )

    $normalized = Resolve-ToolkitDepWingetProgressPhaseName -Phase $Phase
    $steps = Get-ToolkitDepWingetProgressSteps -ExecuteAction $ExecuteAction
    return [array]::IndexOf($steps, $normalized)
}

function Get-ToolkitDepWingetPhaseProgressBand {
    param(
        [string]$Phase,
        [string]$ExecuteAction = 'Install'
    )

    $index = Get-ToolkitDepWingetProgressStepIndex -Phase $Phase -ExecuteAction $ExecuteAction
    if ($index -lt 0) { return $null }

    $steps = Get-ToolkitDepWingetProgressSteps -ExecuteAction $ExecuteAction
    $count = $steps.Count
    if ($count -le 0) { return $null }

    $base = if ($index -le 0) {
        0
    }
    else {
        [int][Math]::Floor(($index / [double]$count) * 95)
    }
    $end = [int][Math]::Floor((($index + 1) / [double]$count) * 95)
    if ($end -le $base) { $end = $base + 1 }

    return @{
        Base = $base
        End  = $end
    }
}

function Get-ToolkitDepWingetPhaseProgressTarget {
    param(
        [string]$Phase,
        [string]$ExecuteAction = 'Install'
    )

    $index = Get-ToolkitDepWingetProgressStepIndex -Phase $Phase -ExecuteAction $ExecuteAction
    if ($index -lt 0) { return -1 }

    $steps = Get-ToolkitDepWingetProgressSteps -ExecuteAction $ExecuteAction
    $count = $steps.Count
    if ($count -le 0) { return -1 }

    return [int][Math]::Floor((($index + 1) / [double]$count) * 95)
}

function Get-ToolkitDepRunnerProgressPhaseTarget {
    param(
        [string]$Phase,
        [string]$ExecuteAction = 'Install'
    )

    switch ([string]$Phase) {
        'detect' { return (Get-ToolkitDepWingetPhaseProgressTarget -Phase 'detect' -ExecuteAction $ExecuteAction) }
        'preflight' {
            if ([string]$ExecuteAction -eq 'Uninstall') { return -1 }
            return (Get-ToolkitDepWingetPhaseProgressTarget -Phase 'preflight' -ExecuteAction $ExecuteAction)
        }
        'run' { return (Get-ToolkitDepWingetPhaseProgressTarget -Phase 'run' -ExecuteAction $ExecuteAction) }
        'reconcile' { return (Get-ToolkitDepWingetPhaseProgressTarget -Phase 'wingetSuccess' -ExecuteAction $ExecuteAction) }
        'done' { return (Get-ToolkitDepWingetPhaseProgressTarget -Phase 'wingetSuccess' -ExecuteAction $ExecuteAction) }
        default { return -1 }
    }
}

function Convert-ToolkitDepWingetPercentToProgress {
    param(
        [int]$Percent,
        [string]$Stage,
        [string]$ExecuteAction = 'Install'
    )

    if ($Percent -lt 0) { return -1 }

    $stagePhase = switch ([string]$Stage) {
        'download' { 'download' }
        'install' { 'install' }
        'uninstall' { 'uninstall' }
        'verify' { 'verify' }
        default { $null }
    }
    if (-not $stagePhase) { return -1 }

    $band = Get-ToolkitDepWingetPhaseProgressBand -Phase $stagePhase -ExecuteAction $ExecuteAction
    if (-not $band) { return -1 }

    $span = [Math]::Max(1, $band.End - $band.Base)
    return $band.Base + [int][Math]::Round($Percent * $span / 100.0)
}

function Get-ToolkitDepItemElapsedSeconds {
    param($Ui)

    if ($null -eq $Ui -or [int]$Ui.ExecuteStartTick -le 0) { return 0 }
    return [int][Math]::Floor(([Environment]::TickCount - [int]$Ui.ExecuteStartTick) / 1000.0)
}

function Get-ToolkitDepWingetTimeCreepTarget {
    param(
        $Ui,
        $WingetOutputState
    )

    $executeAction = if ([string]$WingetOutputState['ExecuteAction'] -eq 'Uninstall') { 'Uninstall' } else { 'Install' }
    $current = if ($Ui) { [Math]::Max(0, [int]$Ui.ItemSubPercent) } else { 0 }
    $elapsed = Get-ToolkitDepItemElapsedSeconds -Ui $Ui

    if (-not [bool]$WingetOutputState['WingetOutputSeen']) {
        $band = Get-ToolkitDepWingetPhaseProgressBand -Phase 'run' -ExecuteAction $executeAction
        if (-not $band) {
            $band = Get-ToolkitDepWingetPhaseProgressBand -Phase 'detect' -ExecuteAction $executeAction
        }
        if (-not $band) { return [Math]::Max($current, [Math]::Min(7, 2 + [int][Math]::Floor($elapsed / 2.0))) }
        $cap = [Math]::Max($band.Base + 1, $band.End - 1)
        return [Math]::Max($current, [Math]::Min($cap, $band.Base + [int][Math]::Floor($elapsed / 2.0) + 1))
    }

    if ([bool]$WingetOutputState['InstallerAwaitingDialog'] `
            -and -not [bool]$WingetOutputState['InstallerPromptDismissed']) {
        $band = Get-ToolkitDepWingetPhaseProgressBand -Phase 'installerPackageInteractive' -ExecuteAction $executeAction
        if (-not $band) { return $current }
        $promptElapsed = $elapsed
        if ([int]$WingetOutputState['InstallerPromptStartTick'] -gt 0) {
            $promptElapsed = [int][Math]::Floor(([Environment]::TickCount `
                    - [int]$WingetOutputState['InstallerPromptStartTick']) / 1000.0)
        }
        $span = [Math]::Max(1, $band.End - $band.Base - 1)
        $promptTarget = $band.Base + [Math]::Min($span, [int][Math]::Floor($promptElapsed / 4.0) + 1)
        return [Math]::Max($current, [Math]::Min($band.End - 1, $promptTarget))
    }

    if ([bool]$WingetOutputState['InstallStarted']) {
        $runPhase = if ($executeAction -eq 'Uninstall') { 'uninstall' } else { 'install' }
        $runBand = Get-ToolkitDepWingetPhaseProgressBand -Phase $runPhase -ExecuteAction $executeAction
        $successTarget = Get-ToolkitDepWingetPhaseProgressTarget -Phase 'wingetSuccess' -ExecuteAction $executeAction
        if (-not $runBand) { return $current }
        $runElapsed = $elapsed
        if ([int]$WingetOutputState['InstallStartedTick'] -gt 0) {
            $runElapsed = [int][Math]::Floor(([Environment]::TickCount `
                    - [int]$WingetOutputState['InstallStartedTick']) / 1000.0)
        }
        $span = [Math]::Max(1, $runBand.End - $runBand.Base - 1)
        $runTarget = $runBand.Base + [Math]::Min($span - 1, [int][Math]::Floor($runElapsed * $span / 120.0))
        $cap = if ($successTarget -gt 0) { $successTarget - 1 } else { 94 }
        return [Math]::Max($current, [Math]::Min($cap, $runTarget))
    }

    $foundBand = Get-ToolkitDepWingetPhaseProgressBand -Phase 'found' -ExecuteAction $executeAction
    if (-not $foundBand) {
        return [Math]::Max($current, 12 + [int][Math]::Min(32, [Math]::Floor($elapsed / 5.0)))
    }
    $cap = [Math]::Max($foundBand.Base + 1, $foundBand.End - 1)
    $executeTarget = $foundBand.Base + [Math]::Min($foundBand.End - $foundBand.Base - 1, [int][Math]::Floor($elapsed / 5.0) + 1)
    return [Math]::Max($current, [Math]::Min($cap, $executeTarget))
}

function Apply-ToolkitDepWingetProgressUpdate {
    param(
        $Ui,
        $WingetOutputState,
        [int]$Target,
        [switch]$Jump,
        [switch]$AllowWhileAwaitingDialog
    )

    if (-not $Ui -or -not $Ui.ItemInFlight) { return }
    if ($Target -lt 0) { return }

    $current = [Math]::Max(0, [int]$Ui.ItemSubPercent)
    $awaiting = [bool]$WingetOutputState['InstallerAwaitingDialog'] `
        -and -not [bool]$WingetOutputState['InstallerPromptDismissed']

    if ($awaiting -and -not $AllowWhileAwaitingDialog) {
        $executeAction = if ([string]$WingetOutputState['ExecuteAction'] -eq 'Uninstall') { 'Uninstall' } else { 'Install' }
        $holdMax = Get-ToolkitDepWingetPhaseProgressTarget -Phase 'installerPackageInteractive' -ExecuteAction $executeAction
        if ($holdMax -gt 0) { $holdMax-- } else { $holdMax = 55 }
        if ($Target -gt $holdMax) { $Target = $holdMax }
        if ($Target -gt ($current + 1)) { $Target = $current + 1 }
        $Jump = $false
    }

    if ($Jump) {
        $next = [Math]::Max($current, $Target)
    }
    else {
        $delta = [Math]::Min(4, [Math]::Max(0, $Target - $current))
        $next = $current + $delta
    }

    if ($next -lt $current) { $next = $current }
    $cap = if ($Target -ge 100) { 100 } else { 99 }
    $Ui.ItemSubPercent = [Math]::Min($cap, $next)
}

function Sync-ToolkitDepWingetItemProgress {
    param(
        $Ui,
        $WingetOutputState,
        [int]$ElapsedSeconds = 0
    )

    if (-not $Ui.ItemInFlight) { return }

    $creepTarget = Get-ToolkitDepWingetTimeCreepTarget -Ui $Ui -WingetOutputState $WingetOutputState
    if ($creepTarget -gt [int]$Ui.ItemSubPercent) {
        Apply-ToolkitDepWingetProgressUpdate -Ui $Ui -WingetOutputState $WingetOutputState -Target $creepTarget
    }
}

function Update-ToolkitDepWingetProgressFromDecision {
    param(
        $Ui,
        $WingetOutputState,
        $Decision
    )

    if ($null -eq $Decision) { return }

    $executeAction = if ([string]$WingetOutputState['ExecuteAction'] -eq 'Uninstall') { 'Uninstall' } else { 'Install' }

    if ($null -ne $Decision.ProgressPhase) {
        $phaseTarget = Get-ToolkitDepWingetPhaseProgressTarget -Phase ([string]$Decision.ProgressPhase) `
            -ExecuteAction $executeAction
        if ($phaseTarget -ge 0) {
            Apply-ToolkitDepWingetProgressUpdate -Ui $Ui -WingetOutputState $WingetOutputState `
                -Target $phaseTarget
        }
    }

    if ([int]$Decision.Percent -ge 0) {
        $stage = [string]$WingetOutputState['PercentStage']
        if ([string]::IsNullOrWhiteSpace($stage)) { $stage = 'download' }
        $mapped = Convert-ToolkitDepWingetPercentToProgress -Percent ([int]$Decision.Percent) -Stage $stage `
            -ExecuteAction $executeAction
        if ($mapped -ge 0) {
            Apply-ToolkitDepWingetProgressUpdate -Ui $Ui -WingetOutputState $WingetOutputState -Target $mapped
        }
    }
    elseif ($Decision.LogText -and -not $Decision.RedrawOnly) {
        $substantiveCount = [int]$WingetOutputState['SubstantiveLogCount'] + 1
        $WingetOutputState['SubstantiveLogCount'] = $substantiveCount
        $foundTarget = Get-ToolkitDepWingetPhaseProgressTarget -Phase 'found' -ExecuteAction $executeAction
        if ($foundTarget -lt 0) { $foundTarget = 8 }
        $logTarget = [Math]::Min($foundTarget, 4 + ($substantiveCount * 2))
        Apply-ToolkitDepWingetProgressUpdate -Ui $Ui -WingetOutputState $WingetOutputState -Target $logTarget
    }
}

function Update-ToolkitDepLoadingStatus {
    param(
        $Ui,
        $WingetOutputState,
        [int]$ElapsedSeconds,
        [scriptblock]$GetI18n,
        [int]$IdleSeconds = -1
    )

    if (-not $Ui.ItemInFlight) { return $false }

    Sync-ToolkitDepWingetItemProgress -Ui $Ui -WingetOutputState $WingetOutputState -ElapsedSeconds $ElapsedSeconds

    if ([int]$Ui.ItemSubPercent -gt 0 -and -not $WingetOutputState['InstallerAwaitingDialog'] `
            -and -not ($WingetOutputState['InstallStarted'] -and -not $WingetOutputState['InstallerPromptDismissed']) `
            -and $WingetOutputState['WingetOutputSeen']) {
        return $false
    }

    $statusKey = 'page.depOperation.statusLoadingPlain'
    $executeAction = [string]$WingetOutputState['ExecuteAction']
    if ($WingetOutputState['InstallerAwaitingDialog']) {
        if ($executeAction -eq 'Uninstall') {
            $statusKey = 'page.depOperation.statusUninstallPromptPlain'
        }
        else {
            $statusKey = 'page.depOperation.statusInstallerPromptPlain'
        }
    }
    elseif ($WingetOutputState['InstallStarted'] -or $WingetOutputState['InstallerPromptDismissed']) {
        if ($executeAction -eq 'Uninstall') {
            $statusKey = 'page.depOperation.statusUninstallRunningPlain'
        }
        else {
            $statusKey = 'page.depOperation.statusInstallerRunningPlain'
        }
    }
    elseif (-not $WingetOutputState['WingetOutputSeen']) {
        $statusKey = 'page.depOperation.statusWingetStartingPlain'
    }

    $WingetOutputState['ElapsedSeconds'] = [int]$ElapsedSeconds
    Set-ToolkitDepOperationInFlightStatus -Ui $Ui -MainText (& $GetI18n -Key $statusKey) -AdvanceSpinner
    return $true
}

function Invoke-ToolkitDepLogInputIfAvailable {
    param(
        [hashtable]$Shell,
        $Log,
        [int]$ViewportRows,
        [scriptblock]$OnExitKey = $null,
        [hashtable]$ScrollState = $null
    )

    $fnTestKey = Resolve-DepOperationFn 'Test-ConsoleKeyAvailable'
    $fnPeekKey = Resolve-DepOperationFn 'Get-ConsoleVirtualKeyPeek'
    $fnReadKey = Resolve-DepOperationFn 'Read-ConsoleVirtualKeyConsume'
    if (-not (& $fnTestKey)) { return 'none' }

    $maxScroll = Get-ToolkitDepLogMaxScroll -Log $Log -ViewportRows $ViewportRows
    $peek = & $fnPeekKey
    if (-not $peek) { return 'none' }

    if (Test-ToolkitShellToolbarLocked -Shell $Shell) {
        if ($peek -eq 'Escape' -or $peek -eq 'Other' -or $peek -eq 'Enter') {
            $null = & $fnReadKey
            return 'none'
        }
    }
    elseif ($peek -eq 'Escape' -and $OnExitKey) {
        $vk = & $fnReadKey
        if ($vk -eq 'Escape') {
            & $OnExitKey
            return 'exit'
        }
        return 'none'
    }
    if ($peek -eq 'Other' -or $peek -eq 'Enter') { return 'none' }

    if ($peek -in @('UpArrow', 'DownArrow')) {
        if ($maxScroll -le 0) {
            $null = & $fnReadKey
            return 'none'
        }

        if ($ScrollState) {
            $now = [Environment]::TickCount
            $minInterval = if ($ScrollState.ContainsKey('MinScrollIntervalMs')) {
                [int]$ScrollState.MinScrollIntervalMs
            }
            else { 55 }
            $lastScroll = if ($ScrollState.ContainsKey('LastScrollTick')) {
                [int]$ScrollState.LastScrollTick
            }
            else { 0 }
            if (($now - $lastScroll) -lt $minInterval) { return 'none' }
            $ScrollState.LastScrollTick = $now
        }

        $vk = & $fnReadKey
        if ($vk -eq 'UpArrow' -and $Log.ScrollOffset -gt 0) {
            $Log.ScrollOffset--
            $Log.AutoScroll = $false
            return 'scroll'
        }
        if ($vk -eq 'DownArrow' -and $Log.ScrollOffset -lt $maxScroll) {
            $Log.ScrollOffset++
            $Log.AutoScroll = ($Log.ScrollOffset -ge $maxScroll)
            return 'scroll'
        }
        return 'none'
    }

    return 'none'
}

function Add-ToolkitDepLogSeparator {
    param($Log)

    if ($null -eq $Log) { return }
    Add-ToolkitDepLogLine -Log $Log -Text '' -Kind 'separator'
}

function Add-ToolkitDepLogSection {
    param(
        $Log,
        [string]$Title,
        [int]$Index = 0,
        [int]$Total = 0,
        [ValidateSet('package', 'tool')]
        [string]$Level = 'package'
    )

    if ($null -eq $Log) { return }

    $key = if ($Level -eq 'tool') { 'page.depOperation.logSectionTool' } else { 'page.depOperation.logSectionPackage' }
    $vars = @{ name = $Title }
    if ($Total -gt 0) {
        $vars.index = $Index
        $vars.total = $Total
    }
    Add-ToolkitDepLogLine -Log $Log -Text (Get-I18n -Key $key -Vars $vars) -Kind 'section' -WithTimestamp
}

function Register-ToolkitDepRunnerItemResult {
    param(
        [hashtable]$RunnerState,
        [ValidateSet('success', 'failed')]
        [string]$Result
    )

    if ($Result -eq 'success') {
        $RunnerState.SuccessCount++
    }
    else {
        $RunnerState.FailedCount++
    }
}

function Format-ToolkitDepBatchCountsText {
    param(
        [ValidateSet('install', 'update', 'uninstall', 'init', 'configure')]
        [string]$Intent = 'install',
        [int]$TotalCount = 0,
        [int]$SuccessCount,
        [int]$FailedCount
    )

    if ($TotalCount -le 0) { $TotalCount = $SuccessCount + $FailedCount }
    if ($TotalCount -le 0) { return '' }

    return (Get-I18n -Key 'page.depOperation.summaryBatchCounts' -Vars @{
        total   = [string]$TotalCount
        success = [string]$SuccessCount
        failed  = [string]$FailedCount
    })
}

function Format-ToolkitDepBatchCountSlot {
    param([int]$Value)

    return ('{0,2}' -f [Math]::Max(0, $Value))
}

function Get-ToolkitDepBatchSummarySegments {
    param(
        [ValidateSet('install', 'update', 'uninstall', 'init', 'configure')]
        [string]$Intent,
        [int]$TotalCount,
        [int]$SuccessCount,
        [int]$FailedCount
    )

    if ($TotalCount -le 0) { $TotalCount = $SuccessCount + $FailedCount }
    if ($TotalCount -le 0) { return @() }

    $sep = Get-I18n -Key 'page.depOperation.summaryBatchSep'
    $totalSlot = Format-ToolkitDepBatchCountSlot -Value $TotalCount
    $successSlot = Format-ToolkitDepBatchCountSlot -Value $SuccessCount
    $failedSlot = Format-ToolkitDepBatchCountSlot -Value $FailedCount

    return @(
        @{ Text = (Get-I18n -Key 'page.depOperation.summaryDone'); Color = [System.ConsoleColor]::White }
        @{
            Text  = (Get-I18n -Key 'page.depOperation.summaryBatchTotal' -Vars @{ total = $totalSlot })
            Color = [System.ConsoleColor]::Cyan
        }
        @{ Text = $sep; Color = [System.ConsoleColor]::White }
        @{
            Text  = (Get-I18n -Key 'page.depOperation.summaryBatchSuccess' -Vars @{ success = $successSlot })
            Color = [System.ConsoleColor]::Green
        }
        @{ Text = $sep; Color = [System.ConsoleColor]::White }
        @{
            Text  = (Get-I18n -Key 'page.depOperation.summaryBatchFailed' -Vars @{ failed = $failedSlot })
            Color = [System.ConsoleColor]::Red
        }
    )
}

function Get-ToolkitDepCatalogRowWriteLimit {
    param(
        [hashtable]$Shell = $null,
        [int]$BrandInnerWidth = 0
    )

    $fnContentWidth = Get-Command Get-ToolkitShellLayoutLineWidth -ErrorAction SilentlyContinue
    if ($fnContentWidth) {
        $limit = & $fnContentWidth -Shell $Shell -BrandInnerWidth $BrandInnerWidth
        if ($limit -gt 0) { return $limit }
    }

    $fnLineWidth = Resolve-DepOperationFn 'Get-BrandSeparatorLineWidth'
    $inner = if ($BrandInnerWidth -gt 0) {
        & $fnLineWidth -BrandInnerWidth $BrandInnerWidth
    }
    else {
        24
    }
    return 1 + [Math]::Max(1, $inner)
}

function Complete-ToolkitDepCatalogRowPadding {
    param(
        [int]$Row,
        [int]$Used,
        [hashtable]$Shell = $null,
        [int]$BrandInnerWidth = 0
    )

    $limit = Get-ToolkitDepCatalogRowWriteLimit -Shell $Shell -BrandInnerWidth $BrandInnerWidth
    if ($Used -lt $limit) {
        Write-Host (' ' * ($limit - $Used)) -NoNewline
    }
    Set-ConsoleCursorAfterRowWrite -Row $Row
}

function Write-ToolkitDepContentFixedLine {
    param(
        [int]$Row,
        [string]$Text,
        [System.ConsoleColor]$Color = [System.ConsoleColor]::Gray,
        [hashtable]$Shell = $null,
        [int]$BrandInnerWidth = 0,
        [bool]$Disabled = $false
    )

    $fnBrandGuard = Get-Command Test-ToolkitShellBrandRowWriteBlocked -ErrorAction SilentlyContinue
    if ($fnBrandGuard -and (& $fnBrandGuard -Row $Row -Shell $Shell)) { return }

    $fnDisplayWidth = Resolve-DepOperationFn 'Get-DisplayWidth'
    $fnTruncate = Resolve-DepOperationFn 'Truncate-DisplayText'
    $limit = Get-ToolkitDepCatalogRowWriteLimit -Shell $Shell -BrandInnerWidth $BrandInnerWidth

    $foreground = if ($Disabled) { [System.ConsoleColor]::DarkGray } else { $Color }

    $textWidth = & $fnDisplayWidth $Text
    if ($textWidth -gt $limit) {
        $Text = & $fnTruncate $Text $limit
        $textWidth = & $fnDisplayWidth $Text
    }
    $padded = $Text + (' ' * ($limit - $textWidth))

    Prepare-ConsoleRowWrite -Row $Row
    try { [Console]::SetCursorPosition(0, $Row) } catch { return }

    Write-Host $padded -NoNewline -ForegroundColor $foreground
    Set-ConsoleCursorAfterRowWrite -Row $Row
}

function Write-ToolkitDepFixedLineSegments {
    param(
        [int]$Row,
        [array]$Segments,
        [switch]$LeadingSpace,
        [hashtable]$Shell = $null,
        [int]$BrandInnerWidth = 0
    )

    if ($null -eq $Segments -or $Segments.Count -eq 0) { return }

    $fnBrandGuard = Get-Command Test-ToolkitShellBrandRowWriteBlocked -ErrorAction SilentlyContinue
    if ($fnBrandGuard -and (& $fnBrandGuard -Row $Row -Shell $Shell)) { return }

    $fnDisplayWidth = Resolve-DepOperationFn 'Get-DisplayWidth'
    $fnTruncate = Resolve-DepOperationFn 'Truncate-DisplayText'
    $limit = Get-ToolkitDepCatalogRowWriteLimit -Shell $Shell -BrandInnerWidth $BrandInnerWidth
    $background = Get-ConsoleSurfaceBackground

    $drawSegments = New-Object 'System.Collections.Generic.List[object]'
    $used = 0
    if ($LeadingSpace -and $used -lt $limit) {
        [void]$drawSegments.Add(@{ Text = ' '; Color = [System.ConsoleColor]::Gray })
        $used++
    }

    foreach ($seg in $Segments) {
        if (-not $seg) { continue }
        if ($used -ge $limit) { break }
        $partWidth = & $fnDisplayWidth $seg.Text
        $remaining = $limit - $used
        $text = if ($partWidth -gt $remaining) { & $fnTruncate $seg.Text $remaining } else { $seg.Text }
        if ([string]::IsNullOrEmpty($text)) { break }
        [void]$drawSegments.Add(@{ Text = $text; Color = $seg.Color })
        $used += & $fnDisplayWidth $text
    }

    if ($used -lt $limit) {
        [void]$drawSegments.Add(@{ Text = (' ' * ($limit - $used)); Color = [System.ConsoleColor]::Gray })
    }

    Prepare-ConsoleRowWrite -Row $Row
    try { [Console]::SetCursorPosition(0, $Row) } catch { return }

    $used = 0
    if ($LeadingSpace -and $used -lt $limit) {
        Write-Host ' ' -NoNewline
        $used++
    }

    foreach ($seg in $drawSegments) {
        if (-not $seg -or [string]::IsNullOrEmpty([string]$seg.Text)) { continue }
        Write-Host ([string]$seg.Text) -NoNewline -ForegroundColor $seg.Color
    }

    Set-ConsoleCursorAfterRowWrite -Row $Row
}

function Format-ToolkitDepLogLineText {
    param(
        $Line,
        [int]$TimeWidth = $script:ToolkitDepLogTimeWidth,
        [int]$BrandInnerWidth = 0
    )

    if ($Line.Kind -eq 'separator') {
        if ($BrandInnerWidth -gt 0) {
            $fnFormatSep = Resolve-DepOperationFn 'Format-ToolkitShellLayoutSeparator'
            return & $fnFormatSep -BrandInnerWidth $BrandInnerWidth
        }
        return [string]$Line.Text
    }
    if ($Line.Kind -in @('hint', 'spacer')) {
        $gap = ' '
        $timePart = if ([string]::IsNullOrWhiteSpace([string]$Line.Timestamp)) {
            ''.PadRight($TimeWidth)
        }
        else {
            ([string]$Line.Timestamp).PadRight($TimeWidth)
        }
        return "$timePart$gap$([string]$Line.Text)"
    }

    $gap = ' '
    $timePart = [string]$Line.Timestamp
    if ([string]::IsNullOrWhiteSpace($timePart)) {
        $timePart = ''.PadRight($TimeWidth)
    }
    else {
        $timePart = $timePart.PadRight($TimeWidth)
    }

    return "$timePart$gap$([string]$Line.Text)"
}

function Resolve-DepOperationProgressDisplay {
    param(
        [int]$ProgressCurrent,
        [int]$ProgressTotal,
        [bool]$ItemInFlight,
        [int]$ItemSubPercent
    )

    if ($ProgressTotal -le 0) { $ProgressTotal = 1 }
    if ($ProgressCurrent -lt 0) { $ProgressCurrent = 0 }

    $subFraction = 0.0
    if ($ItemSubPercent -ge 0 -and $ItemSubPercent -le 100) {
        $subFraction = $ItemSubPercent / 100.0
    }

    $index = 1
    $percent = 0

    if ($ProgressCurrent -ge $ProgressTotal) {
        $index = $ProgressTotal
        $percent = 100
    }
    else {
        if ($ItemInFlight -or $subFraction -gt 0) {
            $index = [Math]::Max(1, $ProgressCurrent + 1)
        }
        else {
            $index = [Math]::Max(1, [Math]::Min($ProgressTotal, $ProgressCurrent))
        }

        $effectiveItems = [double]$ProgressCurrent
        if ($ItemInFlight -or $subFraction -gt 0) {
            $effectiveItems += $subFraction
        }
        $percent = [int][Math]::Min(100, [Math]::Floor(($effectiveItems / [double]$ProgressTotal) * 100.0))
    }

    if ($index -gt $ProgressTotal) { $index = $ProgressTotal }
    if ($index -lt 1) { $index = 1 }

    return @{
        ItemIndex      = $index
        ItemSubPercent = $percent
    }
}

function Write-ToolkitDepOperationSplitStatusSegments {
    param(
        [int]$Row,
        [array]$Segments,
        [string]$RightText = '',
        [int]$BrandInnerWidth = 0,
        [hashtable]$Shell = $null,
        [switch]$LeadingSpace
    )

    if ($null -eq $Segments -or $Segments.Count -eq 0) { return }

    $fnBrandGuard = Get-Command Test-ToolkitShellBrandRowWriteBlocked -ErrorAction SilentlyContinue
    if ($fnBrandGuard -and (& $fnBrandGuard -Row $Row -Shell $Shell)) { return }

    $fnLineWidth = Resolve-DepOperationFn 'Get-BrandSeparatorLineWidth'
    $fnDisplayWidth = Resolve-DepOperationFn 'Get-DisplayWidth'

    $inner = if ($BrandInnerWidth -gt 0) {
        & $fnLineWidth -BrandInnerWidth $BrandInnerWidth
    }
    else {
        24
    }
    $limit = Get-ToolkitDepCatalogRowWriteLimit -Shell $Shell -BrandInnerWidth $BrandInnerWidth
    $background = Get-ConsoleSurfaceBackground

    $drawSegments = New-Object 'System.Collections.Generic.List[object]'
    $used = 0
    if ($LeadingSpace -and $used -lt $limit) {
        [void]$drawSegments.Add(@{ Text = ' '; Color = [System.ConsoleColor]::Gray })
        $used++
    }

    $right = [string]$RightText
    $rightWidth = if ([string]::IsNullOrEmpty($right)) { 0 } else { & $fnDisplayWidth $right }
    $gap = if ($rightWidth -gt 0) { 1 } else { 0 }
    $mainMax = [Math]::Max(1, $inner - $rightWidth - $gap)

    $mainUsed = 0
    foreach ($seg in $Segments) {
        if (-not $seg) { continue }
        if ($mainUsed -ge $mainMax) { break }
        $remaining = $mainMax - $mainUsed
        $partWidth = & $fnDisplayWidth $seg.Text
        $text = if ($partWidth -gt $remaining) {
            Truncate-DisplayTextEllipsis -Text $seg.Text -MaxWidth $remaining
        }
        else {
            $seg.Text
        }
        if ([string]::IsNullOrEmpty($text)) { break }
        [void]$drawSegments.Add(@{ Text = $text; Color = $seg.Color })
        $mainUsed += & $fnDisplayWidth $text
    }

    $used += $mainUsed
    if ($rightWidth -gt 0) {
        $pad = $inner - $mainUsed - $rightWidth
        if ($pad -lt $gap) { $pad = $gap }
        if ($pad -gt 0 -and ($used + $pad) -le $limit) {
            [void]$drawSegments.Add(@{ Text = (' ' * $pad); Color = [System.ConsoleColor]::Gray })
            $used += $pad
        }
        if (($used + $rightWidth) -le $limit) {
            [void]$drawSegments.Add(@{ Text = $right; Color = [System.ConsoleColor]::DarkGray })
            $used += $rightWidth
        }
    }

    if ($used -lt $limit) {
        [void]$drawSegments.Add(@{ Text = (' ' * ($limit - $used)); Color = [System.ConsoleColor]::Gray })
    }

    Prepare-ConsoleRowWrite -Row $Row
    try { [Console]::SetCursorPosition(0, $Row) } catch { return }

    foreach ($seg in $drawSegments) {
        if (-not $seg -or [string]::IsNullOrEmpty([string]$seg.Text)) { continue }
        Write-Host ([string]$seg.Text) -NoNewline -ForegroundColor $seg.Color
    }

    Set-ConsoleCursorAfterRowWrite -Row $Row
}

function Truncate-DisplayTextEllipsis {
    param(
        [string]$Text,
        [int]$MaxWidth
    )

    $fnDisplayWidth = Resolve-DepOperationFn 'Get-DisplayWidth'
    $fnTruncate = Resolve-DepOperationFn 'Truncate-DisplayText'

    if ($MaxWidth -le 0) { return '' }
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    if ((& $fnDisplayWidth $Text) -le $MaxWidth) { return $Text }
    if ($MaxWidth -le 3) { return & $fnTruncate '...' $MaxWidth }

    $body = & $fnTruncate $Text ($MaxWidth - 3)
    return "$body..."
}

function Write-ToolkitDepOperationSplitStatusLine {
    param(
        [int]$Row,
        [string]$MainText,
        [string]$RightText = '',
        [int]$BrandInnerWidth = 0,
        [hashtable]$Shell = $null,
        [switch]$LeadingSpace,
        [System.ConsoleColor]$MainColor = [System.ConsoleColor]::White,
        [System.ConsoleColor]$RightColor = [System.ConsoleColor]::DarkGray
    )

    $fnLineWidth = Resolve-DepOperationFn 'Get-BrandSeparatorLineWidth'
    $fnDisplayWidth = Resolve-DepOperationFn 'Get-DisplayWidth'

    $inner = if ($BrandInnerWidth -gt 0) {
        & $fnLineWidth -BrandInnerWidth $BrandInnerWidth
    }
    else {
        24
    }

    $right = [string]$RightText
    $rightWidth = if ([string]::IsNullOrEmpty($right)) { 0 } else { & $fnDisplayWidth $right }
    $gap = if ($rightWidth -gt 0) { 1 } else { 0 }
    $mainMax = [Math]::Max(1, $inner - $rightWidth - $gap)
    $main = [string]$MainText
    if ((& $fnDisplayWidth $main) -gt $mainMax) {
        $main = Truncate-DisplayTextEllipsis -Text $main -MaxWidth $mainMax
    }

    Write-ToolkitDepOperationSplitStatusSegments -Row $Row `
        -Segments @(@{ Text = $main; Color = $MainColor }) `
        -RightText $right -BrandInnerWidth $BrandInnerWidth -Shell $Shell -LeadingSpace:$LeadingSpace
}

function Format-ToolkitDepOperationStatusLine {
    param(
        [string]$Text,
        [int]$BrandInnerWidth = 0,
        [int]$RightReserve = 1
    )

    $fnLineWidth = Resolve-DepOperationFn 'Get-BrandSeparatorLineWidth'
    $fnPad = Resolve-DepOperationFn 'Pad-DisplayText'
    $fnTruncate = Resolve-DepOperationFn 'Truncate-DisplayText'
    $fnDisplayWidth = Resolve-DepOperationFn 'Get-DisplayWidth'

    $inner = if ($BrandInnerWidth -gt 0) {
        & $fnLineWidth -BrandInnerWidth $BrandInnerWidth
    }
    else {
        24
    }
    $maxWidth = [Math]::Max(1, $inner - $RightReserve)
    $text = [string]$Text

    if ([string]::IsNullOrWhiteSpace($text)) {
        return & $fnPad '' $maxWidth
    }

    $candidates = New-Object 'System.Collections.Generic.List[string]'
    $candidates.Add($text) | Out-Null

    $withoutElapsed = $text
    if ($text -match '^(.*?)（\d+s）\s*$') {
        $withoutElapsed = $Matches[1].TrimEnd()
        $candidates.Add($withoutElapsed) | Out-Null
    }

    $withoutPercent = $withoutElapsed
    if ($withoutElapsed -match '^(.*?\S)\s+\d+%\s*$') {
        $withoutPercent = $Matches[1].TrimEnd()
        $candidates.Add($withoutPercent) | Out-Null
    }

    if ($withoutElapsed -ne $text -and $withoutPercent -ne $withoutElapsed) {
        $both = $withoutPercent
        if ($both -match '^(.*?)（\d+s）\s*$') {
            $both = $Matches[1].TrimEnd()
        }
        $candidates.Add($both) | Out-Null
    }

    $seen = @{}
    foreach ($candidate in $candidates) {
        if ($seen[$candidate]) { continue }
        $seen[$candidate] = $true
        if ((& $fnDisplayWidth $candidate) -le $maxWidth) {
            return & $fnPad $candidate $maxWidth
        }
    }

    return & $fnPad (& $fnTruncate $text $maxWidth) $maxWidth
}

function Format-ToolkitDepProgressPercentSlot {
    param([int]$Percent)

    $clamped = [Math]::Max(0, [Math]::Min(100, $Percent))
    return ('{0,3}%' -f $clamped)
}

function Test-ToolkitDepProgressShowCountSlot {
    param([int]$Total)

    if ($Total -le 0) { $Total = 1 }
    return ($Total -gt 1)
}

function Format-ToolkitDepProgressCountSlot {
    param(
        [int]$Index,
        [int]$Total
    )

    if ($Total -le 0) { $Total = 1 }
    if ($Index -lt 0) { $Index = 0 }

    return ('{0,2}/{1,2}' -f $Index, $Total)
}

function Get-ToolkitDepProgressCountSlotReservedWidth {
    $fnDisplayWidth = Resolve-DepOperationFn 'Get-DisplayWidth'
    return & $fnDisplayWidth (Format-ToolkitDepProgressCountSlot -Index 99 -Total 99)
}

function Get-ToolkitDepProgressBarSuffixReservedWidth {
    param(
        [switch]$IncludeCount,
        [int]$Total = 2
    )

    $fnDisplayWidth = Resolve-DepOperationFn 'Get-DisplayWidth'
    $percentReserved = Format-ToolkitDepProgressPercentSlot -Percent 100
    if ($IncludeCount -and (Test-ToolkitDepProgressShowCountSlot -Total $Total)) {
        $countReserved = Format-ToolkitDepProgressCountSlot -Index 99 -Total 99
        return & $fnDisplayWidth " $percentReserved $countReserved"
    }

    return & $fnDisplayWidth " $percentReserved"
}

function Format-ToolkitDepProgressBar {
    param(
        [int]$Current = 0,
        [int]$Total = 1,
        [string]$Name = '',
        [int]$BrandInnerWidth = 0,
        [int]$ItemSubPercent = -1,
        [int]$LoadingPercent = -1,
        [int]$ItemIndex = 0
    )

    if ($Total -le 0) { $Total = 1 }
    if ($Current -lt 0) { $Current = 0 }
    if ($Current -gt $Total) { $Current = $Total }

    $fnLineWidth = Resolve-DepOperationFn 'Get-BrandSeparatorLineWidth'
    $fnPad = Resolve-DepOperationFn 'Pad-DisplayText'
    $fnTruncate = Resolve-DepOperationFn 'Truncate-DisplayText'
    $fnDisplayWidth = Resolve-DepOperationFn 'Get-DisplayWidth'

    $inner = if ($BrandInnerWidth -gt 0) {
        & $fnLineWidth -BrandInnerWidth $BrandInnerWidth
    }
    else {
        24
    }

    $rightReserve = 0
    $contentMax = [Math]::Max(1, $inner - $rightReserve)

    $useLoadingPercent = ($LoadingPercent -ge 0 -and $LoadingPercent -le 100)
    $useItemProgress = (-not $useLoadingPercent -and $ItemIndex -gt 0)

    if ($useLoadingPercent) {
        $ratio = $LoadingPercent / 100.0
        $percentSlot = Format-ToolkitDepProgressPercentSlot -Percent $LoadingPercent
        $suffix = " $percentSlot"
        $suffixWidth = Get-ToolkitDepProgressBarSuffixReservedWidth
        $barInner = [Math]::Max(1, $contentMax - 2 - $suffixWidth)
        $filled = [Math]::Min($barInner, [int][Math]::Round($ratio * $barInner))
        $bar = ('#' * $filled) + ('-' * [Math]::Max(0, $barInner - $filled))
        $content = & $fnPad "[$bar]$suffix" $contentMax
        return ' ' + $content
    }
    elseif ($useItemProgress) {
        $percent = if ($ItemSubPercent -ge 0 -and $ItemSubPercent -le 100) { $ItemSubPercent } else { 0 }
        $ratio = $percent / 100.0
        $percentSlot = Format-ToolkitDepProgressPercentSlot -Percent $percent
        if (Test-ToolkitDepProgressShowCountSlot -Total $Total) {
            $countSlot = Format-ToolkitDepProgressCountSlot -Index $ItemIndex -Total $Total
            $suffix = " $percentSlot $countSlot"
            $suffixWidth = Get-ToolkitDepProgressBarSuffixReservedWidth -IncludeCount -Total $Total
        }
        else {
            $suffix = " $percentSlot"
            $suffixWidth = Get-ToolkitDepProgressBarSuffixReservedWidth -Total $Total
        }
        $barInner = [Math]::Max(1, $contentMax - 2 - $suffixWidth)
    }
    else {
        $effective = [double]$Current
        if ($ItemSubPercent -ge 0 -and $ItemSubPercent -le 100 -and $Current -lt $Total) {
            $effective = $Current + ($ItemSubPercent / 100.0)
        }

        $ratio = [Math]::Min(1.0, [Math]::Max(0.0, $effective / [double]$Total))

        if (Test-ToolkitDepProgressShowCountSlot -Total $Total) {
            $countText = "$Current/$Total"
            $suffix = " $countText  $Name"
        }
        else {
            $percent = [int][Math]::Min(100, [Math]::Floor($ratio * 100.0))
            $percentSlot = Format-ToolkitDepProgressPercentSlot -Percent $percent
            if ([string]::IsNullOrWhiteSpace($Name)) {
                $suffix = " $percentSlot"
            }
            else {
                $suffix = " $percentSlot  $Name"
            }
            $countText = ''
        }
    }

    if (-not $useItemProgress) {
        $suffixWidth = & $fnDisplayWidth $suffix
        $barInner = $contentMax - 2 - $suffixWidth
        if ($barInner -lt 1 -and (Test-ToolkitDepProgressShowCountSlot -Total $Total)) {
            $fixedPart = " $countText  "
            $fixedWidth = 2 + (& $fnDisplayWidth $fixedPart)
            $nameMax = [Math]::Max(1, $contentMax - $fixedWidth - 2)
            $suffix = "$fixedPart$(& $fnTruncate $Name $nameMax)"
            $suffixWidth = & $fnDisplayWidth $suffix
            $barInner = [Math]::Max(1, $contentMax - 2 - $suffixWidth)
        }
        elseif ($barInner -lt 1) {
            $barInner = [Math]::Max(1, $contentMax - 2 - $suffixWidth)
        }
    }

    $filled = [Math]::Min($barInner, [int][Math]::Round($ratio * $barInner))
    $bar = ('#' * $filled) + ('-' * [Math]::Max(0, $barInner - $filled))
    $content = & $fnPad "[$bar]$suffix" $contentMax
    return ' ' + $content
}

function Get-ToolkitDepWingetOutputDecision {
    param(
        [string]$Line,
        [hashtable]$OutputState
    )

    $fnGetI18n = Resolve-DepOperationFn 'Get-I18n'
    $fnCleanLine = Resolve-DepOperationFn 'Get-WingetStreamLineCleanText'
    $trim = & $fnCleanLine -Line $Line
    $decision = @{
        LogText        = $null
        StatusText     = $trim
        Percent        = -1
        RedrawOnly     = $false
        ProgressPhase  = $null
    }

    if ([string]::IsNullOrWhiteSpace($trim)) {
        $decision.RedrawOnly = $true
        return $decision
    }

    $fnGetPercent = Resolve-DepOperationFn 'Get-WingetDepStreamLinePercent'
    $fnGetPhase = Resolve-DepOperationFn 'Get-WingetDepStreamLinePhase'
    $fnIsProgressVisual = Resolve-DepOperationFn 'Test-WingetDepStreamLineIsProgressVisual'
    $percent = & $fnGetPercent -Line $trim
    $phase = & $fnGetPhase -Line $trim
    $decision.Percent = $percent
    $isProgressVisual = & $fnIsProgressVisual -Line $trim

    if ($isProgressVisual) {
        $decision.StatusText = $null
    }

    if ($phase -eq 'spinner') {
        $decision.RedrawOnly = $true
        $decision.StatusText = $null
        return $decision
    }

    if ($trim -match '已成功验证|Successfully verified') {
        if (-not $OutputState.LoggedPhases.ContainsKey('verifyComplete')) {
            $OutputState.LoggedPhases['verifyComplete'] = $true
            $decision.LogText = & $fnGetI18n -Key 'page.depOperation.logVerifyComplete'
        }
        $OutputState.PercentStage = 'install'
        $decision.ProgressPhase = 'verifyComplete'
        return $decision
    }

    $phaseOnce = @('found', 'startInstall', 'startUninstall', 'waitOther', 'download', 'verify', 'install', 'uninstall', 'installerPackage')
    if ($phase -in $phaseOnce -and -not $OutputState.LoggedPhases.ContainsKey($phase)) {
        if (Test-ToolkitDepShouldSuppressWingetStalePhaseLog -OutputState $OutputState -Phase $phase) {
            $decision.RedrawOnly = $true
            return $decision
        }
        if (Test-ToolkitDepShouldSuppressWingetDownloadLog -OutputState $OutputState -Phase $phase) {
            $decision.RedrawOnly = $true
            $decision.StatusText = Get-ToolkitDepWingetPromptStatusText -OutputState $OutputState -GetI18n $fnGetI18n
            return $decision
        }

        $OutputState.LoggedPhases[$phase] = $true
        $decision.ProgressPhase = $phase
        Update-ToolkitDepWingetMaxPhaseRank -OutputState $OutputState -Rank (Get-ToolkitDepWingetPhaseRank -Phase $phase)
        switch ($phase) {
            'found' {
                $decision.LogText = Resolve-ToolkitDepWingetFoundLogText -Line $trim -OutputState $OutputState -GetI18n $fnGetI18n
            }
            'startInstall' {
                if ([bool]$OutputState['WingetInstallSilent']) {
                    Complete-ToolkitDepInstallerPromptPhase -OutputState $OutputState
                    $null = Add-ToolkitDepExecutePackageLogIfDue -OutputState $OutputState -Decision $decision -GetI18n $fnGetI18n
                }
                else {
                    $decision.RedrawOnly = $true
                }
            }
            'startUninstall' {
                if ([bool]$OutputState['InstallerPromptDismissed']) {
                    if (Add-ToolkitDepExecutePackageLogIfDue -OutputState $OutputState -Decision $decision -GetI18n $fnGetI18n) {
                        if (-not [string]::IsNullOrWhiteSpace([string]$decision.LogText)) {
                            $pending = if ($decision.PendingLogTexts) { @($decision.PendingLogTexts) } else { @() }
                            $decision.PendingLogTexts = @(@([string]$decision.LogText) + @($pending))
                            $decision.LogText = $null
                        }
                    }
                }
                $decision.RedrawOnly = $true
            }
            'waitOther' {
                $decision.LogText = & $fnGetI18n -Key 'page.depOperation.logWaitOther'
            }
            'download' {
                $OutputState.PercentStage = 'download'
                $decision.LogText = & $fnGetI18n -Key 'page.depOperation.logDownloading'
            }
            'verify' {
                $OutputState.PercentStage = 'verify'
                $decision.LogText = & $fnGetI18n -Key 'page.depOperation.logVerifying'
            }
            'install' {
                $wasAwaitingUser = Test-ToolkitDepWingetOutputAwaitingUser -OutputState $OutputState
                if (-not [bool]$OutputState['WingetInstallSilent']) {
                    if (-not $wasAwaitingUser -and -not [bool]$OutputState['InstallerPromptDismissed']) {
                        Enter-ToolkitDepWingetInteractivePromptPhase -OutputState $OutputState -Decision $decision `
                            -GetI18n $fnGetI18n -PromptLogKey 'page.depOperation.logInstallerLaunched'
                    }
                    elseif ($wasAwaitingUser) {
                        Complete-ToolkitDepInstallerPromptPhase -OutputState $OutputState
                        $null = Add-ToolkitDepExecutePackageLogIfDue -OutputState $OutputState -Decision $decision -GetI18n $fnGetI18n
                    }
                }
                elseif (-not $OutputState['InstallerAwaitingDialog']) {
                    Complete-ToolkitDepInstallerPromptPhase -OutputState $OutputState
                    $null = Add-ToolkitDepExecutePackageLogIfDue -OutputState $OutputState -Decision $decision -GetI18n $fnGetI18n
                }
                $OutputState.PercentStage = 'install'
                $installingText = & $fnGetI18n -Key 'page.depOperation.logInstalling'
                if ([string]::IsNullOrWhiteSpace([string]$decision.LogText)) {
                    $decision.LogText = $installingText
                }
                elseif ([string]$decision.LogText -ne $installingText) {
                    $pending = if ($decision.PendingLogTexts) { @($decision.PendingLogTexts) } else { @() }
                    $decision.PendingLogTexts = @($pending + @($installingText))
                }
            }
            'uninstall' {
                $wasAwaitingUser = Test-ToolkitDepWingetOutputAwaitingUser -OutputState $OutputState
                if ($wasAwaitingUser) {
                    Complete-ToolkitDepInstallerPromptPhase -OutputState $OutputState
                    $null = Add-ToolkitDepExecutePackageLogIfDue -OutputState $OutputState -Decision $decision -GetI18n $fnGetI18n
                }
                elseif (-not $OutputState.LoggedPhases.ContainsKey('executePackage')) {
                    $null = Add-ToolkitDepExecutePackageLogIfDue -OutputState $OutputState -Decision $decision -GetI18n $fnGetI18n
                }
                Update-ToolkitDepWingetMaxPhaseRank -OutputState $OutputState -Rank 60
                $OutputState.PercentStage = 'uninstall'
                $uninstallingText = & $fnGetI18n -Key 'page.depOperation.logUninstalling'
                if ([string]::IsNullOrWhiteSpace([string]$decision.LogText)) {
                    $decision.LogText = $uninstallingText
                }
                elseif ([string]$decision.LogText -ne $uninstallingText) {
                    $pending = if ($decision.PendingLogTexts) { @($decision.PendingLogTexts) } else { @() }
                    $decision.PendingLogTexts = @($pending + @($uninstallingText))
                }
            }
            'installerPackage' {
                $executeAction = [string]$OutputState['ExecuteAction']
                if ($executeAction -eq 'Uninstall') {
                    Enter-ToolkitDepWingetInteractivePromptPhase -OutputState $OutputState -Decision $decision `
                        -GetI18n $fnGetI18n -PromptLogKey 'page.depOperation.logUninstallPrompt'
                    $OutputState.PercentStage = 'uninstall'
                    $decision.ProgressPhase = 'installerPackageInteractive'
                }
                else {
                    if (-not [bool]$OutputState['WingetInstallSilent']) {
                        Enter-ToolkitDepWingetInteractivePromptPhase -OutputState $OutputState -Decision $decision `
                            -GetI18n $fnGetI18n -PromptLogKey 'page.depOperation.logInstallerLaunched'
                    }
                    $OutputState.PercentStage = 'install'
                    $decision.ProgressPhase = 'installerPackageInteractive'
                    if (-not $decision.LogText -and -not $OutputState.LoggedPhases.ContainsKey('installerPackageLogged')) {
                        $OutputState.LoggedPhases['installerPackageLogged'] = $true
                        $decision.LogText = & $fnGetI18n -Key 'page.depOperation.logInstallerLaunched'
                    }
                }
            }
            default {
                if ($phase -ne 'found') {
                    $decision.LogText = $trim
                }
            }
        }
    }

    if ($percent -ge 0) {
        $transferStatus = Format-WingetDepStreamLineTransferStatus -Line $Line
        if ($transferStatus) {
            if ([string]::IsNullOrWhiteSpace([string]$OutputState.PercentStage)) {
                $OutputState.PercentStage = 'download'
            }
            $decision.RedrawOnly = $true
            $decision.StatusText = $transferStatus
            return $decision
        }

        if (Test-ToolkitDepWingetOutputAwaitingUser -OutputState $OutputState) {
            $decision.RedrawOnly = $true
            $decision.StatusText = Get-ToolkitDepWingetPromptStatusText -OutputState $OutputState -GetI18n $fnGetI18n
            return $decision
        }
        if ($isProgressVisual) {
            $decision.RedrawOnly = $true
            if (($OutputState.LastLoggedPercent -lt 0) -or (($percent - $OutputState.LastLoggedPercent) -ge 5)) {
                $OutputState.LastLoggedPercent = $percent
            }
            $decision.StatusText = & $fnGetI18n -Key 'page.depOperation.statusDownload' -Vars @{ percent = $percent }
            return $decision
        }
        if ([string]::IsNullOrWhiteSpace([string]$OutputState.PercentStage)) {
            $OutputState.PercentStage = 'download'
        }

        $milestone = ($OutputState.LastLoggedPercent -lt 0) -or ($percent -eq 100) `
            -or (($percent - $OutputState.LastLoggedPercent) -ge 10)
        if ($milestone -and -not $decision.LogText) {
            $OutputState.LastLoggedPercent = $percent
            $stage = [string]$OutputState.PercentStage
            if ($percent -eq 100) {
                if ($stage -eq 'install') {
                    if (-not $OutputState.LoggedInstallComplete) {
                        $decision.LogText = & $fnGetI18n -Key 'page.depOperation.logInstallComplete'
                        $OutputState.LoggedInstallComplete = $true
                    }
                }
                elseif (-not $OutputState.LoggedDownloadComplete) {
                    $decision.LogText = & $fnGetI18n -Key 'page.depOperation.logDownloadComplete'
                    $OutputState.LoggedDownloadComplete = $true
                    $OutputState.PercentStage = 'install'
                }
            }
            elseif ($stage -eq 'install') {
                $decision.LogText = & $fnGetI18n -Key 'page.depOperation.logInstallPercent' -Vars @{ percent = $percent }
            }
            else {
                $decision.LogText = & $fnGetI18n -Key 'page.depOperation.logDownloadPercent' -Vars @{ percent = $percent }
            }
        }
        elseif ($milestone) {
            $OutputState.LastLoggedPercent = $percent
        }

        if ($percent -eq 100 -and $OutputState.LoggedDownloadComplete -and -not $OutputState.LoggedInstallComplete) {
            $decision.StatusText = & $fnGetI18n -Key 'page.depOperation.statusDownloadComplete'
        }
        else {
            $decision.StatusText = & $fnGetI18n -Key 'page.depOperation.statusDownload' -Vars @{ percent = $percent }
        }
    }
    elseif ($phase -eq 'result') {
        if ($trim -match '已成功安装|Successfully installed|已成功卸载|Successfully uninstalled|卸载成功') {
            $decision.ProgressPhase = 'wingetSuccess'
            $OutputState['WingetOperationSucceeded'] = $true
        }
        $decision.LogText = $trim
    }
    elseif ($phase -eq 'info' -and -not $decision.LogText -and -not $isProgressVisual) {
        if (Test-ToolkitDepShouldSuppressWingetStalePhaseLog -OutputState $OutputState -Phase $phase) {
            $decision.RedrawOnly = $true
            return $decision
        }
        if (Test-ToolkitDepShouldSuppressWingetDownloadLog -OutputState $OutputState -Phase $phase) {
            $decision.RedrawOnly = $true
            $decision.StatusText = Get-ToolkitDepWingetPromptStatusText -OutputState $OutputState -GetI18n $fnGetI18n
            return $decision
        }
        if ($trim -match '(?i)^https?://') {
            if (-not $OutputState.LoggedPhases.ContainsKey('downloadUrlSummary')) {
                $OutputState.LoggedPhases['downloadUrlSummary'] = $true
                $decision.LogText = & $fnGetI18n -Key 'page.depOperation.logDownloading'
            }
            else {
                $decision.RedrawOnly = $true
            }
            return $decision
        }
        if ($trim -match '(?i)^Starting package uninstall\b') {
            $decision.RedrawOnly = $true
            return $decision
        }
        if ($trim -match '(?i)^Starting package install\b') {
            $decision.RedrawOnly = $true
            return $decision
        }
        $fnTestZhPhrase = Resolve-DepOperationFn 'Test-WingetDepZhStreamPhrase'
        if ((& $fnTestZhPhrase $trim 'startUninstall') -or (& $fnTestZhPhrase $trim 'startInstall')) {
            $decision.RedrawOnly = $true
            return $decision
        }
        $decision.LogText = $trim
    }
    elseif ($phase -eq 'progress' -and -not $decision.LogText) {
        $decision.RedrawOnly = $true
        if ($percent -lt 0) {
            $decision.StatusText = $null
        }
    }
    elseif ($decision.LogText) {
        $decision.StatusText = [string]$decision.LogText
    }
    elseif ($isProgressVisual) {
        $decision.RedrawOnly = $true
        $decision.StatusText = $null
    }

    return $decision
}

function Get-ToolkitDepStatusText {
    param(
        $PlanItem,
        [string]$Phase,
        [string]$Command = ''
    )

    $name = [string]$PlanItem.Status.Name
    $action = Get-ToolkitDepActionLabel -Action ([string]$PlanItem.Status.Action)

    switch ($Phase) {
        'detect' { return (Get-I18n -Key 'page.depOperation.statusDetect' -Vars @{ name = $name }) }
        'preflight' { return (Get-I18n -Key 'page.depOperation.statusPreflight' -Vars @{ name = $name }) }
        'skip' { return (Get-I18n -Key 'page.depOperation.statusSkip' -Vars @{ name = $name }) }
        'reconcile' { return (Get-I18n -Key 'page.depOperation.statusReconcile' -Vars @{ name = $name }) }
        'run' {
            return (Get-I18n -Key 'page.depOperation.statusAction' -Vars @{ name = $name; action = $action })
        }
        'done' { return (Get-I18n -Key 'page.depOperation.statusDone' -Vars @{ name = $name }) }
        'fail' { return (Get-I18n -Key 'page.depOperation.statusFail' -Vars @{ name = $name }) }
        'stall' {
            return (Get-I18n -Key 'page.depOperation.statusStallWarn')
        }
        'download' {
            return (Get-I18n -Key 'page.depOperation.statusDownload' -Vars @{
                percent = [string]$Command
            })
        }
    }
    return $name
}

function Get-ToolkitDepVersionLabel {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return '-' }
    return [string]$Value
}

function Get-ToolkitDepPolicyLabel {
    param([string]$Policy)

    if ([string]::IsNullOrWhiteSpace($Policy)) { return '-' }

    $normalized = $Policy.Trim().ToLowerInvariant()
    if ($normalized -eq 'latest') {
        return Get-I18n -Key 'page.depOperation.policy.latest'
    }

    return [string]$Policy
}

function Get-ToolkitDepActionLabel {
    param([string]$Action)

    if ([string]::IsNullOrWhiteSpace($Action)) { return '-' }

    $key = "page.depOperation.action.$Action"
    $label = Get-I18nRaw -Key $key
    if (-not [string]::IsNullOrWhiteSpace($label)) {
        return $label
    }

    return [string]$Action
}

function Get-ToolkitDepDeclineLogText {
    param(
        [ValidateSet('uac', 'user')]
        [string]$DeclineKind,
        [string]$ExecuteAction
    )

    $action = [string]$ExecuteAction
    if ($action -notin @('Install', 'Upgrade', 'Repair', 'Uninstall')) {
        $action = 'Install'
    }

    $baseKey = if ($DeclineKind -eq 'uac') { 'logUacDeclined' } else { 'logInstallerDeclined' }
    $key = "page.depOperation.$baseKey.$action"
    $text = Get-I18nRaw -Key $key
    if (-not [string]::IsNullOrWhiteSpace($text)) {
        return $text
    }

    return (Get-I18n -Key "page.depOperation.$baseKey.Install")
}

function Get-ToolkitDepInstalledVersionLabel {
    param(
        $Status,
        [string]$DetectedVersion
    )

    if (-not [string]::IsNullOrWhiteSpace([string]$Status.ActualVersion)) {
        return Get-ToolkitDepVersionLabel -Value ([string]$Status.ActualVersion)
    }
    if ($Status.CommandAvailable -and -not [string]::IsNullOrWhiteSpace($DetectedVersion)) {
        return Get-ToolkitDepVersionLabel -Value $DetectedVersion
    }

    return '-'
}

function Write-ToolkitDepPlanDetectLog {
    param(
        $Log,
        $PlanItem
    )

    $status = $PlanItem.Status
    $name = [string]$status.Name
    Add-ToolkitDepLogLine -Log $Log -Text (Get-I18n -Key 'page.depOperation.logDetect' -Vars @{ name = $name }) -WithTimestamp

    if ($status.VersionDrift) {
        Add-ToolkitDepLogLine -Log $Log -Text (Get-I18n -Key 'page.depOperation.logVersionDrift' -Vars @{
            recorded = [string]$status.RecordedVersion
            actual   = [string]$status.ActualVersion
        }) -Kind 'heading' -WithTimestamp
    }

    $detectedVersion = & (Resolve-DepOperationFn 'Resolve-ToolDepCheckCommandVersion') `
        -CheckCommand ([string]$status.CheckCommand)

    $hasRecord = -not [string]::IsNullOrWhiteSpace([string]$status.RecordedVersion)
    $isInstalled = [bool]$status.CommandAvailable -or (-not [string]::IsNullOrWhiteSpace([string]$status.ActualVersion))
    $isUpdate = ([string]$PlanItem.Intent -eq 'update')
    $isUninstall = ([string]$PlanItem.Intent -eq 'uninstall')

    if ($hasRecord -or $isUpdate -or $isUninstall) {
        Add-ToolkitDepLogLine -Log $Log -Text (Get-I18n -Key 'page.depOperation.logRecorded' -Vars @{
            version = (Get-ToolkitDepVersionLabel -Value ([string]$status.RecordedVersion))
        }) -WithTimestamp
    }
    if ($isInstalled -or $isUpdate -or ($isUninstall -and $PlanItem.ShouldExecute)) {
        Add-ToolkitDepLogLine -Log $Log -Text (Get-I18n -Key 'page.depOperation.logInstalled' -Vars @{
            version = (Get-ToolkitDepInstalledVersionLabel -Status $status -DetectedVersion $detectedVersion)
        }) -WithTimestamp
    }
    Add-ToolkitDepLogLine -Log $Log -Text (Get-I18n -Key 'page.depOperation.logDetected' -Vars @{
        version = (Get-ToolkitDepVersionLabel -Value $detectedVersion)
    }) -WithTimestamp
    Add-ToolkitDepLogLine -Log $Log -Text (Get-I18n -Key 'page.depOperation.logPolicyLine' -Vars @{
        policy = (Get-ToolkitDepPolicyLabel -Policy ([string]$status.Policy))
    }) -WithTimestamp

    if (-not $PlanItem.ShouldExecute) {
        if ($status.BlockedByOtherTools) {
            $others = @($status.OtherToolCommands) -join ', '
            Add-ToolkitDepLogLine -Log $Log -Text (Get-I18n -Key 'page.depOperation.logSkipSharedDep' -Vars @{
                name  = [string]$status.Name
                tools = $others
            }) -Kind 'success' -WithTimestamp
        }
        else {
            Add-ToolkitDepLogLine -Log $Log -Text (Get-I18n -Key 'page.depOperation.logSkip' -Vars @{
                action = (Get-ToolkitDepActionLabel -Action ([string]$status.Action))
            }) -Kind 'success' -WithTimestamp
        }
        return
    }

    Add-ToolkitDepLogLine -Log $Log -Text (Get-I18n -Key 'page.depOperation.logWillRun' -Vars @{
        action = (Get-ToolkitDepActionLabel -Action ([string]$PlanItem.ExecuteAction))
    }) -Kind 'heading' -WithTimestamp
}

function New-ToolkitDepOperationRunner {
    param(
        $Tool,
        $Plan,
        $Log,
        [scriptblock]$OnProgress = $null,
        [scriptblock]$OnExitConfirmKey = $null,
        [scriptblock]$ExitConfirmRef = $null,
        [scriptblock]$OnOutputLine = $null,
        [scriptblock]$OnHeartbeat = $null,
        [scriptblock]$OnUiPoll = $null,
        [scriptblock]$OnStallNotify = $null,
        [scriptblock]$ResolveStallPolicy = $null,
        [scriptblock]$OnBeforeExecute = $null,
        [scriptblock]$ShouldAbort = $null,
        [scriptblock]$OnFileLockRetry = $null,
        [scriptblock]$OnChromePulse = $null,
        [scriptblock]$OnDepLogChanged = $null
    )

    $runnerState = @{
        Tool         = $Tool
        Plan         = $Plan
        Log          = $Log
        Cancelled    = $false
        Failed       = $false
        SuccessCount = 0
        FailedCount  = 0
    }

    $fnWriteDetectLog = Resolve-DepOperationFn 'Write-ToolkitDepPlanDetectLog'
    $fnAddLog = Resolve-DepOperationFn 'Add-ToolkitDepLogLine'
    $fnGetI18n = Resolve-DepOperationFn 'Get-I18n'
    $fnExecutePackage = Resolve-DepOperationFn 'Invoke-ToolDepPackageExecute'
    $fnExecuteRuntime = Resolve-DepOperationFn 'Invoke-ToolkitRuntimeExecute'
    $fnRemoveGlobalDep = Resolve-DepOperationFn 'Remove-GlobalDepPackage'
    $fnSetPkgVersion = Resolve-DepOperationFn 'Set-ToolDepPackageVersion'
    $fnUpdatePath = Resolve-DepOperationFn 'Update-ToolDepSessionPath'
    $fnTestCmd = Resolve-DepOperationFn 'Test-ToolDepCommandAvailable'
    $fnResolveVersion = Resolve-DepOperationFn 'Resolve-ToolDepPackageVersionAfterAction'
    $fnRecordableVersion = Resolve-DepOperationFn 'Get-ToolDepPackageRecordableVersion'
    $fnGetDepRecordId = Resolve-DepOperationFn 'Get-DependencyRecordId'
    $fnTestAlreadyRemoved = Resolve-DepOperationFn 'Test-WingetDepResultIsAlreadyRemoved'
    $fnTestUninstallReported = Resolve-DepOperationFn 'Test-WingetDepResultReportsUninstallSuccess'
    $fnTestPackageRemoved = Resolve-DepOperationFn 'Test-ToolDepPackageRemovedAfterAction'
    $fnTestUserCancelled = Resolve-DepOperationFn 'Test-WingetDepResultIsUserCancelled'
    $fnGetDeclineKind = Resolve-DepOperationFn 'Get-WingetDepResultDeclineKind'
    $fnRegisterItemResult = Resolve-DepOperationFn 'Register-ToolkitDepRunnerItemResult'
    $fnTestNoInstaller = Resolve-DepOperationFn 'Test-WingetDepResultNoApplicableInstaller'
    $fnGetWingetSummary = Resolve-DepOperationFn 'Get-WingetDepResultSummaryLine'
    $fnGetWingetCommand = Resolve-DepOperationFn 'Get-ToolDepWingetCommandLine'
    $fnTestFileLockFailure = Resolve-DepOperationFn 'Test-WingetDepResultIsTempFileLockFailure'
    $fnRepairFileLock = Resolve-DepOperationFn 'Repair-WingetDepFileLockEnvironment'
    $fnPreflight = Resolve-DepOperationFn 'Test-ToolDepPackageNetworkPreflight'
    $fnNeedsInteractiveRetry = Resolve-DepOperationFn 'Test-WingetDepResultNeedsInteractiveRetry'
    $wingetPolicy = & (Resolve-DepOperationFn 'Get-WingetDepPolicyConstants')
    $fileLockMaxRetries = [Math]::Max(1, [int]$wingetPolicy.FileLockMaxRetries)

    $shouldCancel = {
        if ($ExitConfirmRef -and (& $ExitConfirmRef)) { return $true }
        return $false
    }.GetNewClosure()

    $processItem = {
        param($PlanItem)

        if ($runnerState.Cancelled) { return }

        if ($OnProgress) { & $OnProgress @{ Phase = 'detect'; Item = $PlanItem } }

        & $fnWriteDetectLog -Log $runnerState.Log -PlanItem $PlanItem

        if (-not $PlanItem.ShouldExecute) {
            if ($OnProgress) { & $OnProgress @{ Phase = 'skip'; Item = $PlanItem } }
            & $fnRegisterItemResult -RunnerState $runnerState -Result 'success'
            return
        }

        $executeAction = [string]$PlanItem.ExecuteAction
        $status = $PlanItem.Status

        if ($PlanItem._kind -eq 'runtime') {
            if ($OnProgress) { & $OnProgress @{ Phase = 'preflight'; Item = $PlanItem } }
            & $fnAddLog -Log $runnerState.Log -Text (& $fnGetI18n -Key 'page.runtime.logStarting' -Vars @{
                name = [string]$status.Name
            }) -WithTimestamp
            if ($OnBeforeExecute) { & $OnBeforeExecute }
            if ($OnUiPoll) { & $OnUiPoll }
            $runtimeResult = & $fnExecuteRuntime -Runtime $status.Package -ExecuteAction 'Install' `
                -OnOutputLine $OnOutputLine -OnPulse $OnChromePulse
            if ($runtimeResult.Lines) {
                foreach ($line in @($runtimeResult.Lines)) {
                    if (-not [string]::IsNullOrWhiteSpace([string]$line)) {
                        & $fnAddLog -Log $runnerState.Log -Text ([string]$line) -WithTimestamp
                    }
                }
            }
            if (-not $runtimeResult.Success) {
                if ($OnProgress) { & $OnProgress @{ Phase = 'fail'; Item = $PlanItem } }
                & $fnAddLog -Log $runnerState.Log -Text (& $fnGetI18n -Key 'page.runtime.logFailed' -Vars @{
                    name = [string]$status.Name
                }) -Kind 'error' -WithTimestamp
                & $fnRegisterItemResult -RunnerState $runnerState -Result 'failed'
                return
            }
            & $fnUpdatePath
            if ($OnProgress) { & $OnProgress @{ Phase = 'done'; Item = $PlanItem } }
            & $fnAddLog -Log $runnerState.Log -Text (& $fnGetI18n -Key 'page.depOperation.packageDone' -Vars @{
                name = [string]$status.Name
            }) -Kind 'success' -WithTimestamp
            & $fnRegisterItemResult -RunnerState $runnerState -Result 'success'
            return
        }

        if ($executeAction -eq 'Reconcile') {
            if ($OnProgress) { & $OnProgress @{ Phase = 'reconcile'; Item = $PlanItem } }
            $version = [string]$status.EffectiveVersion
            if ([string]::IsNullOrWhiteSpace($version)) { $version = [string]$status.ActualVersion }
            if ([string]::IsNullOrWhiteSpace($version)) {
                $version = [string](& $fnRecordableVersion -Package $status.Package)
            }
            if (-not [string]::IsNullOrWhiteSpace($version)) {
                & $fnSetPkgVersion -ToolId ([string]$runnerState.Tool.id) `
                    -DependencyId ([string]$status.DependencyId) -Version $version -Package $status.Package
                & $fnAddLog -Log $runnerState.Log -Text (& $fnGetI18n -Key 'page.depOperation.logReconciled' -Vars @{
                    name = [string]$status.Name; version = $version
                }) -Kind 'success' -WithTimestamp
            }
            if ($OnProgress) { & $OnProgress @{ Phase = 'done'; Item = $PlanItem } }
            & $fnRegisterItemResult -RunnerState $runnerState -Result 'success'
            return
        }

        $wingetCommand = & $fnGetWingetCommand -Package $status.Package -ExecuteAction $executeAction
        if ($executeAction -in @('Install', 'Upgrade', 'Repair')) {
            if ($OnProgress) { & $OnProgress @{ Phase = 'preflight'; Item = $PlanItem } }
            & $fnAddLog -Log $runnerState.Log -Text (& $fnGetI18n -Key 'page.depOperation.logNetworkPreflight') -WithTimestamp
            if ($OnDepLogChanged) { & $OnDepLogChanged }
            if ($OnUiPoll) { & $OnUiPoll }
            $preflight = & $fnPreflight -Package $status.Package -ExecuteAction $executeAction -OnPulse $OnChromePulse
            if (-not $preflight.Ok) {
                if ($OnProgress) { & $OnProgress @{ Phase = 'fail'; Item = $PlanItem } }
                & $fnAddLog -Log $runnerState.Log -Text (& $fnGetI18n -Key 'page.depOperation.logNetworkPreflightFail' -Vars @{
                    url    = [string]$preflight.Url
                    reason = [string]$preflight.Reason
                }) -Kind 'error' -WithTimestamp
                & $fnRegisterItemResult -RunnerState $runnerState -Result 'failed'
                return
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($wingetCommand)) {
            & $fnAddLog -Log $runnerState.Log -Text (& $fnGetI18n -Key 'page.depOperation.logInvokeWinget' -Vars @{
                command = $wingetCommand
            }) -WithTimestamp
            & $fnAddLog -Log $runnerState.Log -Text (& $fnGetI18n -Key 'page.depOperation.logMayPrompt') -Kind 'heading' -WithTimestamp
            & $fnAddLog -Log $runnerState.Log -Text (& $fnGetI18n -Key 'page.depOperation.logWingetStarting') -WithTimestamp
            # 三条 winget 预备日志合并到紧随其后的 OnBeforeExecute 一次 RedrawView，避免重复全页绘制
        }

        $result = $null
        $fileLockAttempt = 0
        $wingetSilentMode = 'default'
        while ($fileLockAttempt -lt $fileLockMaxRetries) {
            $fileLockAttempt++
            if ($fileLockAttempt -gt 1) {
                & $fnAddLog -Log $runnerState.Log -Text (& $fnGetI18n -Key 'page.depOperation.logFileLockRetry' -Vars @{
                    attempt = $fileLockAttempt
                    max     = $fileLockMaxRetries
                }) -Kind 'heading' -WithTimestamp
                if ($OnFileLockRetry) { & $OnFileLockRetry $fileLockAttempt }
                & $fnRepairFileLock -Attempt ($fileLockAttempt - 1) -OnPulse $OnChromePulse
                if ($OnProgress) {
                    & $OnProgress @{ Phase = 'run'; Item = $PlanItem; Command = [string]$wingetCommand }
                }
            }

            if ($OnBeforeExecute) { & $OnBeforeExecute }
            if ($OnUiPoll) { & $OnUiPoll }

            $result = & $fnExecutePackage -Package $status.Package -ExecuteAction $executeAction `
                -SilentMode $wingetSilentMode -ShouldCancel $shouldCancel -ShouldAbort $ShouldAbort `
                -OnExitConfirmKey $OnExitConfirmKey -OnOutputLine $OnOutputLine -OnHeartbeat $OnHeartbeat `
                -OnUiPoll $OnUiPoll -OnChromePulse $OnChromePulse -OnStallNotify $OnStallNotify `
                -ResolveStallPolicy $ResolveStallPolicy

            if ($result.Cancelled) { break }

            $isFileLockFailure = ($result.Aborted -or $result.TimedOut -or -not $result.Success) `
                -and (& $fnTestFileLockFailure -Result $result)
            if ($isFileLockFailure -and $fileLockAttempt -lt $fileLockMaxRetries) {
                continue
            }

            if ((-not $result.Success) -and ($wingetSilentMode -ne 'interactive') `
                    -and (& $fnNeedsInteractiveRetry -Result $result -ExecuteAction $executeAction)) {
                & $fnAddLog -Log $runnerState.Log -Text (& $fnGetI18n -Key 'page.depOperation.logSilentFallbackRetry') `
                    -Kind 'heading' -WithTimestamp
                $retryCommand = & $fnGetWingetCommand -Package $status.Package -ExecuteAction $executeAction `
                    -SilentMode interactive
                if (-not [string]::IsNullOrWhiteSpace($retryCommand)) {
                    & $fnAddLog -Log $runnerState.Log -Text (& $fnGetI18n -Key 'page.depOperation.logInvokeWinget' -Vars @{
                        command = $retryCommand
                    }) -WithTimestamp
                }
                if ($OnFileLockRetry) { & $OnFileLockRetry 0 -InteractiveFallback }
                $wingetSilentMode = 'interactive'
                $fileLockAttempt--
                if ($OnProgress) {
                    & $OnProgress @{ Phase = 'run'; Item = $PlanItem; Command = [string]$retryCommand }
                }
                continue
            }
            break
        }

        if ($OnProgress -and $result -and $result.Command) {
            & $OnProgress @{ Phase = 'run'; Item = $PlanItem; Command = [string]$result.Command }
        }

        if (-not $result.Streamed) {
            foreach ($line in @($result.Lines)) {
                & $fnAddLog -Log $runnerState.Log -Text $line -WithTimestamp
            }
        }

        if ($result.Cancelled) {
            $runnerState.Cancelled = $true
            & $fnAddLog -Log $runnerState.Log -Text (& $fnGetI18n -Key 'page.depOperation.cancelled') `
                -Kind 'error' -WithTimestamp
            return
        }

        if ($result.Aborted) {
            if ($OnProgress) { & $OnProgress @{ Phase = 'fail'; Item = $PlanItem } }
            $declineKind = & $fnGetDeclineKind -Result $result
            if ($declineKind) {
                $declineText = Get-ToolkitDepDeclineLogText -DeclineKind $declineKind -ExecuteAction $executeAction
                & $fnAddLog -Log $runnerState.Log -Text $declineText -Kind 'error' -WithTimestamp
            }
            elseif (& $fnTestFileLockFailure -Result $result) {
                & $fnAddLog -Log $runnerState.Log -Text (& $fnGetI18n -Key 'page.depOperation.logFileLockAbort') `
                    -Kind 'error' -WithTimestamp
            }
            else {
                $summaryLine = & $fnGetWingetSummary -Result $result
                if (-not [string]::IsNullOrWhiteSpace($summaryLine)) {
                    & $fnAddLog -Log $runnerState.Log -Text $summaryLine -Kind 'error' -WithTimestamp
                }
            }
            & $fnRegisterItemResult -RunnerState $runnerState -Result 'failed'
            return
        }

        if ($result.TimedOut) {
            if ($OnProgress) { & $OnProgress @{ Phase = 'fail'; Item = $PlanItem } }
            $timeoutKey = switch ([string]$result.TimedOutReason) {
                'installerPrompt' { 'page.depOperation.logInstallerPromptTimeout' }
                default {
                    if (& $fnTestFileLockFailure -Result $result) {
                        'page.depOperation.logFileLockAbort'
                    }
                    else {
                        'page.depOperation.logStallTimeout'
                    }
                }
            }
            & $fnAddLog -Log $runnerState.Log -Text (& $fnGetI18n -Key $timeoutKey) `
                -Kind 'error' -WithTimestamp
            & $fnRegisterItemResult -RunnerState $runnerState -Result 'failed'
            return
        }

        if (-not $result.Success) {
            $declineKind = & $fnGetDeclineKind -Result $result
            if ($declineKind) {
                if ($OnProgress) { & $OnProgress @{ Phase = 'fail'; Item = $PlanItem } }
                $declineText = Get-ToolkitDepDeclineLogText -DeclineKind $declineKind -ExecuteAction $executeAction
                & $fnAddLog -Log $runnerState.Log -Text $declineText -Kind 'error' -WithTimestamp
                & $fnRegisterItemResult -RunnerState $runnerState -Result 'failed'
                return
            }
            $uninstallVerified = $false
            if ($executeAction -eq 'Uninstall') {
                & $fnUpdatePath
                $uninstallVerified = (& $fnTestAlreadyRemoved $result) -or (& $fnTestUninstallReported $result)
                if (-not $uninstallVerified -and -not (& $fnTestUserCancelled $result)) {
                    $uninstallVerified = & $fnTestPackageRemoved -Package $status.Package
                }
            }

            if ($uninstallVerified) {
                if (-not (& $fnTestUninstallReported $result)) {
                    $verifiedKey = if (& $fnTestAlreadyRemoved $result) {
                        'page.depOperation.logAlreadyRemoved'
                    }
                    else {
                        'page.depOperation.logUninstallVerified'
                    }
                    & $fnAddLog -Log $runnerState.Log -Text (& $fnGetI18n -Key $verifiedKey -Vars @{
                        name = [string]$status.Name
                    }) -Kind 'success' -WithTimestamp
                }
                if ($OnProgress) { & $OnProgress @{ Phase = 'done'; Item = $PlanItem } }
                & $fnAddLog -Log $runnerState.Log -Text (& $fnGetI18n -Key 'page.depOperation.packageDone' -Vars @{
                    name = [string]$status.Name
                }) -Kind 'success' -WithTimestamp
                & $fnRegisterItemResult -RunnerState $runnerState -Result 'success'
                return
            }

            $summaryLine = & $fnGetWingetSummary -Result $result
            if (-not [string]::IsNullOrWhiteSpace($summaryLine)) {
                & $fnAddLog -Log $runnerState.Log -Text $summaryLine -Kind 'error' -WithTimestamp
            }
            if (& $fnTestNoInstaller $result) {
                if ($OnProgress) { & $OnProgress @{ Phase = 'fail'; Item = $PlanItem } }
                & $fnAddLog -Log $runnerState.Log -Text (& $fnGetI18n -Key 'page.depOperation.logNoApplicableInstaller' -Vars @{
                    name = [string]$status.Name
                }) -Kind 'error' -WithTimestamp
                & $fnRegisterItemResult -RunnerState $runnerState -Result 'failed'
                return
            }
            if (& $fnTestFileLockFailure -Result $result) {
                if ($OnProgress) { & $OnProgress @{ Phase = 'fail'; Item = $PlanItem } }
                & $fnAddLog -Log $runnerState.Log -Text (& $fnGetI18n -Key 'page.depOperation.logFileLockAbort') `
                    -Kind 'error' -WithTimestamp
                & $fnRegisterItemResult -RunnerState $runnerState -Result 'failed'
                return
            }
            $exitCodeText = if ($null -eq $result.ExitCode) {
                '-'
            }
            else { [string]$result.ExitCode }
            if ($OnProgress) { & $OnProgress @{ Phase = 'fail'; Item = $PlanItem } }
            & $fnAddLog -Log $runnerState.Log -Text (& $fnGetI18n -Key 'page.depOperation.packageFailed' -Vars @{
                name = [string]$status.Name; code = $exitCodeText
            }) -Kind 'error' -WithTimestamp
            & $fnRegisterItemResult -RunnerState $runnerState -Result 'failed'
            return
        }

        if ($result.AlreadyLatest) {
            & $fnAddLog -Log $runnerState.Log -Text (& $fnGetI18n -Key 'page.depOperation.logAlreadyLatest' -Vars @{
                name = [string]$status.Name
            }) -Kind 'success' -WithTimestamp
        }

        if ($executeAction -in @('Install', 'Upgrade', 'Repair')) {
            & $fnUpdatePath
            $checkCommand = [string]$status.CheckCommand
            if ($checkCommand -and -not (& $fnTestCmd -CheckCommand $checkCommand)) {
                if ($OnProgress) { & $OnProgress @{ Phase = 'fail'; Item = $PlanItem } }
                & $fnAddLog -Log $runnerState.Log -Text (& $fnGetI18n -Key 'page.depOperation.verifyFailed' -Vars @{
                    command = $checkCommand
                }) -Kind 'error' -WithTimestamp
                & $fnRegisterItemResult -RunnerState $runnerState -Result 'failed'
                return
            }

            $versions = & $fnResolveVersion -Package $status.Package
            if (-not $versions -or $versions.Count -eq 0) {
                $fallback = [string](& $fnRecordableVersion -Package $status.Package)
                if (-not [string]::IsNullOrWhiteSpace($fallback)) {
                    $versions = @{
                        (& $fnGetDepRecordId -Dependency $status.Package) = $fallback
                    }
                }
            }
            if ($versions -and $versions.Count -gt 0) {
                foreach ($depId in $versions.Keys) {
                    & $fnSetPkgVersion -ToolId ([string]$runnerState.Tool.id) `
                        -DependencyId ([string]$depId) -Version ([string]$versions[$depId]) -Package $status.Package
                }
            }
        }

        if ($executeAction -eq 'Uninstall') {
            & $fnRemoveGlobalDep -Fingerprint ([string]$status.DependencyId)
        }

        if ($OnProgress) { & $OnProgress @{ Phase = 'done'; Item = $PlanItem } }
        & $fnAddLog -Log $runnerState.Log -Text (& $fnGetI18n -Key 'page.depOperation.packageDone' -Vars @{
            name = [string]$status.Name
        }) -Kind 'success' -WithTimestamp
        & $fnRegisterItemResult -RunnerState $runnerState -Result 'success'
    }.GetNewClosure()

    return [pscustomobject]@{
        ProcessItem = $processItem
        State       = $runnerState
    }
}

function Test-ToolkitDepRunnerSuccess {
    param($Runner)
    if (-not $Runner) { return $true }
    if ($Runner.State.Cancelled) { return $false }
    if ($null -ne $Runner.State.FailedCount) {
        return ([int]$Runner.State.FailedCount -eq 0)
    }
    return (-not $Runner.State.Failed)
}

function Draw-ToolkitDepOperationLogViewport {
    param(
        [hashtable]$Shell,
        $Log,
        [int]$LogSeparatorRow,
        [int]$LogContentViewportRows,
        [switch]$RepairBrandTextRowsAfterDraw
    )

    if ($null -eq $Log) { return }

    $fnFormatLogLine = Resolve-DepOperationFn 'Format-ToolkitDepLogLineText'

    $layout = $Shell.Layout
    $barWidth = if ([int]$Log.BrandInnerWidth -gt 0) { [int]$Log.BrandInnerWidth } else {
        if ($Shell.BrandInnerWidth -gt 0) { [int]$Shell.BrandInnerWidth } else { [int]$layout.BrandInnerWidth }
    }

    $layoutMetrics = Get-ToolkitDepOperationLogLayout -Layout $layout
    $maxPaintRow = [int]$layoutMetrics.MaxPaintRow
    if ($LogContentViewportRows -le 0) { return }

    $logLines = Get-ToolkitDepOperationLogLines -Log $Log
    $lineCount = if ($logLines) { [int]$logLines.Count } else { 0 }

    $maxScroll = [Math]::Max(0, $lineCount - $LogContentViewportRows)
    if ($Log.ScrollOffset -gt $maxScroll) { $Log.ScrollOffset = $maxScroll }

    $brandEnd = Get-ToolkitShellBrandEndRow -Shell $Shell
    if ($LogSeparatorRow -lt $brandEnd) { return }

    $contentStartRow = $LogSeparatorRow
    for ($row = 0; $row -lt $LogContentViewportRows; $row++) {
        $idx = $Log.ScrollOffset + $row
        $screenRow = $contentStartRow + $row
        if ($screenRow -lt $brandEnd) { continue }
        if ($screenRow -gt $maxPaintRow) {
            break
        }
        if ($idx -ge 0 -and $idx -lt $lineCount) {
            $line = $logLines[$idx]
            $prefix = if ($line.Kind -eq 'separator') { '' } else { ' ' }
            Write-ToolkitDepContentFixedLine -Row $screenRow `
                -Text "$prefix$(& $fnFormatLogLine -Line $line -BrandInnerWidth $barWidth)" `
                -Color $line.Color -Shell $Shell -BrandInnerWidth $barWidth
        }
        else {
            Write-ToolkitDepContentFixedLine -Row $screenRow -Text '' -Color DarkGray `
                -Shell $Shell -BrandInnerWidth $barWidth
        }
    }

    if ($RepairBrandTextRowsAfterDraw) {
        $fnRepairBrandTextRows = Get-Command Repair-ToolkitShellBrandPanelTextRows -ErrorAction SilentlyContinue
        if ($fnRepairBrandTextRows) {
            & $fnRepairBrandTextRows -Shell $Shell
        }
    }
}

function Draw-ToolkitDepOperationView {
    param(
        [hashtable]$Shell,
        $Log,
        [int]$ProgressCurrent,
        [int]$ProgressTotal,
        [string]$ProgressName,
        [string]$StatusText,
        [string]$StatusRightText = '',
        [int]$LogViewportRows,
        [int]$LogStartRow,
        [int]$ProgressItemSubPercent = -1,
        [switch]$ProgressItemInFlight,
        [switch]$StatusPlain,
        [array]$StatusSegments = $null,
        [switch]$ChromeOnly
    )

    $fnWriteFixed = Resolve-DepOperationFn 'Write-FixedLine'
    $fnGetI18n = Resolve-DepOperationFn 'Get-I18n'
    $fnFormatBar = Resolve-DepOperationFn 'Format-ToolkitDepProgressBar'
    $fnFormatStatus = Resolve-DepOperationFn 'Format-ToolkitDepOperationStatusLine'
    $fnResolveProgress = Resolve-DepOperationFn 'Resolve-DepOperationProgressDisplay'
    $fnMaxScroll = Resolve-DepOperationFn 'Get-ToolkitDepLogMaxScroll'
    $fnFormatLogLine = Resolve-DepOperationFn 'Format-ToolkitDepLogLineText'

    $layout = $Shell.Layout
    $barWidth = if ($Shell.BrandInnerWidth -gt 0) { $Shell.BrandInnerWidth } else { $layout.BrandInnerWidth }
    $progressDisplay = & $fnResolveProgress -ProgressCurrent $ProgressCurrent -ProgressTotal $ProgressTotal `
        -ItemInFlight:([bool]$ProgressItemInFlight) -ItemSubPercent $ProgressItemSubPercent
    Write-ToolkitDepContentFixedLine -Row $layout.ListStartRow `
        -Text (& $fnFormatBar -Total $ProgressTotal -BrandInnerWidth $barWidth `
            -ItemIndex $progressDisplay.ItemIndex -ItemSubPercent $progressDisplay.ItemSubPercent) `
        -Color Cyan -Shell $Shell -BrandInnerWidth $barWidth

    if ($StatusSegments -and $StatusSegments.Count -gt 0) {
        if (-not [string]::IsNullOrWhiteSpace($StatusRightText)) {
            Write-ToolkitDepOperationSplitStatusSegments -Row ($layout.ListStartRow + 1) `
                -Segments $StatusSegments -RightText $StatusRightText -BrandInnerWidth $barWidth `
                -Shell $Shell -LeadingSpace
        }
        else {
            Write-ToolkitDepFixedLineSegments -Row ($layout.ListStartRow + 1) -Segments $StatusSegments `
                -Shell $Shell -BrandInnerWidth $barWidth -LeadingSpace
        }
    }
    elseif (-not [string]::IsNullOrWhiteSpace($StatusRightText)) {
        Write-ToolkitDepOperationSplitStatusLine -Row ($layout.ListStartRow + 1) `
            -MainText $StatusText -RightText $StatusRightText -BrandInnerWidth $barWidth `
            -Shell $Shell -LeadingSpace
    }
    elseif ($StatusPlain) {
        $formatted = & $fnFormatStatus -Text $StatusText -BrandInnerWidth $barWidth
        Write-ToolkitDepContentFixedLine -Row ($layout.ListStartRow + 1) -Text " $formatted " `
            -Color White -Shell $Shell -BrandInnerWidth $barWidth
    }
    else {
        if ([string]::IsNullOrWhiteSpace($StatusText)) {
            Write-ToolkitDepContentFixedLine -Row ($layout.ListStartRow + 1) -Text ' ' `
                -Color White -Shell $Shell -BrandInnerWidth $barWidth
        }
        else {
            $formatted = & $fnFormatStatus -Text $StatusText -BrandInnerWidth $barWidth
            Write-ToolkitDepContentFixedLine -Row ($layout.ListStartRow + 1) -Text " $formatted " `
                -Color White -Shell $Shell -BrandInnerWidth $barWidth
        }
    }
    Write-ToolkitDepContentFixedLine -Row ($layout.ListStartRow + 2) -Text '' `
        -Color DarkGray -Shell $Shell -BrandInnerWidth $barWidth

    if ($ChromeOnly) { return }

    if ($LogViewportRows -le 0) {
        if ($layout.MessageRow -ge 0) {
            Write-ToolkitDepContentFixedLine -Row $layout.MessageRow -Text '' -Color DarkGray `
                -Shell $Shell -BrandInnerWidth $barWidth
        }
        return
    }

    $logLines = Get-ToolkitDepOperationLogLines -Log $Log
    $lineCount = if ($logLines) { [int]$logLines.Count } else { 0 }

    $maxScroll = & $fnMaxScroll -Log $Log -ViewportRows $LogViewportRows
    if ($Log.ScrollOffset -gt $maxScroll) { $Log.ScrollOffset = $maxScroll }

    for ($row = 0; $row -lt $LogViewportRows; $row++) {
        $idx = $Log.ScrollOffset + $row
        $screenRow = $LogStartRow + $row
        if ($idx -ge 0 -and $idx -lt $lineCount) {
            $line = $logLines[$idx]
            $prefix = if ($line.Kind -eq 'separator') { '' } else { ' ' }
            Write-ToolkitDepContentFixedLine -Row $screenRow `
                -Text "$prefix$(& $fnFormatLogLine -Line $line -BrandInnerWidth $barWidth)" `
                -Color $line.Color -Shell $Shell -BrandInnerWidth $barWidth
        }
        else {
            Write-ToolkitDepContentFixedLine -Row $screenRow -Text '' -Color DarkGray `
                -Shell $Shell -BrandInnerWidth $barWidth
        }
    }

    if ($layout.MessageRow -ge 0) {
        Write-ToolkitDepContentFixedLine -Row $layout.MessageRow -Text '' -Color DarkGray `
            -Shell $Shell -BrandInnerWidth $barWidth
    }
}

function Invoke-ToolkitDepOperationView {
    param(
        [hashtable]$Shell,
        [string]$SectionTitle,
        $Tool,
        [ValidateSet('install', 'update', 'uninstall')]
        [string]$Intent,
        [switch]$AutoContinue,
        [string]$PreflightErrorKey = '',
        $SharedLog = $null,
        [array]$AllTools = $null
    )

    $fnGetI18n = Resolve-DepOperationFn 'Get-I18n'
    $resolvedTools = if ($AllTools) { @($AllTools) } elseif (Get-Command Get-ToolkitTools -ErrorAction SilentlyContinue) {
        @(Get-ToolkitTools)
    }
    else {
        @(Discover-Tools)
    }
    $plan = $null
    $effectivePreflightKey = [string]$PreflightErrorKey
    if ([string]::IsNullOrWhiteSpace($effectivePreflightKey)) {
        $builtPlan = Build-ToolkitDepOperationPlan -Tool $Tool -Intent $Intent -AllTools $resolvedTools
        $wingetPreflightKey = Get-ToolkitDepWingetPreflightErrorKey -Plan $builtPlan
        if ($wingetPreflightKey) {
            $effectivePreflightKey = $wingetPreflightKey
        }
        else {
            $plan = $builtPlan
        }
    }

    $total = if ($plan) { @($plan.Items).Count } else { 1 }

    $exitConfirmArmed = $false
    $onExitConfirmed = { $exitConfirmArmed = $true }.GetNewClosure()
    $exitConfirmRef = { return [bool]$exitConfirmArmed }.GetNewClosure()

    $ctx = Initialize-ToolkitDepBatchOperationView -Shell $Shell -SectionTitle $SectionTitle `
        -ProgressTotal $total -Log $SharedLog -OnExitConfirmed $onExitConfirmed

    $log = $ctx.Log
    $ui = $ctx.Ui
    $RedrawView = $ctx.RedrawView
    $RedrawDepChrome = $ctx.RedrawDepChrome
    $onExitKey = $ctx.OnExitKey
    $uiPollState = $ctx.PollState
    $logSeparatorRow = $ctx.LogSeparatorRow
    $logContentViewportRows = $ctx.LogContentViewportRows
    $brandRepairState = $ctx.BrandRepairState
    $fnDrainStaleInput = $ctx.FnDrainStaleInput
    $fnDrainEscInput = Resolve-DepOperationFn 'Drain-ConsoleEscInputIfAvailable'
    $fnLogInput = $ctx.FnLogInput

    $complete = $false
    $runner = $null

    $invokeDepOperationRedrawNow = {
        & $RedrawView
    }.GetNewClosure()

    $onDepLogChanged = {
        if ($brandRepairState) { $brandRepairState.Requested = $true }
        & $invokeDepOperationRedrawNow
    }.GetNewClosure()

    if ($effectivePreflightKey) {
        Add-ToolkitDepLogLine -Log $log -Text (& $fnGetI18n -Key $effectivePreflightKey) -Kind 'error' -WithTimestamp
        $complete = $true
    }

    $fnGetStatusText = Resolve-DepOperationFn 'Get-ToolkitDepStatusText'
    $fnAddLog = Resolve-DepOperationFn 'Add-ToolkitDepLogLine'

    if ($plan) {
        $fnGetOutputDecision = Resolve-DepOperationFn 'Get-ToolkitDepWingetOutputDecision'
        $fnUpdateLoading = Resolve-DepOperationFn 'Update-ToolkitDepLoadingStatus'
        $fnTestFileLockLine = Resolve-DepOperationFn 'Test-WingetDepStreamLineIsFileLockRemoveError'
        $fnGetDeclineKind = Resolve-DepOperationFn 'Get-WingetDepStreamLineDeclineKind'
        $fnTestWingetSilent = Resolve-DepOperationFn 'Test-ToolDepWingetInstallUsesSilent'
        $wingetPolicy = Resolve-DepOperationFn 'Get-WingetDepPolicyConstants'
        $wingetPolicy = & $wingetPolicy
        $fnCleanLine = Resolve-DepOperationFn 'Get-WingetStreamLineCleanText'
        $fnIsSpinner = Resolve-DepOperationFn 'Test-WingetStreamLineIsSpinnerOnly'
        $fnIsProgressVisual = Resolve-DepOperationFn 'Test-WingetDepStreamLineIsProgressVisual'
        $fnGetPercent = Resolve-DepOperationFn 'Get-WingetDepStreamLinePercent'

        $wingetAbortState = @{ Requested = $false }
        $wingetOutputState = @{
            LastLoggedPercent        = -1
            LoggedPhases             = @{}
            LastSubstantiveLineTick  = [Environment]::TickCount
            ElapsedSeconds           = 0
            SpinnerFrames            = @('|', '/', '-', '\')
            SpinnerIndex             = 0
            LoggedWorking            = $false
            PercentStage             = ''
            LoggedDownloadComplete   = $false
            LoggedInstallComplete    = $false
            WingetOutputSeen         = $false
            WingetInstallSilent      = $false
            SubstantiveLogCount      = 0
            InstallerAwaitingDialog  = $false
            InstallerPromptDismissed = $false
            InstallerPromptStartTick = 0
            InstallStarted           = $false
            InstallStartedTick       = 0
            WingetOperationSucceeded = $false
            FileLockErrorCount       = 0
            FileLockWarnLogged       = $false
        }
        $stallNotifyState = @{ LastTick = 0; Logged = $false }

        $onChromePulse = {
            $changed = Sync-ToolkitDepOperationStatusChrome -Ui $ui -PollState $uiPollState
            if ($changed) {
                & $RedrawDepChrome
            }
        }.GetNewClosure()

        $refreshDepLoadingStatus = {
            if (-not $ui.ItemInFlight) { return }
            $now = [Environment]::TickCount
            $elapsed = if ($ui.ExecuteStartTick -gt 0) {
                [int][Math]::Floor(($now - $ui.ExecuteStartTick) / 1000.0)
            }
            else { 0 }
            $null = & $fnUpdateLoading -Ui $ui -WingetOutputState $wingetOutputState `
                -ElapsedSeconds $elapsed -GetI18n $fnGetI18n
        }.GetNewClosure()

        $shouldAbortWinget = {
            return [bool]$wingetAbortState.Requested
        }.GetNewClosure()

        $registerWingetFileLockFailure = {
            param([string]$Line)
            if (-not (& $fnTestFileLockLine -Line $Line)) { return $false }

            $wingetOutputState['FileLockErrorCount'] = [int]$wingetOutputState['FileLockErrorCount'] + 1
            if (-not $wingetOutputState['FileLockWarnLogged']) {
                $wingetOutputState['FileLockWarnLogged'] = $true
                & $fnAddLog -Log $log -Text (& $fnGetI18n -Key 'page.depOperation.logFileLockWarn') -WithTimestamp
            }
            return $false
        }.GetNewClosure()

        $registerWingetDeclineFailure = {
            param([string]$Line)
            if ($wingetOutputState['DeclineHandled']) { return $false }
            $declineKind = & $fnGetDeclineKind -Line $Line
            if (-not $declineKind) { return $false }

            $wingetOutputState['DeclineHandled'] = $true
            Complete-ToolkitDepInstallerPromptPhase -OutputState $wingetOutputState
            $wingetOutputState['InstallerAwaitingDialog'] = $false

            $action = [string]$wingetOutputState['ExecuteAction']
            if ([string]::IsNullOrWhiteSpace($action)) { $action = 'Install' }
            $declineText = Get-ToolkitDepDeclineLogText -DeclineKind $declineKind -ExecuteAction $action
            Set-ToolkitDepOperationInFlightStatus -Ui $ui -MainText $declineText
            & $fnAddLog -Log $log -Text $Line -WithTimestamp
            $wingetAbortState.Requested = $true
            return $true
        }.GetNewClosure()

        $onBeforeExecute = {
            $ui.ExecuteStartTick = [Environment]::TickCount
            $wingetOutputState['LastSubstantiveLineTick'] = $ui.ExecuteStartTick
            $null = & $fnUpdateLoading -Ui $ui -WingetOutputState $wingetOutputState -ElapsedSeconds 0 -GetI18n $fnGetI18n
            if ($brandRepairState) { $brandRepairState.Requested = $true }
            & $invokeDepOperationRedrawNow
        }.GetNewClosure()

        $onProgress = {
            param($Info)
            $ui.ProgressName = [string]$Info.Item.Status.Name
            $executeAction = [string]$Info.Item.ExecuteAction
            $phaseTarget = Get-ToolkitDepRunnerProgressPhaseTarget -Phase ([string]$Info.Phase) `
                -ExecuteAction $executeAction
            if ($phaseTarget -ge 0) {
                Apply-ToolkitDepWingetProgressUpdate -Ui $ui -WingetOutputState $wingetOutputState `
                    -Target $phaseTarget
            }
            if (-not $wingetOutputState['InstallerAwaitingDialog']) {
                Set-ToolkitDepOperationInFlightStatus -Ui $ui -MainText (& $fnGetStatusText -PlanItem $Info.Item `
                    -Phase ([string]$Info.Phase) -Command ([string]$Info.Command))
            }
            & $RedrawDepChrome
        }.GetNewClosure()

        $onOutputLine = {
            param($Line)
            $raw = & $fnCleanLine -Line $Line
            if ([string]::IsNullOrWhiteSpace($raw)) { return }

            if ((& $registerWingetDeclineFailure $raw)) {
                & $invokeDepOperationRedrawNow
                return
            }

            if ((& $fnIsSpinner -Line $raw)) {
                $wingetOutputState['WingetOutputSeen'] = $true
                & $refreshDepLoadingStatus
                & $RedrawDepChrome
                return
            }

            if ((& $fnIsProgressVisual -Line $raw)) {
                $wingetOutputState['WingetOutputSeen'] = $true
                $null = & $registerWingetFileLockFailure $raw
                $decision = & $fnGetOutputDecision -Line $Line -OutputState $wingetOutputState
                $pct = [int]$decision.Percent
                if ($pct -lt 0) {
                    $pct = & $fnGetPercent -Line $raw
                }
                if ($pct -ge 0) {
                    $decision.Percent = $pct
                }
                Update-ToolkitDepWingetProgressFromDecision -Ui $ui -WingetOutputState $wingetOutputState -Decision $decision
                $statusText = Format-WingetDepStreamLineTransferStatus -Line $raw
                if ([string]::IsNullOrWhiteSpace($statusText) -and $pct -ge 0) {
                    $statusText = & $fnGetI18n -Key 'page.depOperation.statusDownload' -Vars @{ percent = $pct }
                }
                elseif ([string]::IsNullOrWhiteSpace($statusText) -and $decision.StatusText) {
                    $statusText = [string]$decision.StatusText
                }
                if (-not [string]::IsNullOrWhiteSpace($statusText)) {
                    Set-ToolkitDepOperationInFlightStatus -Ui $ui -MainText $statusText -AdvanceSpinner
                }
                & $refreshDepLoadingStatus
                & $RedrawDepChrome
                return
            }

            $wingetOutputState['WingetOutputSeen'] = $true
            $null = & $registerWingetFileLockFailure $raw
            $decision = & $fnGetOutputDecision -Line $Line -OutputState $wingetOutputState
            $substantive = (-not [string]::IsNullOrWhiteSpace([string]$decision.LogText)) `
                -or ((-not $decision.RedrawOnly) -and (-not [string]::IsNullOrWhiteSpace([string]$decision.StatusText)))
            if ($substantive) {
                $wingetOutputState['LastSubstantiveLineTick'] = [Environment]::TickCount
                $stallNotifyState.Logged = $false
            }

            if ($decision.Percent -ge 0) {
                $decision.Percent = [int]$decision.Percent
            }
            Update-ToolkitDepWingetProgressFromDecision -Ui $ui -WingetOutputState $wingetOutputState -Decision $decision
            if ($decision.StatusText -and -not $decision.RedrawOnly) {
                Set-ToolkitDepOperationInFlightStatus -Ui $ui -MainText ([string]$decision.StatusText)
            }
            $needsFullRedraw = $false
            if ($decision.PendingLogTexts) {
                foreach ($pendingText in @($decision.PendingLogTexts)) {
                    if ([string]::IsNullOrWhiteSpace([string]$pendingText)) { continue }
                    & $fnAddLog -Log $log -Text ([string]$pendingText) -WithTimestamp
                    $needsFullRedraw = $true
                }
            }
            if ($decision.LogText -and -not $decision.RedrawOnly) {
                $logText = [string]$decision.LogText
                if ($logText -match '已成功安装|Successfully installed|已成功卸载|Successfully uninstalled|卸载成功') {
                    $wingetOutputState['WingetOperationSucceeded'] = $true
                    $stallNotifyState.Logged = $false
                }
                $skipSpinner = (& $fnIsSpinner -Line $raw) -and ($logText -eq $raw)
                if (-not $skipSpinner) {
                    & $fnAddLog -Log $log -Text $logText -WithTimestamp
                    $needsFullRedraw = $true
                }
            }
            if ($decision.RedrawOnly) {
                & $refreshDepLoadingStatus
            }
            if ($needsFullRedraw) {
                & $invokeDepOperationRedrawNow
            }
            else {
                & $RedrawDepChrome
            }
        }.GetNewClosure()

        $onHeartbeat = {
            param($Info)
            if (-not $ui.ItemInFlight) { return }

            $null = & $fnUpdateLoading -Ui $ui -WingetOutputState $wingetOutputState `
                -ElapsedSeconds ([int]$Info.ElapsedSeconds) -GetI18n $fnGetI18n `
                -IdleSeconds ([int]$Info.IdleSeconds)
            if (-not $wingetOutputState['LoggedWorking'] -and [int]$Info.IdleSeconds -ge 2 `
                    -and -not $wingetOutputState['InstallStarted'] `
                    -and -not $wingetOutputState['InstallerAwaitingDialog']) {
                $wingetOutputState['LoggedWorking'] = $true
                & $fnAddLog -Log $log -Text (& $fnGetI18n -Key 'page.depOperation.logWorking') -WithTimestamp
                & $invokeDepOperationRedrawNow
                return
            }
            & $RedrawDepChrome
        }.GetNewClosure()

        $onUiPoll = {
            $inputResult = & $fnLogInput -Shell $Shell -Log $log -ViewportRows $logContentViewportRows `
                -OnExitKey $onExitKey -ScrollState $uiPollState
            if ($inputResult -eq 'scroll') {
                & $invokeDepOperationRedrawNow
            }
            elseif ($inputResult -eq 'exit') {
                return
            }

            if (-not $ui.ItemInFlight) { return }

            $now = [Environment]::TickCount
            if (($now - $uiPollState.LastLoadingTick) -lt 200) { return }
            $uiPollState.LastLoadingTick = $now

            $elapsed = if ($ui.ExecuteStartTick -gt 0) {
                [int][Math]::Floor(($now - $ui.ExecuteStartTick) / 1000.0)
            }
            else { 0 }
            $null = & $fnUpdateLoading -Ui $ui -WingetOutputState $wingetOutputState -ElapsedSeconds $elapsed -GetI18n $fnGetI18n
            & $RedrawDepChrome
        }.GetNewClosure()

        $onStallNotify = {
            param($Info)
            if ($wingetOutputState['WingetOperationSucceeded']) { return }
            if ($wingetOutputState['InstallStarted'] -and $wingetOutputState['InstallerPromptDismissed']) {
                return
            }
            $now = [Environment]::TickCount
            if (($now - $stallNotifyState.LastTick) -lt 1000) { return }
            $stallNotifyState.LastTick = $now
            $idleSeconds = [string]$Info.ElapsedSeconds
            $stallLogAdded = $false
            if ($wingetOutputState['InstallerAwaitingDialog']) {
                $stallKey = if ([string]$wingetOutputState['ExecuteAction'] -eq 'Uninstall') {
                    'page.depOperation.statusUninstallPromptStall'
                }
                else {
                    'page.depOperation.statusInstallerPromptStall'
                }
                Set-ToolkitDepOperationInFlightStatus -Ui $ui -MainText (& $fnGetI18n -Key $stallKey) -AdvanceSpinner
                if (-not $stallNotifyState.Logged) {
                    $stallNotifyState.Logged = $true
                    $stallLogKey = if ([string]$wingetOutputState['ExecuteAction'] -eq 'Uninstall') {
                        'page.depOperation.logUninstallPromptStall'
                    }
                    else {
                        'page.depOperation.logInstallerPromptStall'
                    }
                    & $fnAddLog -Log $log -Text (& $fnGetI18n -Key $stallLogKey -Vars @{
                        seconds = $idleSeconds
                    }) -Kind 'heading' -WithTimestamp
                    $stallLogAdded = $true
                }
            }
            else {
                Set-ToolkitDepOperationInFlightStatus -Ui $ui -MainText (& $fnGetStatusText -PlanItem @{
                        Status = @{ Name = $ui.ProgressName }
                    } -Phase 'stall') -AdvanceSpinner
                if (-not $stallNotifyState.Logged) {
                    $stallNotifyState.Logged = $true
                    & $fnAddLog -Log $log -Text (& $fnGetI18n -Key 'page.depOperation.logStallWarn' -Vars @{
                        seconds = $idleSeconds
                    }) -Kind 'heading' -WithTimestamp
                    $stallLogAdded = $true
                }
            }
            if ($stallLogAdded) {
                & $invokeDepOperationRedrawNow
            }
            else {
                & $RedrawDepChrome
            }
        }.GetNewClosure()

        $resolveWingetStallPolicy = {
            param($Info)
            if ($wingetOutputState['WingetOperationSucceeded']) {
                return @{ Warn = $false; FailMs = 0 }
            }
            if ($wingetOutputState['InstallStarted'] -and $wingetOutputState['InstallerPromptDismissed']) {
                return @{ Warn = $true; FailMs = 180000 }
            }
            if ($wingetOutputState['InstallerAwaitingDialog'] -and -not [bool]$wingetOutputState['WingetInstallSilent']) {
                $promptMs = 0
                if ([int]$wingetOutputState['InstallerPromptStartTick'] -gt 0) {
                    $promptMs = [Environment]::TickCount - [int]$wingetOutputState['InstallerPromptStartTick']
                }
                if ($promptMs -ge [int]$wingetPolicy.InstallerPromptFailMs) {
                    return @{
                        Warn           = $true
                        FailMs         = 0
                        AbsoluteFail   = $true
                        TimedOutReason = 'installerPrompt'
                    }
                }
                if ($promptMs -ge [int]$wingetPolicy.InstallerPromptWarnMs) {
                    return @{ Warn = $true; FailMs = [int]$wingetPolicy.StallFailMs }
                }
                return @{ Warn = $false; FailMs = 0 }
            }
            return @{ Warn = $true; FailMs = [int]$wingetPolicy.StallFailMs }
        }.GetNewClosure()

        $onFileLockRetry = {
            param(
                [int]$Attempt = 1,
                [switch]$InteractiveFallback
            )

            $wingetAbortState.Requested = $false
            $wingetOutputState['FileLockErrorCount'] = 0
            $wingetOutputState['FileLockWarnLogged'] = $false
            $ui.ExecuteStartTick = [Environment]::TickCount
            $wingetOutputState['LastSubstantiveLineTick'] = $ui.ExecuteStartTick
            if ($InteractiveFallback) {
                $wingetOutputState['WingetInstallSilent'] = $false
                $wingetOutputState['InstallerAwaitingDialog'] = $false
                $wingetOutputState['InstallerPromptDismissed'] = $false
                $wingetOutputState['InstallerPromptStartTick'] = 0
                $wingetOutputState['InstallStarted'] = $false
                $wingetOutputState['InstallStartedTick'] = 0
                $wingetOutputState['LoggedPhases'] = @{}
                $wingetOutputState['MaxPhaseRank'] = 0
                $wingetOutputState['LastLoggedPercent'] = -1
                $wingetOutputState['PercentStage'] = ''
                $wingetOutputState['LoggedDownloadComplete'] = $false
                $wingetOutputState['LoggedInstallComplete'] = $false
                $stallNotifyState.Logged = $false
            }
        }.GetNewClosure()

        $runner = New-ToolkitDepOperationRunner -Tool $Tool -Plan $plan -Log $log `
            -OnProgress $onProgress -OnExitConfirmKey $onExitKey -ExitConfirmRef $exitConfirmRef `
            -OnOutputLine $onOutputLine -OnHeartbeat $onHeartbeat -OnUiPoll $onUiPoll `
            -OnStallNotify $onStallNotify -ResolveStallPolicy $resolveWingetStallPolicy `
            -OnBeforeExecute $onBeforeExecute -ShouldAbort $shouldAbortWinget -OnFileLockRetry $onFileLockRetry `
            -OnChromePulse $onChromePulse -OnDepLogChanged $onDepLogChanged
    }

    if ($plan -and -not $effectivePreflightKey) {
        Set-ToolkitShellToolbarLocked -Shell $Shell -Locked $true
        Start-ToolkitDepOperationBatch -Ui $ui
        & $invokeDepOperationRedrawNow
        foreach ($item in @($plan.Items)) {
            if ($runner.State.Cancelled) { break }
            if ($ui.ProgressCurrent -gt 0) {
                Add-ToolkitDepLogSeparator -Log $log
            }
            Add-ToolkitDepLogSection -Log $log -Title ([string]$item.Status.Name) `
                -Index ($ui.ProgressCurrent + 1) -Total $total -Level 'package'
            $ui.ProgressName = [string]$item.Status.Name
            Set-ToolkitDepOperationInFlightStatus -Ui $ui -MainText (& $fnGetStatusText -PlanItem $item -Phase 'detect')
            $ui.ItemInFlight = $true
            $ui.ItemSubPercent = -1
            $wingetOutputState['LastLoggedPercent'] = -1
            $wingetOutputState['LoggedPhases'] = @{}
            $wingetOutputState['LastSubstantiveLineTick'] = [Environment]::TickCount
            $wingetOutputState['LoggedWorking'] = $false
            $wingetOutputState['PercentStage'] = ''
            $wingetOutputState['LoggedDownloadComplete'] = $false
            $wingetOutputState['LoggedInstallComplete'] = $false
            $wingetOutputState['WingetOutputSeen'] = $false
            $wingetVerb = if ([string]$item.ExecuteAction -eq 'Upgrade') { 'upgrade' } else { 'install' }
            $wingetOutputState['WingetInstallSilent'] = & $fnTestWingetSilent -Package $item.Status.Package -Verb $wingetVerb
            $wingetOutputState['SubstantiveLogCount'] = 0
            $wingetOutputState['InstallerAwaitingDialog'] = $false
            $wingetOutputState['InstallerPromptDismissed'] = $false
            $wingetOutputState['InstallerPromptStartTick'] = 0
            $wingetOutputState['InstallStarted'] = $false
            $wingetOutputState['InstallStartedTick'] = 0
            $wingetOutputState['WingetOperationSucceeded'] = $false
            $wingetOutputState['FileLockErrorCount'] = 0
            $wingetOutputState['FileLockWarnLogged'] = $false
            $wingetOutputState['DeclineHandled'] = $false
            $wingetOutputState['ExecuteAction'] = [string]$item.ExecuteAction
            $wingetOutputState['PackageDisplayName'] = [string]$item.Status.Name
            $wingetOutputState['MaxPhaseRank'] = 0
            $wingetAbortState.Requested = $false
            $stallNotifyState.Logged = $false
            $ui.ExecuteStartTick = 0
            & $invokeDepOperationRedrawNow
            & $fnDrainEscInput -Shell $Shell -ProcessEsc $onExitKey
            if (-not (Resolve-ToolkitDepSharedUninstallConfirm -Tool $Tool -PlanItem $item -Log $log `
                    -Intent $Intent -Shell $Shell)) {
                Register-ToolkitDepRunnerItemResult -RunnerState $runner.State -Result 'success'
                if (-not $runner.State.Cancelled) {
                    Apply-ToolkitDepWingetProgressUpdate -Ui $ui -WingetOutputState $wingetOutputState -Target 100 -Jump
                    & $invokeDepOperationRedrawNow
                    $ui.ProgressCurrent++
                }
                $ui.ItemInFlight = $false
                $ui.ItemSubPercent = -1
                & $invokeDepOperationRedrawNow
                continue
            }
            & $runner.ProcessItem $item
            & $fnDrainEscInput -Shell $Shell -ProcessEsc $onExitKey
            if (-not $runner.State.Cancelled) {
                Apply-ToolkitDepWingetProgressUpdate -Ui $ui -WingetOutputState $wingetOutputState -Target 100 -Jump
                & $invokeDepOperationRedrawNow
                $ui.ProgressCurrent++
            }
            $ui.ItemInFlight = $false
            $ui.ItemSubPercent = -1
            & $invokeDepOperationRedrawNow
        }

        $runner.State.Failed = ([int]$runner.State.FailedCount -gt 0)

        $fnCompleteUninstall = Resolve-DepOperationFn 'Complete-ToolkitDepUninstallRecord'

        if ($Intent -eq 'uninstall') {
            if (Test-ToolkitDepRunnerSuccess -Runner $runner) {
                & $fnCompleteUninstall -Tool $Tool -Runner $runner
            }
        }
        elseif ([int]$runner.State.SuccessCount -gt 0) {
            $fnSyncDepState = Resolve-DepOperationFn 'Sync-ToolDepInstalledState'
            $null = & $fnSyncDepState -Tool $Tool
        }

        if (-not $runner.State.Cancelled) {
            Set-ToolkitDepOperationBatchCompleteUi -Ui $ui -Intent $Intent -TotalCount $total `
                -SuccessCount ([int]$runner.State.SuccessCount) -FailedCount ([int]$runner.State.FailedCount) `
                -ProgressCurrent $total
        }
        $complete = $true
        $log.AutoScroll = $false
        Set-ToolkitShellToolbarLocked -Shell $Shell -Locked $false
        & $invokeDepOperationRedrawNow
    }
    else {
        & $invokeDepOperationRedrawNow
    }

    if ($complete -and -not $AutoContinue) {
        $log.AutoScroll = $false
        & $fnDrainStaleInput
    }

    try {
        if ($AutoContinue -and $complete) {
            $Shell.Layout['BodyDirty'] = $true
            return (Test-ToolkitDepRunnerSuccess -Runner $runner)
        }

        $waitResult = Invoke-ToolkitDepBatchOperationWaitLoop -Context $ctx
        if (Test-ShellNavMarker $waitResult) {
            return $waitResult
        }
        if ($effectivePreflightKey) {
            return $false
        }
        return (Test-ToolkitDepRunnerSuccess -Runner $runner)
    }
    finally {
        Clear-ToolkitDepBatchOperationView -Context $ctx
    }
}

Register-DepOperationFnCache
