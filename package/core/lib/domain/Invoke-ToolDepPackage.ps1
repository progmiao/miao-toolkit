# 单包第三方依赖执行（winget 等）

function Test-ToolDepCommandAvailable {
    param([string]$CheckCommand)

    if ([string]::IsNullOrWhiteSpace($CheckCommand)) { return $false }
    $exe = ($CheckCommand -split '\s+', 2)[0]
    return [bool](Get-Command $exe -ErrorAction SilentlyContinue)
}

function Resolve-ToolDepCheckCommandVersion {
    param([string]$CheckCommand)

    if ([string]::IsNullOrWhiteSpace($CheckCommand)) { return $null }
    if (-not (Test-ToolDepCommandAvailable -CheckCommand $CheckCommand)) { return $null }

    try {
        $parts = $CheckCommand -split '\s+', 2
        $exe = $parts[0]
        $args = @()
        if ($parts.Count -gt 1 -and -not [string]::IsNullOrWhiteSpace($parts[1])) {
            $args = @($parts[1] -split '\s+')
        }
        $output = & $exe @args 2>&1 | Out-String
        $line = @($output -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -First 1)
        if ([string]::IsNullOrWhiteSpace($line)) { return $null }
        return [string]$line
    }
    catch {
        return $null
    }
}

function Test-WingetCliAvailable {
    return [bool](Get-Command winget -ErrorAction SilentlyContinue)
}

