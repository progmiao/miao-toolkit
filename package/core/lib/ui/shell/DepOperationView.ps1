# 第三方依赖操作视图：进度条 + 状态行 + 可滚动日志

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
            'Format-ToolkitDepLogLineText'
            'Get-BrandSeparatorLineWidth'
            'Format-ToolkitShellContentSeparator'
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
            'Set-ToolDepPackageVersion'
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
            'Test-WingetDepResultNoApplicableInstaller'
            'Get-WingetDepResultSummaryLine'
            'Get-WingetDepStreamLinePercent'
            'Get-WingetDepStreamLinePhase'
            'Test-WingetDepStreamLineIsProgressVisual'
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
    $gapRow = [int]$Layout.GapRow
    $maxPaintRow = if ($gapRow -ge 0) { [Math]::Min($listEnd, $gapRow - 1) } else { $listEnd }

    $idealSeparatorRow = $listStart + 3
    $separatorRow = [Math]::Min($idealSeparatorRow, $maxPaintRow)
    if ($separatorRow -lt ($listStart + 2)) {
        $separatorRow = [Math]::Min($listStart + 2, $maxPaintRow)
    }

    $contentStartRow = $separatorRow + 1
    $contentViewportRows = 0
    if ($contentStartRow -le $maxPaintRow) {
        $contentViewportRows = $maxPaintRow - $contentStartRow + 1
    }

    return @{
        SeparatorRow          = $separatorRow
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
        return $inner
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

function Complete-ToolkitDepInstallerPromptPhase {
    param($OutputState)

    $OutputState['InstallerPromptDismissed'] = $true
    $OutputState['InstallerAwaitingDialog'] = $false
    $OutputState['InstallStarted'] = $true
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

    if ($WingetOutputState['InstallStarted'] -or $WingetOutputState['InstallerAwaitingDialog']) {
        $Ui.ItemSubPercent = -1
    }
    if ([int]$Ui.ItemSubPercent -ge 0 -and -not $WingetOutputState['InstallStarted'] `
            -and -not $WingetOutputState['InstallerAwaitingDialog'] `
            -and $WingetOutputState['WingetOutputSeen']) {
        return $false
    }

    $statusKey = 'page.depOperation.statusLoading'
    if ($WingetOutputState['InstallStarted'] -or $WingetOutputState['InstallerPromptDismissed']) {
        $statusKey = 'page.depOperation.statusInstallerRunning'
    }
    elseif ($WingetOutputState['InstallerAwaitingDialog']) {
        $statusKey = 'page.depOperation.statusInstallerPrompt'
    }
    elseif (-not $WingetOutputState['WingetOutputSeen']) {
        $statusKey = 'page.depOperation.statusWingetStarting'
    }

    $WingetOutputState['ElapsedSeconds'] = [int]$ElapsedSeconds
    $WingetOutputState['SpinnerIndex'] = [int]$WingetOutputState['SpinnerIndex'] + 1
    $spinner = $WingetOutputState['SpinnerFrames'][[int]$WingetOutputState['SpinnerIndex'] % 4]
    $Ui.StatusText = & $GetI18n -Key $statusKey -Vars @{
        spinner = $spinner
        elapsed = [string]$ElapsedSeconds
    }
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
        [ValidateSet('install', 'update', 'uninstall', 'init')]
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

function Get-ToolkitDepBatchSummarySegments {
    param(
        [ValidateSet('install', 'update', 'uninstall', 'init')]
        [string]$Intent,
        [int]$TotalCount,
        [int]$SuccessCount,
        [int]$FailedCount
    )

    if ($TotalCount -le 0) { $TotalCount = $SuccessCount + $FailedCount }
    if ($TotalCount -le 0) { return @() }

    $doneKey = switch ($Intent) {
        'install' { 'page.depOperation.summaryDoneInstall' }
        'update' { 'page.depOperation.summaryDoneUpdate' }
        'uninstall' { 'page.depOperation.summaryDoneUninstall' }
        'init' { 'page.depOperation.summaryDoneInit' }
        default { 'page.depOperation.summaryDoneInstall' }
    }
    $sep = Get-I18n -Key 'page.depOperation.summaryBatchSep'

    return @(
        @{ Text = (Get-I18n -Key $doneKey); Color = [System.ConsoleColor]::White }
        @{
            Text  = (Get-I18n -Key 'page.depOperation.summaryBatchTotal' -Vars @{ total = [string]$TotalCount })
            Color = [System.ConsoleColor]::Cyan
        }
        @{ Text = $sep; Color = [System.ConsoleColor]::White }
        @{
            Text  = (Get-I18n -Key 'page.depOperation.summaryBatchSuccess' -Vars @{ success = [string]$SuccessCount })
            Color = [System.ConsoleColor]::Green
        }
        @{ Text = $sep; Color = [System.ConsoleColor]::White }
        @{
            Text  = (Get-I18n -Key 'page.depOperation.summaryBatchFailed' -Vars @{ failed = [string]$FailedCount })
            Color = [System.ConsoleColor]::Red
        }
    )
}

function Write-ToolkitDepFixedLineSegments {
    param(
        [int]$Row,
        [array]$Segments,
        [switch]$LeadingSpace
    )

    if ($null -eq $Segments -or $Segments.Count -eq 0) { return }

    Prepare-ConsoleRowWrite -Row $Row
    try { [Console]::SetCursorPosition(0, $Row) } catch { return }

    $width = Get-SafeWriteLineWidth -Row $Row
    $used = 0
    if ($LeadingSpace -and $used -lt $width) {
        Write-Host ' ' -NoNewline
        $used++
    }

    foreach ($seg in $Segments) {
        if (-not $seg) { continue }
        if ($used -ge $width) { break }
        $partWidth = Get-DisplayWidth $seg.Text
        $remaining = $width - $used
        $text = if ($partWidth -gt $remaining) { Truncate-DisplayText $seg.Text $remaining } else { $seg.Text }
        if ([string]::IsNullOrEmpty($text)) { break }
        Write-Host $text -NoNewline -ForegroundColor $seg.Color
        $used += Get-DisplayWidth $text
    }

    if ($used -lt $width) {
        Write-Host (' ' * ($width - $used)) -NoNewline
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
            $fnFormatSep = Resolve-DepOperationFn 'Format-ToolkitShellContentSeparator'
            return & $fnFormatSep -BrandInnerWidth $BrandInnerWidth
        }
        return [string]$Line.Text
    }
    if ($Line.Kind -in @('hint', 'spacer')) {
        $fnPad = Resolve-DepOperationFn 'Pad-DisplayText'
        if ($BrandInnerWidth -gt 0) {
            $fnLineWidth = Resolve-DepOperationFn 'Get-BrandSeparatorLineWidth'
            $max = & $fnLineWidth -BrandInnerWidth $BrandInnerWidth
            return & $fnPad ([string]$Line.Text) $max
        }
        return [string]$Line.Text
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

function Format-ToolkitDepProgressBar {
    param(
        [int]$Current,
        [int]$Total,
        [string]$Name,
        [int]$BrandInnerWidth = 0,
        [int]$ItemSubPercent = -1
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

    $countText = "$Current/$Total"
    $suffix = " $countText  $Name"
    $suffixWidth = & $fnDisplayWidth $suffix
    $barInner = $inner - 2 - $suffixWidth
    if ($barInner -lt 1) {
        $fixedPart = " $countText  "
        $fixedWidth = 2 + (& $fnDisplayWidth $fixedPart)
        $nameMax = [Math]::Max(1, $inner - $fixedWidth - 2)
        $suffix = "$fixedPart$(& $fnTruncate $Name $nameMax)"
        $suffixWidth = & $fnDisplayWidth $suffix
        $barInner = [Math]::Max(1, $inner - 2 - $suffixWidth)
    }

    $effective = [double]$Current
    if ($ItemSubPercent -ge 0 -and $ItemSubPercent -le 100 -and $Current -lt $Total) {
        $effective = $Current + ($ItemSubPercent / 100.0)
    }

    $ratio = [Math]::Min(1.0, [Math]::Max(0.0, $effective / [double]$Total))
    $filled = [Math]::Min($barInner, [int][Math]::Round($ratio * $barInner))
    $bar = ('#' * $filled) + ('-' * [Math]::Max(0, $barInner - $filled))
    $content = & $fnPad "[$bar]$suffix" $inner
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
        LogText    = $null
        StatusText = $trim
        Percent    = -1
        RedrawOnly = $false
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
        Complete-ToolkitDepInstallerPromptPhase -OutputState $OutputState
        if (-not $OutputState.LoggedPhases.ContainsKey('verifyComplete')) {
            $OutputState.LoggedPhases['verifyComplete'] = $true
            $decision.LogText = & $fnGetI18n -Key 'page.depOperation.logVerifyComplete'
        }
        return $decision
    }

    $phaseOnce = @('found', 'startInstall', 'startUninstall', 'waitOther', 'download', 'verify', 'install', 'uninstall', 'installerPackage')
    if ($phase -in $phaseOnce -and -not $OutputState.LoggedPhases.ContainsKey($phase)) {
        $OutputState.LoggedPhases[$phase] = $true
        switch ($phase) {
            'startInstall' {
                Complete-ToolkitDepInstallerPromptPhase -OutputState $OutputState
                $decision.LogText = & $fnGetI18n -Key 'page.depOperation.logStartInstall'
            }
            'startUninstall' {
                Complete-ToolkitDepInstallerPromptPhase -OutputState $OutputState
                $decision.LogText = & $fnGetI18n -Key 'page.depOperation.logStartUninstall'
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
                Complete-ToolkitDepInstallerPromptPhase -OutputState $OutputState
                $OutputState.PercentStage = 'install'
                $decision.LogText = & $fnGetI18n -Key 'page.depOperation.logInstalling'
            }
            'uninstall' {
                $decision.LogText = & $fnGetI18n -Key 'page.depOperation.logUninstalling'
            }
            'installerPackage' {
                $OutputState['InstallStarted'] = $true
                if ($OutputState['InstallerPromptDismissed']) {
                    $OutputState['InstallerAwaitingDialog'] = $false
                }
                else {
                    $OutputState['InstallerAwaitingDialog'] = $true
                }
                if (-not $OutputState.LoggedPhases.ContainsKey('installerPackageLogged')) {
                    $OutputState.LoggedPhases['installerPackageLogged'] = $true
                    $decision.LogText = & $fnGetI18n -Key 'page.depOperation.logInstallerLaunched'
                }
            }
            default {
                $decision.LogText = $trim
            }
        }
    }

    if ($percent -ge 0) {
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
        $decision.LogText = $trim
    }
    elseif ($phase -eq 'info' -and -not $decision.LogText -and -not $isProgressVisual) {
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
        'skip' { return (Get-I18n -Key 'page.depOperation.statusSkip' -Vars @{ name = $name }) }
        'reconcile' { return (Get-I18n -Key 'page.depOperation.statusReconcile' -Vars @{ name = $name }) }
        'run' {
            return (Get-I18n -Key 'page.depOperation.statusAction' -Vars @{ name = $name; action = $action })
        }
        'done' { return (Get-I18n -Key 'page.depOperation.statusDone' -Vars @{ name = $name }) }
        'fail' { return (Get-I18n -Key 'page.depOperation.statusFail' -Vars @{ name = $name }) }
        'stall' {
            return (Get-I18n -Key 'page.depOperation.statusStallWarn' -Vars @{
                seconds = [string]$Command
            })
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
        Add-ToolkitDepLogLine -Log $Log -Text (Get-I18n -Key 'page.depOperation.logSkip' -Vars @{
            action = (Get-ToolkitDepActionLabel -Action ([string]$status.Action))
        }) -Kind 'success' -WithTimestamp
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
        [scriptblock]$OnBeforeExecute = $null
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

    $shouldCancel = {
        if ($ExitConfirmRef) { return [bool](& $ExitConfirmRef) }
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

        if ($executeAction -eq 'Reconcile') {
            if ($OnProgress) { & $OnProgress @{ Phase = 'reconcile'; Item = $PlanItem } }
            $version = [string]$status.EffectiveVersion
            if ([string]::IsNullOrWhiteSpace($version)) { $version = [string]$status.ActualVersion }
            if ([string]::IsNullOrWhiteSpace($version)) {
                $version = [string](& $fnRecordableVersion -Package $status.Package)
            }
            if (-not [string]::IsNullOrWhiteSpace($version)) {
                & $fnSetPkgVersion -ToolId ([string]$runnerState.Tool.id) `
                    -DependencyId ([string]$status.DependencyId) -Version $version
                & $fnAddLog -Log $runnerState.Log -Text (& $fnGetI18n -Key 'page.depOperation.logReconciled' -Vars @{
                    name = [string]$status.Name; version = $version
                }) -Kind 'success' -WithTimestamp
            }
            if ($OnProgress) { & $OnProgress @{ Phase = 'done'; Item = $PlanItem } }
            & $fnRegisterItemResult -RunnerState $runnerState -Result 'success'
            return
        }

        $wingetCommand = & $fnGetWingetCommand -Package $status.Package -ExecuteAction $executeAction
        if ($OnProgress) {
            & $OnProgress @{ Phase = 'run'; Item = $PlanItem; Command = [string]$wingetCommand }
        }
        if (-not [string]::IsNullOrWhiteSpace($wingetCommand)) {
            & $fnAddLog -Log $runnerState.Log -Text (& $fnGetI18n -Key 'page.depOperation.logInvokeWinget' -Vars @{
                command = $wingetCommand
            }) -WithTimestamp
            & $fnAddLog -Log $runnerState.Log -Text (& $fnGetI18n -Key 'page.depOperation.logMayPrompt') -Kind 'heading' -WithTimestamp
            & $fnAddLog -Log $runnerState.Log -Text (& $fnGetI18n -Key 'page.depOperation.logWingetStarting') -WithTimestamp
        }

        if ($OnBeforeExecute) { & $OnBeforeExecute }
        if ($OnUiPoll) { & $OnUiPoll }

        $result = & $fnExecutePackage -Package $status.Package -ExecuteAction $executeAction `
            -ShouldCancel $shouldCancel -OnExitConfirmKey $OnExitConfirmKey -OnOutputLine $OnOutputLine `
            -OnHeartbeat $OnHeartbeat -OnUiPoll $OnUiPoll -OnStallNotify $OnStallNotify `
            -ResolveStallPolicy $ResolveStallPolicy

        if ($OnProgress -and $result.Command) {
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

        if ($result.TimedOut) {
            if ($OnProgress) { & $OnProgress @{ Phase = 'fail'; Item = $PlanItem } }
            & $fnAddLog -Log $runnerState.Log -Text (& $fnGetI18n -Key 'page.depOperation.logStallTimeout') `
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
                        -DependencyId ([string]$depId) -Version ([string]$versions[$depId])
                }
            }
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
        [int]$LogContentViewportRows
    )

    if ($null -eq $Log) { return }

    $fnWriteFixed = Resolve-DepOperationFn 'Write-FixedLine'
    $fnFormatSep = Resolve-DepOperationFn 'Format-ToolkitShellContentSeparator'
    $fnFormatLogLine = Resolve-DepOperationFn 'Format-ToolkitDepLogLineText'

    $layout = $Shell.Layout
    $barWidth = if ([int]$Log.BrandInnerWidth -gt 0) { [int]$Log.BrandInnerWidth } else {
        if ($Shell.BrandInnerWidth -gt 0) { [int]$Shell.BrandInnerWidth } else { [int]$layout.BrandInnerWidth }
    }

    $separatorText = & $fnFormatSep -BrandInnerWidth $barWidth
    & $fnWriteFixed $LogSeparatorRow $separatorText -Color DarkGray

    $layoutMetrics = Get-ToolkitDepOperationLogLayout -Layout $layout
    $maxPaintRow = [int]$layoutMetrics.MaxPaintRow
    if ($LogContentViewportRows -le 0) { return }

    $logLines = Get-ToolkitDepOperationLogLines -Log $Log
    $lineCount = if ($logLines) { [int]$logLines.Count } else { 0 }

    $maxScroll = [Math]::Max(0, $lineCount - $LogContentViewportRows)
    if ($Log.ScrollOffset -gt $maxScroll) { $Log.ScrollOffset = $maxScroll }

    $contentStartRow = $LogSeparatorRow + 1
    for ($row = 0; $row -lt $LogContentViewportRows; $row++) {
        $idx = $Log.ScrollOffset + $row
        $screenRow = $contentStartRow + $row
        if ($screenRow -gt $maxPaintRow) {
            break
        }
        if ($idx -ge 0 -and $idx -lt $lineCount) {
            $line = $logLines[$idx]
            $prefix = if ($line.Kind -eq 'separator') { '' } else { ' ' }
            & $fnWriteFixed $screenRow "$prefix$(& $fnFormatLogLine -Line $line -BrandInnerWidth $barWidth)" -Color $line.Color
        }
        else {
            & $fnWriteFixed $screenRow '' -Color DarkGray
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
        [int]$LogViewportRows,
        [int]$LogStartRow,
        [int]$ProgressItemSubPercent = -1,
        [switch]$StatusPlain,
        [array]$StatusSegments = $null
    )

    $fnWriteFixed = Resolve-DepOperationFn 'Write-FixedLine'
    $fnGetI18n = Resolve-DepOperationFn 'Get-I18n'
    $fnFormatBar = Resolve-DepOperationFn 'Format-ToolkitDepProgressBar'
    $fnMaxScroll = Resolve-DepOperationFn 'Get-ToolkitDepLogMaxScroll'
    $fnFormatLogLine = Resolve-DepOperationFn 'Format-ToolkitDepLogLineText'

    $layout = $Shell.Layout
    $barWidth = if ($Shell.BrandInnerWidth -gt 0) { $Shell.BrandInnerWidth } else { $layout.BrandInnerWidth }
    & $fnWriteFixed $layout.ListStartRow (& $fnFormatBar -Current $ProgressCurrent `
        -Total $ProgressTotal -Name $ProgressName -BrandInnerWidth $barWidth `
        -ItemSubPercent $ProgressItemSubPercent) -Color Cyan

    if ($StatusSegments -and $StatusSegments.Count -gt 0) {
        Write-ToolkitDepFixedLineSegments -Row ($layout.ListStartRow + 1) -Segments $StatusSegments -LeadingSpace
    }
    elseif ($StatusPlain) {
        & $fnWriteFixed ($layout.ListStartRow + 1) " $StatusText" -Color White
    }
    else {
        $statusLine = " $(& $fnGetI18n -Key 'page.depOperation.currentPrefix')$StatusText"
        & $fnWriteFixed ($layout.ListStartRow + 1) $statusLine -Color White
    }
    & $fnWriteFixed ($layout.ListStartRow + 2) '' -Color DarkGray

    if ($LogViewportRows -le 0) {
        if ($layout.GapRow -ge 0) {
            & $fnWriteFixed $layout.GapRow '' -Color DarkGray
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
            & $fnWriteFixed $screenRow "$prefix$(& $fnFormatLogLine -Line $line -BrandInnerWidth $barWidth)" -Color $line.Color
        }
        else {
            & $fnWriteFixed $screenRow '' -Color DarkGray
        }
    }

    if ($layout.GapRow -ge 0) {
        & $fnWriteFixed $layout.GapRow '' -Color DarkGray
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
        $SharedLog = $null
    )

    $toolbar = New-ShellSystemToolbarConfig -HideSystem -HideHelp
    $renderFooter = New-ShellSystemToolbarFooterRenderer -Shell $Shell -ToolbarConfig $toolbar
    Register-ToolkitShellFooter -Shell $Shell -Renderer $renderFooter

    Initialize-ToolkitShellBodyView -Shell $Shell -SectionTitle $SectionTitle `
        -FooterTemplate SystemToolbarOnly

    $layout = $Shell.Layout
    $logLayout = Get-ToolkitDepOperationLogLayout -Layout $layout
    $logSeparatorRow = [int]$logLayout.SeparatorRow
    $logContentViewportRows = [int]$logLayout.ContentViewportRows

    $log = if ($SharedLog) { $SharedLog } else { New-ToolkitDepOperationLog }
    $contentMetrics = if ($Shell.Layout.ContentMetrics) { $Shell.Layout.ContentMetrics } else {
        Sync-ToolkitShellContentMetrics -Shell $Shell
    }
    $barWidth = [int]$contentMetrics.InnerWidth
    $log.BrandInnerWidth = $barWidth
    $log.ViewportRows = $logContentViewportRows

    $fnGetI18n = Resolve-DepOperationFn 'Get-I18n'

    $plan = if ([string]::IsNullOrWhiteSpace($PreflightErrorKey)) {
        Build-ToolDepSyncPlan -Tool $Tool -Intent $Intent
    }
    else { $null }

    $total = if ($plan) { @($plan.Items).Count } else { 1 }

    $ui = @{
        ProgressCurrent  = 0
        ItemInFlight     = $false
        ItemSubPercent   = -1
        ProgressName     = ''
        StatusText       = (& $fnGetI18n -Key 'page.depOperation.statusReady')
        StatusPlain      = $false
        StatusSegments   = $null
        ExecuteStartTick = 0
    }
    $complete = $false
    $exitConfirmArmed = $false
    $runner = $null

    if ($PreflightErrorKey) {
        Add-ToolkitDepLogLine -Log $log -Text (& $fnGetI18n -Key $PreflightErrorKey) -Kind 'error' -WithTimestamp
        $complete = $true
    }
    $exitConfirmRef = { return [bool]$exitConfirmArmed }.GetNewClosure()

    $fnRegisterExitExtension = Resolve-DepOperationFn 'Register-ShellExitExtension'
    $fnClearExitExtension = Resolve-DepOperationFn 'Clear-ShellExitExtension'
    $fnProcessEscInput = Resolve-DepOperationFn 'Process-ShellEscInputIfAvailable'
    $fnDrainEscInput = Resolve-DepOperationFn 'Drain-ConsoleEscInputIfAvailable'
    $fnDrainStaleInput = Resolve-DepOperationFn 'Drain-ConsoleStaleToolbarInput'
    $fnReadExitIfActive = Resolve-DepOperationFn 'Read-ShellExitIfActive'
    $fnEnterBatch = Resolve-DepOperationFn 'Enter-ConsoleDrawBatch'
    $fnCompleteBatch = Resolve-DepOperationFn 'Complete-ConsoleDrawBatch'
    $fnDrawView = Resolve-DepOperationFn 'Draw-ToolkitDepOperationView'
    $fnDrawLogViewport = Resolve-DepOperationFn 'Draw-ToolkitDepOperationLogViewport'

    $onExitConfirmed = { $exitConfirmArmed = $true }.GetNewClosure()
    & $fnRegisterExitExtension -Shell $Shell -OnExitConfirmed $onExitConfirmed

    $onExitKey = {
        $null = & $fnProcessEscInput -Shell $Shell
    }.GetNewClosure()

    $RedrawDepOperationView = {
        $itemSubPercent = if ($ui.ItemInFlight) { [int]$ui.ItemSubPercent } else { -1 }
        $statusSegments = if ($ui.StatusSegments) { @($ui.StatusSegments) } else { $null }
        & $fnEnterBatch
        & $fnDrawView -Shell $Shell -Log $log -ProgressCurrent $ui.ProgressCurrent `
            -ProgressTotal $total -ProgressName $ui.ProgressName -StatusText $ui.StatusText `
            -LogViewportRows 0 -LogStartRow $logSeparatorRow `
            -ProgressItemSubPercent $itemSubPercent -StatusPlain:([bool]$ui.StatusPlain) `
            -StatusSegments $statusSegments
        & $fnDrawLogViewport -Shell $Shell -Log $log `
            -LogSeparatorRow $logSeparatorRow -LogContentViewportRows $logContentViewportRows
        Invoke-ToolkitShellRegisteredFooter -Shell $Shell
        & $fnCompleteBatch -ToolkitShell $Shell
    }.GetNewClosure()

    $fnGetStatusText = Resolve-DepOperationFn 'Get-ToolkitDepStatusText'
    $fnAddLog = Resolve-DepOperationFn 'Add-ToolkitDepLogLine'
    $redrawState = @{ LastRedrawTick = 0; Pending = $false }

    $invokeDepOperationRedrawNow = {
        $redrawState.LastRedrawTick = [Environment]::TickCount
        $redrawState.Pending = $false
        & $RedrawDepOperationView
    }.GetNewClosure()

    $uiPollState = @{
        LastLoadingTick     = 0
        LastScrollTick      = 0
        MinScrollIntervalMs = 55
    }
    $fnLogInput = Resolve-DepOperationFn 'Invoke-ToolkitDepLogInputIfAvailable'

    $requestDepOperationRedraw = {
        $now = [Environment]::TickCount
        if (($now - $redrawState.LastRedrawTick) -ge 200) {
            & $invokeDepOperationRedrawNow
        }
        else {
            $redrawState.Pending = $true
        }
    }.GetNewClosure()

    if ($plan) {
        $onProgress = {
            param($Info)
            $ui.ProgressName = [string]$Info.Item.Status.Name
            $ui.StatusText = & $fnGetStatusText -PlanItem $Info.Item -Phase ([string]$Info.Phase) `
                -Command ([string]$Info.Command)
            & $invokeDepOperationRedrawNow
        }.GetNewClosure()

        $fnGetOutputDecision = Resolve-DepOperationFn 'Get-ToolkitDepWingetOutputDecision'
        $fnUpdateLoading = Resolve-DepOperationFn 'Update-ToolkitDepLoadingStatus'
        $wingetOutputState = @{
            LastLoggedPercent       = -1
            LoggedPhases            = @{}
            LastSubstantiveLineTick = [Environment]::TickCount
            ElapsedSeconds          = 0
            SpinnerFrames           = @('|', '/', '-', '\')
            SpinnerIndex            = 0
            LoggedWorking           = $false
            PercentStage            = ''
            LoggedDownloadComplete  = $false
            LoggedInstallComplete   = $false
            WingetOutputSeen        = $false
            InstallerAwaitingDialog = $false
            InstallerPromptDismissed  = $false
            InstallStarted          = $false
        }

        $onBeforeExecute = {
            $ui.ExecuteStartTick = [Environment]::TickCount
            $wingetOutputState['LastSubstantiveLineTick'] = $ui.ExecuteStartTick
            $null = & $fnUpdateLoading -Ui $ui -WingetOutputState $wingetOutputState -ElapsedSeconds 0 -GetI18n $fnGetI18n
            & $invokeDepOperationRedrawNow
        }.GetNewClosure()

        $fnCleanLine = Resolve-DepOperationFn 'Get-WingetStreamLineCleanText'
        $fnIsSpinner = Resolve-DepOperationFn 'Test-WingetStreamLineIsSpinnerOnly'
        $fnIsProgressVisual = Resolve-DepOperationFn 'Test-WingetDepStreamLineIsProgressVisual'

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

        $stallNotifyState = @{ LastTick = 0; Logged = $false }

        $onOutputLine = {
            param($Line)
            $raw = & $fnCleanLine -Line $Line
            if ([string]::IsNullOrWhiteSpace($raw)) { return }

            if ((& $fnIsSpinner -Line $raw) -or (& $fnIsProgressVisual -Line $raw)) {
                $wingetOutputState['WingetOutputSeen'] = $true
                & $refreshDepLoadingStatus
                & $invokeDepOperationRedrawNow
                return
            }

            $wingetOutputState['WingetOutputSeen'] = $true
            $decision = & $fnGetOutputDecision -Line $Line -OutputState $wingetOutputState
            $substantive = (-not [string]::IsNullOrWhiteSpace([string]$decision.LogText)) `
                -or ((-not $decision.RedrawOnly) -and (-not [string]::IsNullOrWhiteSpace([string]$decision.StatusText)))
            if ($substantive) {
                $wingetOutputState['LastSubstantiveLineTick'] = [Environment]::TickCount
                $stallNotifyState.Logged = $false
            }

            if ($decision.Percent -gt 0) {
                $ui.ItemSubPercent = [int]$decision.Percent
            }
            if ($decision.StatusText -and -not $decision.RedrawOnly) {
                $ui.StatusText = [string]$decision.StatusText
            }
            if ($decision.LogText -and -not $decision.RedrawOnly) {
                $logText = [string]$decision.LogText
                $skipSpinner = (& $fnIsSpinner -Line $raw) -and ($logText -eq $raw)
                if (-not $skipSpinner) {
                    & $fnAddLog -Log $log -Text $logText -WithTimestamp
                }
            }
            if ($decision.RedrawOnly) {
                & $refreshDepLoadingStatus
            }
            & $invokeDepOperationRedrawNow
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
            }
            & $invokeDepOperationRedrawNow
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
            & $invokeDepOperationRedrawNow
        }.GetNewClosure()

        $onStallNotify = {
            param($Info)
            if ($wingetOutputState['InstallStarted'] -or $wingetOutputState['InstallerAwaitingDialog']) {
                return
            }
            $now = [Environment]::TickCount
            if (($now - $stallNotifyState.LastTick) -lt 1000) { return }
            $stallNotifyState.LastTick = $now
            $seconds = [string]$Info.ElapsedSeconds
            $ui.StatusText = & $fnGetStatusText -PlanItem @{ Status = @{ Name = $ui.ProgressName } } `
                -Phase 'stall' -Command $seconds
            if (-not $stallNotifyState.Logged) {
                $stallNotifyState.Logged = $true
                & $fnAddLog -Log $log -Text (& $fnGetI18n -Key 'page.depOperation.logStallWarn' -Vars @{
                    seconds = $seconds
                }) -Kind 'heading' -WithTimestamp
            }
            & $invokeDepOperationRedrawNow
        }.GetNewClosure()

        $resolveWingetStallPolicy = {
            param($Info)
            if ($wingetOutputState['InstallStarted'] -or $wingetOutputState['InstallerAwaitingDialog']) {
                return @{ Warn = $false; FailMs = 0 }
            }
            return @{ Warn = $true; FailMs = 90000 }
        }.GetNewClosure()

        $runner = New-ToolkitDepOperationRunner -Tool $Tool -Plan $plan -Log $log `
            -OnProgress $onProgress -OnExitConfirmKey $onExitKey -ExitConfirmRef $exitConfirmRef `
            -OnOutputLine $onOutputLine -OnHeartbeat $onHeartbeat -OnUiPoll $onUiPoll `
            -OnStallNotify $onStallNotify -ResolveStallPolicy $resolveWingetStallPolicy `
            -OnBeforeExecute $onBeforeExecute
    }

    if ($plan -and -not $PreflightErrorKey) {
        Set-ToolkitShellToolbarLocked -Shell $Shell -Locked $true
        foreach ($item in @($plan.Items)) {
            if ($runner.State.Cancelled) { break }
            if ($ui.ProgressCurrent -gt 0) {
                Add-ToolkitDepLogSeparator -Log $log
            }
            Add-ToolkitDepLogSection -Log $log -Title ([string]$item.Status.Name) `
                -Index ($ui.ProgressCurrent + 1) -Total $total -Level 'package'
            $ui.ProgressName = [string]$item.Status.Name
            $ui.StatusText = & $fnGetStatusText -PlanItem $item -Phase 'detect'
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
            $wingetOutputState['InstallerAwaitingDialog'] = $false
            $wingetOutputState['InstallerPromptDismissed'] = $false
            $wingetOutputState['InstallStarted'] = $false
            $ui.ExecuteStartTick = 0
            $stallNotifyState.Logged = $false
            & $invokeDepOperationRedrawNow
            & $fnDrainEscInput -Shell $Shell -ProcessEsc $onExitKey
            & $runner.ProcessItem $item
            & $fnDrainEscInput -Shell $Shell -ProcessEsc $onExitKey
            $ui.ItemInFlight = $false
            $ui.ItemSubPercent = -1
            if (-not $runner.State.Cancelled) {
                $ui.ProgressCurrent++
            }
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
            $ui.ProgressCurrent = $total
            $ui.StatusPlain = $true
            $ui.StatusText = ''
            $ui.StatusSegments = Get-ToolkitDepBatchSummarySegments -Intent $Intent `
                -TotalCount $total -SuccessCount ([int]$runner.State.SuccessCount) `
                -FailedCount ([int]$runner.State.FailedCount)
        }
        $complete = $true
        $log.AutoScroll = $false
        Set-ToolkitShellToolbarLocked -Shell $Shell -Locked $false
        & $invokeDepOperationRedrawNow
    }
    else {
        & $RedrawDepOperationView
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

        & $invokeDepOperationRedrawNow
        while ($true) {
            $exitResult = & $fnReadExitIfActive -Shell $Shell
            if ($null -ne $exitResult) {
                if ($exitResult -eq 'exitConfirmed') {
                    return (Get-ShellNavMarker -Action 'quit')
                }
                & $invokeDepOperationRedrawNow
                continue
            }

            if (Test-ConsoleKeyAvailable) {
                $fnPeekKey = Resolve-DepOperationFn 'Get-ConsoleVirtualKeyPeek'
                $peek = & $fnPeekKey
                if ($peek -in @('UpArrow', 'DownArrow', 'Escape')) {
                    $scrollInput = & $fnLogInput -Shell $Shell -Log $log `
                        -ViewportRows $logContentViewportRows -OnExitKey $onExitKey -ScrollState $uiPollState
                    if ($scrollInput -eq 'scroll') {
                        $maxScroll = Get-ToolkitDepLogMaxScroll -Log $log -ViewportRows $logContentViewportRows
                        $log.AutoScroll = ([int]$log.ScrollOffset -ge $maxScroll)
                        & $invokeDepOperationRedrawNow
                    }
                    elseif ($scrollInput -eq 'exit') {
                        & $invokeDepOperationRedrawNow
                    }
                    continue
                }

                if ($complete -and -not (Test-ToolkitShellToolbarLocked -Shell $Shell)) {
                    Prepare-ToolkitShellBodyDraw -Shell $Shell
                    $key = [Console]::ReadKey($true)
                    Set-CursorVisible $false
                    if ($key.KeyChar -match '^[qQ]$') {
                        $Shell.Layout['BodyDirty'] = $true
                        return (Test-ToolkitDepRunnerSuccess -Runner $runner)
                    }
                    if ($key.Key -eq 'Escape') {
                        $null = & $onExitKey
                        & $invokeDepOperationRedrawNow
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

Register-DepOperationFnCache
