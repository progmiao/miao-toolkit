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
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { return $false }

    try {
        $null = & winget --version --disable-interactivity 2>&1
        return ($LASTEXITCODE -eq 0)
    }
    catch {
        return $false
    }
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

    if ($trim -match '[\u2588\u2590-\u2592\u2593]') {
        $filled = ([regex]::Matches($trim, '\u2588')).Count
        $partial = ([regex]::Matches($trim, '[\u2590-\u2592\u2593]')).Count
        $totalUnits = $filled + $partial
        if ($totalUnits -gt 0) {
            return [Math]::Max(0, [Math]::Min(100, [int][Math]::Round($filled * 100.0 / $totalUnits)))
        }
    }

    return -1
}

function Format-WingetDepStreamSizePart {
    param(
        [string]$Value,
        [string]$Unit
    )

    $num = [double]$Value
    $text = if ([Math]::Abs($num - [Math]::Round($num)) -lt 0.001) {
        [string][int][Math]::Round($num)
    }
    else {
        [string]$Value
    }

    return "$text $Unit"
}

function Get-WingetDepStreamLineTransferLabel {
    param([string]$Line)

    if ([string]::IsNullOrWhiteSpace($Line)) { return $null }
    $trim = Get-WingetStreamLineCleanText -Line $Line
    if ([string]::IsNullOrWhiteSpace($trim)) { return $null }

    if ($trim -match '(\d+(?:\.\d+)?)\s*(KB|MB|GB)\s*/\s*(\d+(?:\.\d+)?)\s*(KB|MB|GB)') {
        $u1 = [string]$Matches[2].ToUpperInvariant()
        $u2 = [string]$Matches[4].ToUpperInvariant()
        if ($u1 -eq $u2) {
            $cur = Format-WingetDepStreamSizePart -Value $Matches[1] -Unit $u1
            $total = Format-WingetDepStreamSizePart -Value $Matches[3] -Unit $u2
            return "$cur / $total"
        }
    }

    return $null
}