function Update-ToolDepSessionPath {
    $machine = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [System.Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machine;$user"
}

function Resolve-ToolDepPackageVersionAfterAction {
    param(
        $Package
    )

    $depId = Get-DependencyRecordId -Dependency $Package
    $version = $null

    if ($Package.install -and $Package.install.packageId) {
        $version = Get-WingetPackageInstalledVersion -PackageId ([string]$Package.install.packageId)
    }

    if ([string]::IsNullOrWhiteSpace($version)) {
        $policy = (Get-DependencyVersionPolicy -Dependency $Package).Trim()
        if ($policy -and ($policy.ToLowerInvariant() -ne 'latest')) {
            $version = $policy
        }
    }

    if ([string]::IsNullOrWhiteSpace($version)) { return $null }
    return @{ $depId = [string]$version }
}

function Split-ProcessOutputLines {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
    return @($Text -split "`r?`n" | ForEach-Object { $_.TrimEnd() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Test-WingetDepStreamLineIsProgressVisual {
    param([string]$Line)

    $trim = Get-WingetStreamLineCleanText -Line $Line
    if ([string]::IsNullOrWhiteSpace($trim)) { return $false }
    if ($trim -match '[\u2580-\u259F]') { return $true }
    return $false
}

function Test-WingetStreamLineUseful {
    param([string]$Line)

    if ([string]::IsNullOrWhiteSpace($Line)) { return $false }
    $trim = $Line.Trim()
    if ($trim.Length -eq 0) { return $false }
    if (Test-WingetDepStreamLineIsProgressVisual -Line $trim) { return $false }
    if ($trim -match '^[\|\\/\-\s]+$') { return $false }
    if ($trim -match '^[\u2588\s]+$') { return $false }
    if ($trim -match '^(Windows 程序包管理器|Windows Package Manager|版权所有|Copyright \(C\)|保留所有权利|All rights reserved)') {
        return $false
    }
    if ($trim -match '^(Usage:|usage:|各命令|命令语法)') { return $false }
    return $true
}

function Get-WingetStreamLineCleanText {
    param([string]$Line)

    if ([string]::IsNullOrWhiteSpace($Line)) { return '' }
    $trim = [string]$Line.Trim()
    $trim = $trim -replace '\x1b\[[0-9;?]*[ -/]*[@-~]', ''
    $trim = $trim -replace '\x1b\].*?\x07', ''
    $trim = $trim -replace '^\r+|\r+$', ''
    return [string]$trim.Trim()
}

function Test-WingetStreamLineIsSpinnerOnly {
    param([string]$Line)

    $trim = Get-WingetStreamLineCleanText -Line $Line
    if ([string]::IsNullOrWhiteSpace($trim)) { return $false }
    return [bool]($trim -match '^[\|\\/\-\s]+$')
}

function Get-WingetDepStreamLinePercent {
    param([string]$Line)

    if ([string]::IsNullOrWhiteSpace($Line)) { return -1 }
    $trim = [string]$Line.Trim()

    if ($trim -match '(\d+)\s*%') {
        return [Math]::Max(0, [Math]::Min(100, [int]$Matches[1]))
    }

    if ($trim -match '(\d+(?:\.\d+)?)\s*(KB|MB|GB)\s*/\s*(\d+(?:\.\d+)?)\s*(KB|MB|GB)') {
        $cur = [double]$Matches[1]
        $total = [double]$Matches[3]
        $u1 = [string]$Matches[2].ToUpperInvariant()
        $u2 = [string]$Matches[4].ToUpperInvariant()
        if ($total -gt 0 -and $u1 -eq $u2) {
            return [Math]::Max(0, [Math]::Min(100, [int][Math]::Round(($cur / $total) * 100.0)))
        }
    }

    return -1
}

function New-WingetDepAsyncStreamCollector {
    return @{
        Queue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
        Ended = $false
    }
}

function Register-WingetDepAsyncStreamCollector {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$EventName,
        $Collector
    )

    return Register-ObjectEvent -InputObject $Process -EventName $EventName -Action {
        if ($null -ne $EventArgs.Data) {
            [void]$Event.MessageData.Queue.Enqueue([string]$EventArgs.Data)
        }
        else {
            $Event.MessageData.Ended = $true
        }
    } -MessageData $Collector
}

function Get-WingetDepAsyncStreamLines {
    param($Collector)

    $lines = New-Object 'System.Collections.Generic.List[string]'
    $item = $null
    while ($Collector.Queue.TryDequeue([ref]$item)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$item)) {
            [void]$lines.Add([string]$item)
        }
    }
    return @($lines.ToArray())
}

function Unregister-WingetDepAsyncStreamCollector {
    param($Subscription)

    if (-not $Subscription) { return }
    try {
        Unregister-Event -SourceIdentifier $Subscription.Name -ErrorAction Stop
        Remove-Job -Id $Subscription.Id -Force -ErrorAction Stop
    }
    catch {}
}

function Get-WingetDepZhStreamPhrases {
    if ($null -ne $script:WingetDepZhStreamPhrases) {
        return $script:WingetDepZhStreamPhrases
    }

    $path = Join-Path $PSScriptRoot '..\..\i18n\zh.json'
    if (-not (Test-Path -LiteralPath $path)) {
        $script:WingetDepZhStreamPhrases = @{}
        return $script:WingetDepZhStreamPhrases
    }

    try {
        $doc = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        $script:WingetDepZhStreamPhrases = $doc.page.depOperation.wingetStreamPhrases
    }
    catch {
        $script:WingetDepZhStreamPhrases = @{}
    }

    return $script:WingetDepZhStreamPhrases
}

function Test-WingetDepZhStreamPhrase {
    param(
        [string]$Text,
        [string]$Key
    )

    $phrases = Get-WingetDepZhStreamPhrases
    if (-not $phrases) { return $false }
    $phrase = [string]$phrases.$Key
    if ([string]::IsNullOrWhiteSpace($phrase)) { return $false }
    return $Text.Contains($phrase)
}

function Get-WingetDepStreamLinePhase {
    param([string]$Line)

    if ([string]::IsNullOrWhiteSpace($Line)) { return 'empty' }
    $trim = Get-WingetStreamLineCleanText -Line $Line

    if (Test-WingetStreamLineIsSpinnerOnly -Line $trim) { return 'spinner' }
    if (Test-WingetDepStreamLineIsProgressVisual -Line $trim) { return 'progress' }
    if ($trim -match '^Found\s+\S') { return 'found' }
    if ($trim -match '^Starting package install') { return 'startInstall' }
    if ($trim -match '^Starting package uninstall') { return 'startUninstall' }
    if ($trim -match '^Waiting for another') { return 'waitOther' }
    if ($trim -match '^Downloading') { return 'download' }
    if ($trim -match '^Verifying') { return 'verify' }
    if ($trim -match '^Successfully verified') { return 'verify' }
    if ($trim -match '^Installing\b') { return 'install' }
    if ($trim -match '^Uninstalling') { return 'uninstall' }
    if (Test-WingetDepZhStreamPhrase $trim 'found') { return 'found' }
    if (Test-WingetDepZhStreamPhrase $trim 'startInstall') { return 'startInstall' }
    if (Test-WingetDepZhStreamPhrase $trim 'startUninstall') { return 'startUninstall' }
    if (Test-WingetDepZhStreamPhrase $trim 'waitOther') {
        if ((Test-WingetDepZhStreamPhrase $trim 'install') -or (Test-WingetDepZhStreamPhrase $trim 'uninstall')) {
            return 'waitOther'
        }
    }
    if (Test-WingetDepZhStreamPhrase $trim 'download') { return 'download' }
    if ((Test-WingetDepZhStreamPhrase $trim 'verify') -or (Test-WingetDepZhStreamPhrase $trim 'verified') `
            -or (Test-WingetDepZhStreamPhrase $trim 'verifyOk')) {
        return 'verify'
    }
    if (Test-WingetDepZhStreamPhrase $trim 'install') { return 'install' }
    if (Test-WingetDepZhStreamPhrase $trim 'uninstall') { return 'uninstall' }
    if ($trim -match '\.msi\b|\.exe\b') { return 'installerPackage' }
    if ((Get-WingetDepStreamLinePercent -Line $trim) -ge 0) { return 'progress' }
    if (Test-WingetStreamLineIsImportant -Line $trim) { return 'result' }
    if (Test-WingetStreamLineUseful -Line $trim) { return 'info' }

    return 'other'
}

function Test-WingetDepStreamLineIsDeclined {
    param([string]$Line)

    $trim = Get-WingetStreamLineCleanText -Line $Line
    if ([string]::IsNullOrWhiteSpace($trim)) { return $false }

    if ($trim -match 'access\s+denied|拒绝访问|requires elevation|需要提升|UAC|用户拒绝') {
        return $true
    }
    if ($trim -match 'cancelled|canceled|已取消|用户取消|operation was cancelled|Operation cancelled') {
        return $true
    }
    if ($trim -match 'The operation was canceled by the user') {
        return $true
    }
    if ($trim -match '退出代码为:\s*160[23]|exit code.*160[23]|exit code is:\s*160[23]') {
        return $true
    }
    if ($trim -match '(安装失败|Install failed|卸载失败|Uninstall failed).*(1602|1603)|(1602|1603).*(安装失败|Install failed|卸载失败|Uninstall failed)') {
        return $true
    }

    $phrases = Get-WingetDepZhStreamPhrases
    if ($phrases) {
        foreach ($key in @('uacDeclined', 'userCancelled')) {
            $phrase = [string]$phrases.$key
            if (-not [string]::IsNullOrWhiteSpace($phrase) -and $trim.Contains($phrase)) {
                return $true
            }
        }
    }

    return $false
}

function Test-WingetDepStreamLineIsEphemeral {
    param([string]$Line)

    if ([string]::IsNullOrWhiteSpace($Line)) { return $true }
    $phase = Get-WingetDepStreamLinePhase -Line $Line
    return ($phase -in @('spinner', 'download', 'verify', 'install', 'uninstall', 'progress', 'waitOther'))
}

function New-WingetStreamLineBuffer {
    return [System.Text.StringBuilder]::new()
}

function Read-WingetStreamAvailableLines {
    param(
        [System.IO.StreamReader]$Reader,
        [System.Text.StringBuilder]$Buffer
    )

    if (-not $Reader -or $null -eq $Buffer) { return @() }

    $completed = New-Object 'System.Collections.Generic.List[string]'
    try {
        while ($Reader.Peek() -ge 0) {
            $ch = $Reader.Read()
            if ($ch -lt 0) { break }

            if ($ch -eq 10 -or $ch -eq 13) {
                $text = $Buffer.ToString().Trim()
                $null = $Buffer.Clear()
                if ($text) { [void]$completed.Add($text) }
                continue
            }

            [void]$Buffer.Append([char]$ch)
        }
    }
    catch {}

    return @($completed.ToArray())
}

function Complete-WingetStreamLineBuffer {
    param([System.Text.StringBuilder]$Buffer)

    if ($null -eq $Buffer) { return @() }
    $text = $Buffer.ToString().Trim()
    $null = $Buffer.Clear()
    if ([string]::IsNullOrWhiteSpace($text)) { return @() }
    return @($text)
}

function Test-WingetStreamLineIsImportant {
    param([string]$Line)

    if ([string]::IsNullOrWhiteSpace($Line)) { return $false }
    $trim = [string]$Line.Trim()
    if ($trim -match '找不到适用的安装程序|No applicable installer|已成功安装|Successfully installed|卸载成功|已成功卸载|Successfully uninstalled|安装失败|Install failed|卸载失败|Uninstall failed|失败|error|错误') {
        return $true
    }
    return $false
}

function Invoke-WingetDepProcessStreamLines {
    param(
        [string[]]$Lines,
        [System.Collections.ArrayList]$AllLines,
        [scriptblock]$OnOutputLine
    )

    if ($Lines.Count -eq 0) { return $false }

    $notified = $false
    foreach ($line in $Lines) {
        $trim = [string]$line.Trim()
        if ([string]::IsNullOrWhiteSpace($trim)) { continue }

        if ($OnOutputLine) {
            & $OnOutputLine $line
            $notified = $true
        }

        $useful = (Test-WingetStreamLineUseful -Line $line) -or (Test-WingetStreamLineIsImportant -Line $line)
        if ($useful -and ($allLines -notcontains $line)) {
            [void]$AllLines.Add($line)
        }
    }

    return $notified
}

function Get-WingetDepResultSummaryLine {
    param($Result)

    if (-not $Result -or -not $Result.Lines) { return $null }
    $last = $null
    foreach ($line in @($Result.Lines)) {
        $trim = [string]$line.Trim()
        if ([string]::IsNullOrWhiteSpace($trim)) { continue }
        if (Test-WingetStreamLineUseful -Line $trim) { $last = $trim }
        elseif (Test-WingetStreamLineIsImportant -Line $trim) { $last = $trim }
    }
    return $last
}

$script:WingetDepStallWarnMs = 12000
$script:WingetDepStallFailMs = 90000
$script:WingetDepProcessExitWaitMs = 600000

function Build-ToolDepWingetArgumentList {
    param(
        [ValidateSet('install', 'upgrade', 'uninstall')]
        [string]$Verb,
        [string]$PackageId,
        $Package = $null
    )

    $args = @($Verb, '--id', $PackageId, '-e', '--disable-interactivity')

    $useSilent = $true
    $scope = $null
    if ($Package -and $Package.install) {
        $install = $Package.install
        if ($install -is [hashtable]) {
            if ($install.ContainsKey('scope') -and -not [string]::IsNullOrWhiteSpace([string]$install['scope'])) {
                $scope = [string]$install['scope']
            }
            if ($install.ContainsKey('wingetSilent') -and $null -ne $install['wingetSilent']) {
                $useSilent = [bool]$install['wingetSilent']
            }
        }
        else {
            if ($install.PSObject.Properties['scope'] -and -not [string]::IsNullOrWhiteSpace([string]$install.scope)) {
                $scope = [string]$install.scope
            }
            if ($install.PSObject.Properties['wingetSilent'] -and $null -ne $install.wingetSilent) {
                $useSilent = [bool]$install.wingetSilent
            }
        }
    }

    if ($Verb -in @('install', 'upgrade')) {
        $args += @(
            '--accept-package-agreements'
            '--accept-source-agreements'
        )
        if ($useSilent) { $args += '--silent' }
        if (-not [string]::IsNullOrWhiteSpace($scope)) {
            $args += @('--scope', $scope)
        }
    }
    # 卸载默认不加 --silent：不少包需弹出卸载程序（如 Volta），静默模式易失败

    return $args
}

function Get-ToolDepWingetCommandLine {
    param(
        $Package,
        [ValidateSet('Install', 'Upgrade', 'Repair', 'Uninstall')]
        [string]$ExecuteAction
    )

    $packageId = if ($Package.install) { [string]$Package.install.packageId } else { '' }
    if ([string]::IsNullOrWhiteSpace($packageId)) { return '' }

    $verb = switch ($ExecuteAction) {
        'Install' { 'install' }
        'Repair' { 'install' }
        'Upgrade' { 'upgrade' }
        'Uninstall' { 'uninstall' }
        default { 'install' }
    }

    $args = @(Build-ToolDepWingetArgumentList -Verb $verb -PackageId $packageId -Package $Package)
    return "winget $($args -join ' ')"
}

function Invoke-WingetDepProcess {
    param(
        [string[]]$ArgumentList,
        [scriptblock]$ShouldCancel = $null,
        [scriptblock]$OnExitConfirmKey = $null,
        [scriptblock]$OnOutputLine = $null,
        [scriptblock]$OnHeartbeat = $null,
        [scriptblock]$OnUiPoll = $null,
        [scriptblock]$OnStallNotify = $null,
        [scriptblock]$ResolveStallPolicy = $null,
        [int]$StallWarnMs = $script:WingetDepStallWarnMs,
        [int]$StallFailMs = $script:WingetDepStallFailMs,
        [int]$ProcessExitWaitMs = $script:WingetDepProcessExitWaitMs
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'winget'
    $escaped = @($ArgumentList | ForEach-Object {
        if ($_ -match '\s') { "`"$_`"" } else { $_ }
    })
    $psi.Arguments = ($escaped -join ' ')
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $psi.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    $process.EnableRaisingEvents = $true
    $allLines = New-Object System.Collections.ArrayList
    $stdoutCollector = New-WingetDepAsyncStreamCollector
    $stderrCollector = New-WingetDepAsyncStreamCollector
    $stdoutSubscription = $null
    $stderrSubscription = $null

    $cancelled = $false
    $timedOut = $false
    $streamTiming = @{
        LastOutputTick    = [Environment]::TickCount
        StartTick         = [Environment]::TickCount
        LastHeartbeatTick = [Environment]::TickCount
    }

    $pumpWingetDepUi = {
        if ($OnUiPoll) {
            & $OnUiPoll
        }
        elseif ($OnExitConfirmKey -and (Test-ConsoleKeyAvailable)) {
            & $OnExitConfirmKey
        }

        if (-not $OnHeartbeat) { return }

        $now = [Environment]::TickCount
        if (($now - $streamTiming.LastHeartbeatTick) -lt 400) { return }

        $streamTiming.LastHeartbeatTick = $now
        $idleMs = $now - $streamTiming.LastOutputTick
        & $OnHeartbeat @{
            ElapsedSeconds = [int][Math]::Floor(($now - $streamTiming.StartTick) / 1000.0)
            IdleSeconds    = [int][Math]::Floor($idleMs / 1000.0)
        }
    }.GetNewClosure()

    $noteStreamActivity = {
        param([string[]]$Lines)
        if (-not $Lines -or $Lines.Count -eq 0) { return }
        foreach ($line in $Lines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            # Spinner/progress lines mean winget is alive; only blank output is true idle.
            $streamTiming.LastOutputTick = [Environment]::TickCount
            return
        }
    }.GetNewClosure()

    $processWingetStreamBatch = {
        param([string[]]$Lines)
        if ($Lines.Count -eq 0) { return }
        & $noteStreamActivity $Lines
        $null = Invoke-WingetDepProcessStreamLines -Lines $Lines -AllLines $allLines -OnOutputLine $OnOutputLine
    }.GetNewClosure()

    $drainWingetAsyncStreams = {
        & $processWingetStreamBatch @(Get-WingetDepAsyncStreamLines -Collector $stdoutCollector)
        & $processWingetStreamBatch @(Get-WingetDepAsyncStreamLines -Collector $stderrCollector)
    }.GetNewClosure()

    try {
        $stdoutSubscription = Register-WingetDepAsyncStreamCollector -Process $process `
            -EventName 'OutputDataReceived' -Collector $stdoutCollector
        $stderrSubscription = Register-WingetDepAsyncStreamCollector -Process $process `
            -EventName 'ErrorDataReceived' -Collector $stderrCollector

        $null = $process.Start()
        $process.BeginOutputReadLine()
        $process.BeginErrorReadLine()
    }
    catch {
        Unregister-WingetDepAsyncStreamCollector -Subscription $stdoutSubscription
        Unregister-WingetDepAsyncStreamCollector -Subscription $stderrSubscription
        throw
    }

    $exitDeadline = [Environment]::TickCount + [Math]::Max(5000, $ProcessExitWaitMs)
    while ($true) {
        if ($ShouldCancel -and (& $ShouldCancel)) {
            $cancelled = $true
            try { $process.Kill() } catch {}
            break
        }

        & $pumpWingetDepUi
        & $drainWingetAsyncStreams

        $now = [Environment]::TickCount
        $idleMs = $now - $streamTiming.LastOutputTick
        $stallWarnMs = $StallWarnMs
        $stallFailMs = $StallFailMs
        if ($ResolveStallPolicy) {
            $policy = & $ResolveStallPolicy @{
                IdleMs         = $idleMs
                ElapsedSeconds = [int][Math]::Floor(($now - $streamTiming.StartTick) / 1000.0)
            }
            if ($null -ne $policy) {
                if ($policy.ContainsKey('Warn') -and -not [bool]$policy.Warn) { $stallWarnMs = 0 }
                if ($policy.ContainsKey('FailMs')) { $stallFailMs = [int]$policy.FailMs }
            }
        }
        if ($stallFailMs -gt 0 -and $idleMs -ge $stallFailMs) {
            $timedOut = $true
            try { $process.Kill() } catch {}
            break
        }
        if ($OnStallNotify -and $stallWarnMs -gt 0 -and $idleMs -ge $stallWarnMs) {
            & $OnStallNotify @{
                Phase          = 'warn'
                ElapsedSeconds = [int][Math]::Floor($idleMs / 1000.0)
                TotalSeconds   = [int][Math]::Floor(($now - $streamTiming.StartTick) / 1000.0)
            }
        }

        $streamsDone = $stdoutCollector.Ended -and $stderrCollector.Ended
        if ($process.HasExited -and $streamsDone) { break }
        if ([Environment]::TickCount -ge $exitDeadline) { break }

        Start-Sleep -Milliseconds 50
    }

    try {
        if (-not $process.HasExited) {
            $process.WaitForExit(5000) | Out-Null
        }
        else {
            $process.WaitForExit() | Out-Null
        }
    }
    catch {}

    $drainDeadline = [Environment]::TickCount + 3000
    while ((-not $stdoutCollector.Ended -or -not $stderrCollector.Ended) `
            -and [Environment]::TickCount -lt $drainDeadline) {
        & $pumpWingetDepUi
        & $drainWingetAsyncStreams
        Start-Sleep -Milliseconds 30
    }

    & $drainWingetAsyncStreams

    Unregister-WingetDepAsyncStreamCollector -Subscription $stdoutSubscription
    Unregister-WingetDepAsyncStreamCollector -Subscription $stderrSubscription

    if ($cancelled) {
        return @{
            Success       = $false
            Cancelled     = $true
            TimedOut      = $false
            ExitCode      = -1
            Lines         = @()
            Command       = "winget $($ArgumentList -join ' ')"
            Streamed      = ($null -ne $OnOutputLine)
            AlreadyLatest = $false
        }
    }

    if ($timedOut) {
        [void]$allLines.Add('winget stalled waiting for installer confirmation or progress')
    }

    $exitCode = -1
    if (-not $cancelled -and -not $timedOut) {
        if ($process.HasExited) {
            try { $exitCode = [int]$process.ExitCode } catch { $exitCode = -2 }
        }
        else {
            $exitCode = -2
        }
    }

    try { $process.Close() } catch {}
    $resultSnapshot = @{
        Success  = ($exitCode -eq 0)
        ExitCode = $exitCode
        Lines    = @($allLines)
    }
    $alreadyLatest = (-not $cancelled -and -not $timedOut) -and (Test-WingetDepResultIsAlreadyLatest $resultSnapshot)
    $uninstallSucceeded = (-not $cancelled -and -not $timedOut) -and (Test-WingetDepResultReportsUninstallSuccess $resultSnapshot)

    return @{
        Success       = (-not $cancelled -and -not $timedOut -and (($exitCode -eq 0) -or $alreadyLatest -or $uninstallSucceeded))
        Cancelled     = $cancelled
        TimedOut      = $timedOut
        ExitCode      = $exitCode
        Lines         = @($allLines)
        Command       = "winget $($ArgumentList -join ' ')"
        Streamed      = ($null -ne $OnOutputLine)
        AlreadyLatest = $alreadyLatest
    }
}

function Invoke-ToolDepWingetInstall {
    param(
        [string]$PackageId,
        $Package = $null,
        [scriptblock]$ShouldCancel = $null,
        [scriptblock]$OnExitConfirmKey = $null,
        [scriptblock]$OnOutputLine = $null,
        [scriptblock]$OnHeartbeat = $null,
        [scriptblock]$OnUiPoll = $null,
        [scriptblock]$OnStallNotify = $null,
        [scriptblock]$ResolveStallPolicy = $null
    )

    return Invoke-WingetDepProcess -ArgumentList @(Build-ToolDepWingetArgumentList -Verb install `
        -PackageId $PackageId -Package $Package) -ShouldCancel $ShouldCancel `
        -OnExitConfirmKey $OnExitConfirmKey -OnOutputLine $OnOutputLine -OnHeartbeat $OnHeartbeat `
        -OnUiPoll $OnUiPoll -OnStallNotify $OnStallNotify -ResolveStallPolicy $ResolveStallPolicy
}

