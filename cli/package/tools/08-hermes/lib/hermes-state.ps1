# hermes — CLI 安装状态与命令执行

function Resolve-HermesExecutable {
    $paths = Get-HermesKnownPaths
    if (Test-Path -LiteralPath $paths.HermesExe) {
        return [string]$paths.HermesExe
    }
    if (Test-Path -LiteralPath $paths.HermesCmdShim) {
        return [string]$paths.HermesCmdShim
    }

    $cmd = Get-Command hermes -ErrorAction SilentlyContinue
    if ($cmd) {
        return [string]$cmd.Source
    }

    return $null
}

function Test-HermesInstalled {
    $paths = Get-HermesKnownPaths
    if (Test-Path -LiteralPath $paths.HermesExe) {
        return $true
    }

    $exe = Resolve-HermesExecutable
    if ([string]::IsNullOrWhiteSpace($exe)) {
        return $false
    }

    $normalized = $exe.Replace('/', '\').ToLowerInvariant()
    $homeNorm = $paths.HermesHome.Replace('/', '\').ToLowerInvariant()
    if ($normalized.StartsWith($homeNorm)) {
        return $true
    }

    return $false
}

function Invoke-HermesCli {
    param(
        [string[]]$ArgumentList,
        [int]$TimeoutMs = 120000,
        [scriptblock]$OnUiPoll = $null,
        [scriptblock]$OnChromePulse = $null
    )

    $exe = Resolve-HermesExecutable
    if ([string]::IsNullOrWhiteSpace($exe)) {
        throw 'hermes CLI not found'
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
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

    $process = $null
    try {
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $psi
        $null = $process.Start()

        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()

        $deadline = [Environment]::TickCount + [Math]::Max(1000, $TimeoutMs)
        while (-not $process.HasExited) {
            if ([Environment]::TickCount -ge $deadline) {
                try { $process.Kill() } catch {}
                return [pscustomobject]@{
                    ExitCode = -1
                    Success  = $false
                    TimedOut = $true
                    StdOut   = ''
                    StdErr   = ''
                    Output   = ''
                }
            }

            if ($OnChromePulse) { & $OnChromePulse }
            if ($OnUiPoll) { & $OnUiPoll }
            Start-Sleep -Milliseconds 50
        }

        $null = $process.WaitForExit()
        $stdoutText = $stdoutTask.GetAwaiter().GetResult()
        $stderrText = $stderrTask.GetAwaiter().GetResult()
        $exitCode = [int]$process.ExitCode
        $output = ($stdoutText + $stderrText)

        return [pscustomobject]@{
            ExitCode = $exitCode
            Success  = ($exitCode -eq 0)
            TimedOut = $false
            StdOut   = $stdoutText
            StdErr   = $stderrText
            Output   = $output
        }
    }
    finally {
        if ($process) {
            try { $process.Dispose() } catch {}
        }
    }
}

function Get-HermesCliVersionOutput {
    if (-not (Test-HermesInstalled)) {
        return $null
    }

    try {
        $result = Invoke-HermesCli -ArgumentList @('--version') -TimeoutMs 30000
        if (-not $result.Success) { return $null }
        $line = @($result.StdOut -split "`r?`n" | ForEach-Object { [string]$_ } | Where-Object {
            -not [string]::IsNullOrWhiteSpace($_)
        } | Select-Object -First 1)
        if ([string]::IsNullOrWhiteSpace($line)) { return $null }
        return $line.Trim()
    }
    catch {
        return $null
    }
}

function Get-HermesInstalledVersion {
    $line = Get-HermesCliVersionOutput
    if ([string]::IsNullOrWhiteSpace($line)) { return $null }
    if ($line -match '(\d+\.\d+\.\d+)') {
        return [string]$Matches[1]
    }
    return $line
}

function Import-HermesWingetCore {
    param([string]$CoreLib)

    if (-not (Get-Command Get-WingetPackageInstalledVersion -ErrorAction SilentlyContinue)) {
        . (Join-Path $CoreLib 'domain\Ensure-ToolDeps.ps1')
    }
}

function Test-HermesWingetDesktopInstalled {
    param([string]$CoreLib = '')

    if (-not [string]::IsNullOrWhiteSpace($CoreLib)) {
        Import-HermesWingetCore -CoreLib $CoreLib
    }

    if (-not (Get-Command Get-WingetPackageInstalledVersion -ErrorAction SilentlyContinue)) {
        return $false
    }

    $version = Get-WingetPackageInstalledVersion -PackageId $script:HermesWingetDesktopPackageId
    return -not [string]::IsNullOrWhiteSpace($version)
}

function Test-HermesUpdateNetworkReachable {
    param(
        [int]$TimeoutSec = 0,
        [scriptblock]$OnPulse = $null
    )

    $timeout = if ($TimeoutSec -gt 0) { $TimeoutSec } else { $script:HermesUpdateNetworkPreflightSec }
    $timeout = [Math]::Max(2, [int]$timeout)

    $urls = @(
        'https://github.com'
        'https://raw.githubusercontent.com'
    )

    foreach ($url in @($urls)) {
        if ($OnPulse) { & $OnPulse }
        try {
            $response = Invoke-WebRequest -Uri $url -Method Head -TimeoutSec $timeout -UseBasicParsing
            $code = [int]$response.StatusCode
            if ($code -ge 200 -and $code -lt 400) {
                return $true
            }
        }
        catch {
            $msg = [string]$_.Exception.Message
            if ($msg -match '405|403|401') {
                return $true
            }
        }
    }

    return $false
}

function Resolve-HermesUpdateCheck {
    param(
        [scriptblock]$OnPulse = $null,
        [int]$TimeoutMs = 0
    )

    $timeout = if ($TimeoutMs -gt 0) { $TimeoutMs } else { $script:HermesUpdateCheckTimeoutMs }

    if (-not (Test-HermesUpdateNetworkReachable -OnPulse $OnPulse)) {
        return @{
            Available  = $false
            Skipped    = $true
            SkipReason = 'network'
            TimedOut   = $false
            Detail     = ''
        }
    }

    if ($OnPulse) { & $OnPulse }

    try {
        $cliResult = Invoke-HermesCli -ArgumentList @('update', '--check') -TimeoutMs $timeout -OnUiPoll $OnPulse
        if ($cliResult.TimedOut) {
            return @{
                Available  = $false
                Skipped    = $true
                SkipReason = 'timeout'
                TimedOut   = $true
                Detail     = ''
            }
        }

        if (-not $cliResult.Success) {
            return @{
                Available  = $false
                Skipped    = $true
                SkipReason = 'error'
                TimedOut   = $false
                Detail     = [string]$cliResult.Output
            }
        }

        $output = [string]$cliResult.Output
        $available = ($output -match '(?i)update available')

        return @{
            Available  = [bool]$available
            Skipped    = $false
            SkipReason = ''
            TimedOut   = $false
            Detail     = $output
        }
    }
    catch {
        return @{
            Available  = $false
            Skipped    = $true
            SkipReason = 'error'
            TimedOut   = $false
            Detail     = [string]$_.Exception.Message
        }
    }
}

function Get-HermesInstallWrapperScriptContent {
    $url = $script:HermesInstallScriptUrl
    return @"
`$ErrorActionPreference = 'Stop'
`$url = '$url'
`$content = (Invoke-WebRequest -Uri `$url -UseBasicParsing).Content
if (`$content.Length -gt 0 -and [int][char]`$content[0] -eq 0xFEFF) {
    `$content = `$content.Substring(1)
}
& ([scriptblock]::Create(`$content)) -SkipSetup
"@
}

function New-HermesInstallWrapperScriptPath {
    $tempFile = [IO.Path]::Combine([IO.Path]::GetTempPath(), "miao-hermes-install-$([guid]::NewGuid().ToString('N')).ps1")
    $content = Get-HermesInstallWrapperScriptContent
    [IO.File]::WriteAllText($tempFile, $content, (New-Object Text.UTF8Encoding $false))
    return $tempFile
}