function Format-WingetDepStreamLineTransferStatus {
    param([string]$Line)

    $transfer = Get-WingetDepStreamLineTransferLabel -Line $Line
    if ([string]::IsNullOrWhiteSpace($transfer)) { return $null }

    if (Get-Command Get-I18n -ErrorAction SilentlyContinue) {
        return Get-I18n -Key 'page.depOperation.statusDownloadTransfer' -Vars @{ transfer = $transfer }
    }

    return "下载进度：$transfer"
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
    if ($trim -match '^Starting package install|^正在(?:启动|执行|运行)程序包安装') { return 'startInstall' }
    if ($trim -match '^Starting package uninstall|^正在(?:启动|执行)程序包卸载') { return 'startUninstall' }
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
    if ($trim -match '(?i)^https?://') { return 'info' }
    if ($trim -match '(?i)(?:[A-Za-z]:\\|\\\\)[^\s]*\.(?:msi|exe)\b') { return 'installerPackage' }
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

function Get-WingetDepStreamLineDeclineKind {
    param([string]$Line)

    if (-not (Test-WingetDepStreamLineIsDeclined -Line $Line)) { return $null }

    $trim = Get-WingetStreamLineCleanText -Line $Line
    if ($trim -match 'access\s+denied|拒绝访问|requires elevation|需要提升|UAC|用户拒绝|The operation was canceled by the user') {
        return 'uac'
    }

    return 'user'
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

function Test-WingetDepStreamLineIsFileLockRemoveError {
    param([string]$Line)

    $trim = Get-WingetStreamLineCleanText -Line $Line
    if ([string]::IsNullOrWhiteSpace($trim)) { return $false }

    if ($trim -match '(?i)^remove:') {
        if ($trim -match '(?i)being used by another process|另一个进程|正在使用|cannot access the file|无法访问') {
            return $true
        }
    }

    return $false
}

function Test-WingetDepStreamLineIsNonStallActivity {
    param([string]$Line)

    $trim = Get-WingetStreamLineCleanText -Line $Line
    if ([string]::IsNullOrWhiteSpace($trim)) { return $false }
    if (Test-WingetStreamLineIsSpinnerOnly -Line $trim) { return $true }
    if (Test-WingetDepStreamLineIsProgressVisual -Line $trim) { return $true }
    if (Test-WingetDepStreamLineIsFileLockRemoveError -Line $trim) { return $false }
    return $true
}

function Test-WingetDepResultIsTempFileLockFailure {
    param($Result)

    if (-not $Result) { return $false }
    foreach ($line in @($Result.Lines)) {
        if (Test-WingetDepStreamLineIsFileLockRemoveError -Line ([string]$line)) {
            return $true
        }
    }
    return $false
}

function Test-WingetStreamLineIsImportant {
    param([string]$Line)

    if ([string]::IsNullOrWhiteSpace($Line)) { return $false }
    $trim = [string]$Line.Trim()
    if ($trim -match '找不到适用的安装程序|No applicable installer|已成功安装|Successfully installed|卸载成功|已成功卸载|Successfully uninstalled|安装失败|Install failed|卸载失败|Uninstall failed|失败|error|错误') {
        return $true
    }
    if (Test-WingetDepStreamLineIsFileLockRemoveError -Line $trim) {
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
$script:WingetDepInstallerPromptWarnMs = 30000
$script:WingetDepInstallerPromptFailMs = 300000
$script:WingetDepFileLockMaxRetries = 3
$script:WingetDepProcessExitWaitMs = 300000
$script:WingetDepNetworkPreflightTimeoutSec = 15

function Get-WingetDepPolicyConstants {
    return @{
        StallWarnMs                 = [int]$script:WingetDepStallWarnMs
        StallFailMs                 = [int]$script:WingetDepStallFailMs
        InstallerPromptWarnMs       = [int]$script:WingetDepInstallerPromptWarnMs
        InstallerPromptFailMs       = [int]$script:WingetDepInstallerPromptFailMs
        FileLockMaxRetries          = [int]$script:WingetDepFileLockMaxRetries
        ProcessExitWaitMs           = [int]$script:WingetDepProcessExitWaitMs
        NetworkPreflightTimeoutSec  = [int]$script:WingetDepNetworkPreflightTimeoutSec
    }
}

function Get-ToolDepInstallConfigProperty {
    param(
        $Package,
        [string[]]$Names
    )

    if (-not $Package -or -not $Package.install) { return $null }

    $install = $Package.install
    foreach ($name in @($Names)) {
        if ($install -is [hashtable]) {
            if ($install.ContainsKey($name) -and $null -ne $install[$name]) {
                return $install[$name]
            }
        }
        elseif ($install.PSObject.Properties[$name] -and $null -ne $install.$name) {
            return $install.$name
        }
    }

    return $null
}

function Test-ToolDepWingetInstallInteractiveRequired {
    param($Package)

    $flag = Get-ToolDepInstallConfigProperty -Package $Package -Names @(
        'installInteractiveRequired'
        'wingetInteractiveRequired'
    )
    if ($null -eq $flag) { return $false }
    return [bool]$flag
}

function Resolve-ToolDepWingetSilentMode {
    param(
        $Package,
        [ValidateSet('install', 'upgrade', 'uninstall')]
        [string]$Verb
    )

    if ($Verb -eq 'uninstall') { return 'interactive' }

    if (Test-ToolDepWingetInstallInteractiveRequired -Package $Package) {
        return 'interactive'
    }

    $explicit = Get-ToolDepInstallConfigProperty -Package $Package -Names @('wingetSilent')
    if ($null -ne $explicit) {
        if ([bool]$explicit) { return 'silent' }
        return 'interactive'
    }

    return 'silent'
}

function Parse-WingetShowInstallerDownloadUrls {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return @() }

    $urls = New-Object 'System.Collections.Generic.List[string]'
    foreach ($line in @($Text -split "`r?`n")) {
        $trim = [string]$line.Trim()
        if ([string]::IsNullOrWhiteSpace($trim)) { continue }
        if ($trim -match '(?i)(?:Installer\s+(?:Url|URL)|安装程序\s+URL)\s*[:：]\s*(\S+)') {
            [void]$urls.Add([string]$Matches[1].Trim())
        }
    }

    return @($urls | Select-Object -Unique)
}

function Get-WingetPackageInstallerDownloadUrls {
    param([string]$PackageId)

    if ([string]::IsNullOrWhiteSpace($PackageId)) { return @() }
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { return @() }

    try {
        $output = & winget show --id $PackageId -e --disable-interactivity --accept-source-agreements 2>&1 |
            Out-String
        if ([string]::IsNullOrWhiteSpace($output)) { return @() }
        return @(Parse-WingetShowInstallerDownloadUrls -Text $output)
    }
    catch {
        return @()
    }
}

function Test-ToolDepNetworkEndpointReachable {
    param(
        [string]$Url,
        [int]$TimeoutSec = $script:WingetDepNetworkPreflightTimeoutSec
    )

    if ([string]::IsNullOrWhiteSpace($Url)) {
        return @{ Ok = $false; Reason = 'empty url' }
    }

    $timeoutSec = [Math]::Max(3, $TimeoutSec)
    $attempts = @(
        @{ Method = 'Head'; Headers = $null }
        @{ Method = 'Get'; Headers = @{ Range = 'bytes=0-0' } }
    )

    $lastReason = 'unreachable'
    foreach ($attempt in @($attempts)) {
        try {
            $params = @{
                Uri             = $Url
                Method          = [string]$attempt.Method
                TimeoutSec      = $timeoutSec
                UseBasicParsing = $true
            }
            if ($attempt.Headers) {
                $params.Headers = $attempt.Headers
            }
            $response = Invoke-WebRequest @params
            $code = [int]$response.StatusCode
            if ($code -ge 200 -and $code -lt 400) {
                return @{ Ok = $true; StatusCode = $code }
            }
            $lastReason = "HTTP $code"
        }
        catch {
            $lastReason = [string]$_.Exception.Message
            if ($lastReason -match '404|403|401|500|502|503|504|timed out|timeout|无法连接|connection|Name or service not known|No such host') {
                break
            }
        }
    }

    return @{ Ok = $false; Reason = $lastReason }
}

function Test-ToolDepPackageNetworkPreflight {
    param(
        $Package,
        [ValidateSet('Install', 'Upgrade', 'Repair', 'Uninstall')]
        [string]$ExecuteAction,
        [scriptblock]$OnPulse = $null
    )

    if ($ExecuteAction -notin @('Install', 'Upgrade', 'Repair')) {
        return @{ Ok = $true; Skipped = $true }
    }

    $packageId = if ($Package.install) { [string]$Package.install.packageId } else { '' }
    if ([string]::IsNullOrWhiteSpace($packageId)) {
        return @{ Ok = $true; Skipped = $true }
    }

    if ($OnPulse) { & $OnPulse }

    $urls = @(Get-WingetPackageInstallerDownloadUrls -PackageId $packageId)
    if ($urls.Count -eq 0) {
        return @{ Ok = $true; Skipped = $true }
    }

    $policy = Get-WingetDepPolicyConstants
    $timeoutSec = [int]$policy.NetworkPreflightTimeoutSec
    foreach ($url in @($urls)) {
        if ($OnPulse) { & $OnPulse }
        $probe = Test-ToolDepNetworkEndpointReachable -Url $url -TimeoutSec $timeoutSec
        if (-not $probe.Ok) {
            return @{
                Ok     = $false
                Url    = $url
                Reason = [string]$probe.Reason
                Urls   = @($urls)
            }
        }
    }

    return @{ Ok = $true; Urls = @($urls) }
}

function Test-WingetDepResultNeedsInteractiveRetry {
    param(
        $Result,
        [ValidateSet('Install', 'Upgrade', 'Repair', 'Uninstall')]
        [string]$ExecuteAction
    )

    if ($ExecuteAction -notin @('Install', 'Upgrade', 'Repair')) { return $false }
    if (-not $Result -or -not $Result.UsedSilent) { return $false }
    if ($Result.Success -or $Result.Cancelled -or $Result.Aborted -or $Result.TimedOut) { return $false }
    if ($Result.AlreadyLatest) { return $false }
    if (Test-WingetDepResultIsTempFileLockFailure -Result $Result) { return $false }

    foreach ($line in @($Result.Lines)) {
        if (Get-WingetDepStreamLineDeclineKind -Line ([string]$line)) {
            return $false
        }
    }

    return $true
}

function Get-WingetDepStaleTempPaths {
    $paths = [System.Collections.Generic.List[string]]::new()

    foreach ($candidate in @(
            (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Temp')
            (Join-Path $env:LOCALAPPDATA 'Temp\WinGet')
        )) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
            [void]$paths.Add($candidate)
        }
    }

    $packagesRoot = Join-Path $env:LOCALAPPDATA 'Packages'
    if (Test-Path -LiteralPath $packagesRoot) {
        foreach ($pkg in @(Get-ChildItem -LiteralPath $packagesRoot -Directory `
                -Filter 'Microsoft.DesktopAppInstaller_*' -ErrorAction SilentlyContinue)) {
            $temp = Join-Path $pkg.FullName 'LocalState\Temp'
            if (Test-Path -LiteralPath $temp) {
                [void]$paths.Add($temp)
            }
        }
    }

    return @($paths | Select-Object -Unique)
}

function Wait-WingetDepProcessesIdle {
    param(
        [int]$TimeoutMs = 15000,
        [scriptblock]$OnPulse = $null
    )

    $deadline = [Environment]::TickCount + [Math]::Max(1000, $TimeoutMs)
    while ([Environment]::TickCount -lt $deadline) {
        if ($OnPulse) { & $OnPulse }
        $running = @(Get-Process -Name 'winget' -ErrorAction SilentlyContinue)
        if ($running.Count -eq 0) { return $true }
        Start-Sleep -Milliseconds 400
    }

    return $false
}

function Clear-WingetDepStaleTempPaths {
    param([array]$Paths = $null)

    $targets = if ($Paths) { @($Paths) } else { Get-WingetDepStaleTempPaths }
    foreach ($path in $targets) {
        if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path)) { continue }
        try {
            Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
        }
        catch {
            try {
                Get-ChildItem -LiteralPath $path -Force -ErrorAction Stop | ForEach-Object {
                    Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
            catch {}
        }
    }
}

function Repair-WingetDepFileLockEnvironment {
    param(
        [int]$Attempt = 1,
        [scriptblock]$OnPulse = $null
    )

    $waitSec = [Math]::Min(8, [Math]::Max(2, 2 * [Math]::Max(1, $Attempt)))
    $deadline = [Environment]::TickCount + ($waitSec * 1000)
    while ([Environment]::TickCount -lt $deadline) {
        if ($OnPulse) { & $OnPulse }
        Start-Sleep -Milliseconds 50
    }
    $null = Wait-WingetDepProcessesIdle -TimeoutMs 15000 -OnPulse $OnPulse
    Clear-WingetDepStaleTempPaths
}

function Build-ToolDepWingetArgumentList {
    param(
        [ValidateSet('install', 'upgrade', 'uninstall')]
        [string]$Verb,
        [string]$PackageId,
        $Package = $null,
        [ValidateSet('default', 'silent', 'interactive')]
        [string]$SilentMode = 'default'
    )

    $args = @($Verb, '--id', $PackageId, '-e')

    $useSilent = $false
    $scope = $null
    if ($Package -and $Package.install) {
        $install = $Package.install
        if ($install -is [hashtable]) {
            if ($install.ContainsKey('scope') -and -not [string]::IsNullOrWhiteSpace([string]$install['scope'])) {
                $scope = [string]$install['scope']
            }
        }
        else {
            if ($install.PSObject.Properties['scope'] -and -not [string]::IsNullOrWhiteSpace([string]$install.scope)) {
                $scope = [string]$install.scope
            }
        }
    }

    if ($Verb -in @('install', 'upgrade')) {
        $resolvedSilent = switch ($SilentMode) {
            'silent' { 'silent' }
            'interactive' { 'interactive' }
            default { Resolve-ToolDepWingetSilentMode -Package $Package -Verb $Verb }
        }
        $useSilent = ($resolvedSilent -eq 'silent')
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

function Test-ToolDepWingetInstallUsesSilent {
    param(
        $Package,
        [ValidateSet('install', 'upgrade', 'uninstall')]
        [string]$Verb = 'install'
    )

    if ($Verb -eq 'uninstall') { return $false }
    return ((Resolve-ToolDepWingetSilentMode -Package $Package -Verb $Verb) -eq 'silent')
}

function Get-ToolDepWingetCommandLine {
    param(
        $Package,
        [ValidateSet('Install', 'Upgrade', 'Repair', 'Uninstall')]
        [string]$ExecuteAction,
        [ValidateSet('default', 'silent', 'interactive')]
        [string]$SilentMode = 'default'
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

    $args = @(Build-ToolDepWingetArgumentList -Verb $verb -PackageId $packageId -Package $Package `
        -SilentMode $SilentMode)
    return "winget $($args -join ' ')"
}

function Invoke-WingetDepProcess {
    param(
        [string[]]$ArgumentList,
        [scriptblock]$ShouldCancel = $null,
        [scriptblock]$ShouldAbort = $null,
        [scriptblock]$OnExitConfirmKey = $null,
        [scriptblock]$OnOutputLine = $null,
        [scriptblock]$OnHeartbeat = $null,
        [scriptblock]$OnUiPoll = $null,
        [scriptblock]$OnChromePulse = $null,
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
    $aborted = $false
    $timedOut = $false
    $timedOutReason = ''
    $streamTiming = @{
        LastOutputTick    = [Environment]::TickCount
        StartTick         = [Environment]::TickCount
        LastHeartbeatTick = [Environment]::TickCount
    }

    $pumpWingetDepUi = {
        if ($OnChromePulse) {
            & $OnChromePulse
        }

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
            if (Test-WingetDepStreamLineIsNonStallActivity -Line $line) {
                $streamTiming.LastOutputTick = [Environment]::TickCount
                return
            }
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
        if ($ShouldAbort -and (& $ShouldAbort)) {
            $aborted = $true
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
                if ($policy.ContainsKey('AbsoluteFail') -and [bool]$policy.AbsoluteFail) {
                    if ($policy.ContainsKey('TimedOutReason')) {
                        $timedOutReason = [string]$policy.TimedOutReason
                    }
                    $timedOut = $true
                    try { $process.Kill() } catch {}
                    break
                }
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
            Aborted       = $false
            TimedOut      = $false
            ExitCode      = -1
            Lines         = @($allLines)
            Command       = "winget $($ArgumentList -join ' ')"
            Streamed      = ($null -ne $OnOutputLine)
            AlreadyLatest = $false
        }
    }

    if ($aborted) {
        $exitCode = -1
        if ($process.HasExited) {
            try { $exitCode = [int]$process.ExitCode } catch { $exitCode = -2 }
        }
        return @{
            Success        = $false
            Cancelled      = $false
            Aborted        = $true
            TimedOut       = $false
            ExitCode       = $exitCode
            Lines          = @($allLines)
            Command        = "winget $($ArgumentList -join ' ')"
            Streamed       = ($null -ne $OnOutputLine)
            AlreadyLatest  = $false
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
        Success        = (-not $cancelled -and -not $timedOut -and -not $aborted -and (($exitCode -eq 0) -or $alreadyLatest -or $uninstallSucceeded))
        Cancelled      = $cancelled
        Aborted        = $false
        TimedOut       = $timedOut
        TimedOutReason = $timedOutReason
        ExitCode       = $exitCode
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
        [ValidateSet('default', 'silent', 'interactive')]
        [string]$SilentMode = 'default',
        [scriptblock]$ShouldCancel = $null,
        [scriptblock]$ShouldAbort = $null,
        [scriptblock]$OnExitConfirmKey = $null,
        [scriptblock]$OnOutputLine = $null,
        [scriptblock]$OnHeartbeat = $null,
        [scriptblock]$OnUiPoll = $null,
        [scriptblock]$OnChromePulse = $null,
        [scriptblock]$OnStallNotify = $null,
        [scriptblock]$ResolveStallPolicy = $null
    )

    $argumentList = @(Build-ToolDepWingetArgumentList -Verb install -PackageId $PackageId -Package $Package `
        -SilentMode $SilentMode)
    $result = Invoke-WingetDepProcess -ArgumentList $argumentList -ShouldCancel $ShouldCancel -ShouldAbort $ShouldAbort `
        -OnExitConfirmKey $OnExitConfirmKey -OnOutputLine $OnOutputLine -OnHeartbeat $OnHeartbeat `
        -OnUiPoll $OnUiPoll -OnChromePulse $OnChromePulse -OnStallNotify $OnStallNotify -ResolveStallPolicy $ResolveStallPolicy
    $result.UsedSilent = ($argumentList -contains '--silent')
    return $result
}

function Invoke-ToolDepWingetUpgrade {
    param(
        [string]$PackageId,
        $Package = $null,
        [ValidateSet('default', 'silent', 'interactive')]
        [string]$SilentMode = 'default',
        [scriptblock]$ShouldCancel = $null,
        [scriptblock]$ShouldAbort = $null,
        [scriptblock]$OnExitConfirmKey = $null,
        [scriptblock]$OnOutputLine = $null,
        [scriptblock]$OnHeartbeat = $null,
        [scriptblock]$OnUiPoll = $null,
        [scriptblock]$OnChromePulse = $null,
        [scriptblock]$OnStallNotify = $null,
        [scriptblock]$ResolveStallPolicy = $null
    )

    $argumentList = @(Build-ToolDepWingetArgumentList -Verb upgrade -PackageId $PackageId -Package $Package `
        -SilentMode $SilentMode)
    $result = Invoke-WingetDepProcess -ArgumentList $argumentList -ShouldCancel $ShouldCancel -ShouldAbort $ShouldAbort `
        -OnExitConfirmKey $OnExitConfirmKey -OnOutputLine $OnOutputLine -OnHeartbeat $OnHeartbeat `
        -OnUiPoll $OnUiPoll -OnChromePulse $OnChromePulse -OnStallNotify $OnStallNotify -ResolveStallPolicy $ResolveStallPolicy
    $result.UsedSilent = ($argumentList -contains '--silent')
    return $result
}

function Invoke-ToolDepWingetUninstall {
    param(
        [string]$PackageId,
        $Package = $null,
        [scriptblock]$ShouldCancel = $null,
        [scriptblock]$ShouldAbort = $null,
        [scriptblock]$OnExitConfirmKey = $null,
        [scriptblock]$OnOutputLine = $null,
        [scriptblock]$OnHeartbeat = $null,
        [scriptblock]$OnUiPoll = $null,
        [scriptblock]$OnChromePulse = $null,
        [scriptblock]$OnStallNotify = $null,
        [scriptblock]$ResolveStallPolicy = $null
    )

    return Invoke-WingetDepProcess -ArgumentList @(Build-ToolDepWingetArgumentList -Verb uninstall `
        -PackageId $PackageId -Package $Package) -ShouldCancel $ShouldCancel -ShouldAbort $ShouldAbort `
        -OnExitConfirmKey $OnExitConfirmKey -OnOutputLine $OnOutputLine -OnHeartbeat $OnHeartbeat `
        -OnUiPoll $OnUiPoll -OnChromePulse $OnChromePulse -OnStallNotify $OnStallNotify -ResolveStallPolicy $ResolveStallPolicy
}

function Invoke-ToolDepPackageExecute {
    param(
        $Package,
        [ValidateSet('Install', 'Upgrade', 'Repair', 'Uninstall')]
        [string]$ExecuteAction,
        [ValidateSet('default', 'silent', 'interactive')]
        [string]$SilentMode = 'default',
        [scriptblock]$ShouldCancel = $null,
        [scriptblock]$ShouldAbort = $null,
        [scriptblock]$OnExitConfirmKey = $null,
        [scriptblock]$OnOutputLine = $null,
        [scriptblock]$OnHeartbeat = $null,
        [scriptblock]$OnUiPoll = $null,
        [scriptblock]$OnChromePulse = $null,
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

    if (-not (Test-WingetCliAvailable)) {
        $missingText = if (Get-Command Get-I18n -ErrorAction SilentlyContinue) {
            Get-I18n -Key 'page.depOperation.wingetMissing'
        }
        else {
            'winget not found'
        }
        return @{
            Success   = $false
            Cancelled = $false
            ExitCode  = 1
            Lines     = @($missingText)
            Command   = ''
        }
    }

    $invokeParams = @{
        PackageId            = $packageId
        Package              = $Package
        ShouldCancel         = $ShouldCancel
        ShouldAbort          = $ShouldAbort
        OnExitConfirmKey     = $OnExitConfirmKey
        OnOutputLine         = $OnOutputLine
        OnHeartbeat          = $OnHeartbeat
        OnUiPoll             = $OnUiPoll
        OnChromePulse        = $OnChromePulse
        OnStallNotify        = $OnStallNotify
        ResolveStallPolicy   = $ResolveStallPolicy
    }

    switch ($ExecuteAction) {
        'Install' {
            return Invoke-ToolDepWingetInstall @invokeParams -SilentMode $SilentMode
        }
        'Repair' {
            return Invoke-ToolDepWingetInstall @invokeParams -SilentMode $SilentMode
        }
        'Upgrade' {
            return Invoke-ToolDepWingetUpgrade @invokeParams -SilentMode $SilentMode
        }
        'Uninstall' {
            return Invoke-ToolDepWingetUninstall @invokeParams
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