function Invoke-ToolDepWingetUpgrade {
    param(
        [string]$PackageId,
        $Package = $null,
        [scriptblock]$ShouldCancel = $null,
        [scriptblock]$OnExitConfirmKey = $null,
        [scriptblock]$OnOutputLine = $null,
        [scriptblock]$OnHeartbeat = $null,
        [scriptblock]$OnUiPoll = $null,
        [scriptblock]$OnStallNotify = $null,
        [scriptblock]$ResolveStallPolicy = $null
    )

    return Invoke-WingetDepProcess -ArgumentList @(Build-ToolDepWingetArgumentList -Verb upgrade `
        -PackageId $PackageId -Package $Package) -ShouldCancel $ShouldCancel `
        -OnExitConfirmKey $OnExitConfirmKey -OnOutputLine $OnOutputLine -OnHeartbeat $OnHeartbeat `
        -OnUiPoll $OnUiPoll -OnStallNotify $OnStallNotify -ResolveStallPolicy $ResolveStallPolicy
}

function Invoke-ToolDepWingetUninstall {
    param(
        [string]$PackageId,
        $Package = $null,
        [scriptblock]$ShouldCancel = $null,
        [scriptblock]$OnExitConfirmKey = $null,
        [scriptblock]$OnOutputLine = $null,
        [scriptblock]$OnHeartbeat = $null,
        [scriptblock]$OnUiPoll = $null,
        [scriptblock]$OnStallNotify = $null,
        [scriptblock]$ResolveStallPolicy = $null
    )

    return Invoke-WingetDepProcess -ArgumentList @(Build-ToolDepWingetArgumentList -Verb uninstall `
        -PackageId $PackageId -Package $Package) -ShouldCancel $ShouldCancel `
        -OnExitConfirmKey $OnExitConfirmKey -OnOutputLine $OnOutputLine -OnHeartbeat $OnHeartbeat `
        -OnUiPoll $OnUiPoll -OnStallNotify $OnStallNotify -ResolveStallPolicy $ResolveStallPolicy
}

function Invoke-ToolDepPackageExecute {
    param(
        $Package,
        [ValidateSet('Install', 'Upgrade', 'Repair', 'Uninstall')]
        [string]$ExecuteAction,
        [scriptblock]$ShouldCancel = $null,
        [scriptblock]$OnExitConfirmKey = $null,
        [scriptblock]$OnOutputLine = $null,
        [scriptblock]$OnHeartbeat = $null,
        [scriptblock]$OnUiPoll = $null,
        [scriptblock]$OnStallNotify = $null,
        [scriptblock]$ResolveStallPolicy = $null
    )

    $packageId = if ($Package.install) { [string]$Package.install.packageId } else { '' }
    if ([string]::IsNullOrWhiteSpace($packageId)) {
        return @{
            Success   = $false
            Cancelled = $false
            ExitCode  = 1
            Lines     = @('missing packageId')
            Command   = ''
        }
    }

    switch ($ExecuteAction) {
        'Install' {
            return Invoke-ToolDepWingetInstall -PackageId $packageId -Package $Package -ShouldCancel $ShouldCancel `
                -OnExitConfirmKey $OnExitConfirmKey -OnOutputLine $OnOutputLine -OnHeartbeat $OnHeartbeat `
                -OnUiPoll $OnUiPoll -OnStallNotify $OnStallNotify -ResolveStallPolicy $ResolveStallPolicy
        }
        'Repair' {
            return Invoke-ToolDepWingetInstall -PackageId $packageId -Package $Package -ShouldCancel $ShouldCancel `
                -OnExitConfirmKey $OnExitConfirmKey -OnOutputLine $OnOutputLine -OnHeartbeat $OnHeartbeat `
                -OnUiPoll $OnUiPoll -OnStallNotify $OnStallNotify -ResolveStallPolicy $ResolveStallPolicy
        }
        'Upgrade' {
            return Invoke-ToolDepWingetUpgrade -PackageId $packageId -Package $Package -ShouldCancel $ShouldCancel `
                -OnExitConfirmKey $OnExitConfirmKey -OnOutputLine $OnOutputLine -OnHeartbeat $OnHeartbeat `
                -OnUiPoll $OnUiPoll -OnStallNotify $OnStallNotify -ResolveStallPolicy $ResolveStallPolicy
        }
        'Uninstall' {
            return Invoke-ToolDepWingetUninstall -PackageId $packageId -Package $Package -ShouldCancel $ShouldCancel `
                -OnExitConfirmKey $OnExitConfirmKey -OnOutputLine $OnOutputLine -OnHeartbeat $OnHeartbeat `
                -OnUiPoll $OnUiPoll -OnStallNotify $OnStallNotify -ResolveStallPolicy $ResolveStallPolicy
        }
    }

    return @{
        Success   = $false
        Cancelled = $false
        ExitCode  = 1
        Lines     = @()
        Command   = ''
    }
}

function Get-ToolDepPackageRecordableVersion {
    param($Package)

    if (-not $Package) { return $null }

    $packageId = $null
    if ($Package.install -and $Package.install.packageId) {
        $packageId = [string]$Package.install.packageId
    }

    if ($packageId) {
        $version = Get-WingetPackageInstalledVersion -PackageId $packageId
        if (-not [string]::IsNullOrWhiteSpace($version)) { return $version }
    }

    $checkCommand = if ($Package.checkCommand) { [string]$Package.checkCommand } else { '' }
    if ($checkCommand -and (Test-ToolDepCommandAvailable -CheckCommand $checkCommand)) {
        $version = Resolve-ToolDepCheckCommandVersion -CheckCommand $checkCommand
        if (-not [string]::IsNullOrWhiteSpace($version)) { return $version }
    }

    $policy = $null
    if ($Package.version) { $policy = [string]$Package.version }
    elseif ($Package.updatePolicy) { $policy = [string]$Package.updatePolicy }
    if ($policy -and ($policy.Trim().ToLowerInvariant() -ne 'latest')) {
        return $policy.Trim()
    }

    return $null
}
