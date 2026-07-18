# claude-code — CLI 安装状态与 WinGet 操作

function Get-ClaudeCodeWingetPackageId {
    return $script:ClaudeCodeWingetPackageId
}

function Test-ClaudeCodeCliAvailable {
    if (Get-Command claude -ErrorAction SilentlyContinue) {
        return $true
    }
    return $false
}

function Get-ClaudeCodeCliVersionOutput {
    if (-not (Test-ClaudeCodeCliAvailable)) {
        return $null
    }

    try {
        $output = & claude --version 2>&1
        $line = @($output | ForEach-Object { [string]$_ } | Where-Object {
            -not [string]::IsNullOrWhiteSpace($_)
        } | Select-Object -First 1)
        if ([string]::IsNullOrWhiteSpace($line)) { return $null }
        return $line.Trim()
    }
    catch {
        return $null
    }
}

function Get-ClaudeCodeCliVersion {
    $line = Get-ClaudeCodeCliVersionOutput
    if ([string]::IsNullOrWhiteSpace($line)) { return $null }
    if ($line -match '(\d+\.\d+\.\d+)') {
        return $Matches[1]
    }
    return $line
}

function Get-ClaudeCodeCliInstallPath {
    if (-not (Test-ClaudeCodeCliAvailable)) {
        return $null
    }

    try {
        return [string](Get-Command claude -ErrorAction Stop).Source
    }
    catch {
        return $null
    }
}

function Test-ClaudeCodeWingetPackageInstalled {
    param([string]$CoreLib = '')

    if (-not [string]::IsNullOrWhiteSpace($CoreLib)) {
        Import-ClaudeCodeWingetCore -CoreLib $CoreLib
    }

    if (-not (Get-Command Get-WingetPackageInstalledVersion -ErrorAction SilentlyContinue)) {
        return $false
    }

    $wingetVersion = Get-WingetPackageInstalledVersion -PackageId (Get-ClaudeCodeWingetPackageId)
    return -not [string]::IsNullOrWhiteSpace($wingetVersion)
}

function Test-ClaudeCodeInstalled {
    param([string]$CoreLib = '')

    if ($null -ne (Get-ClaudeCodeCliVersion)) {
        return $true
    }

    return (Test-ClaudeCodeWingetPackageInstalled -CoreLib $CoreLib)
}

function Get-ClaudeCodeInstalledVersion {
    $cliVersion = Get-ClaudeCodeCliVersion
    if (-not [string]::IsNullOrWhiteSpace($cliVersion)) {
        return [string]$cliVersion
    }

    if (Get-Command Get-WingetPackageInstalledVersion -ErrorAction SilentlyContinue) {
        $wingetVersion = Get-WingetPackageInstalledVersion -PackageId (Get-ClaudeCodeWingetPackageId)
        if (-not [string]::IsNullOrWhiteSpace($wingetVersion)) {
            return [string]$wingetVersion
        }
    }

    return $null
}

function Resolve-ClaudeCodeWingetInstallVerb {
    if (Test-ClaudeCodeWingetPackageInstalled) {
        return 'upgrade'
    }

    return 'install'
}

function Test-ClaudeCodeUpdateAvailable {
    param([string]$CoreLib = '')

    if (-not (Test-ClaudeCodeInstalled)) {
        return $false
    }

    if (-not [string]::IsNullOrWhiteSpace($CoreLib)) {
        Import-ClaudeCodeWingetCore -CoreLib $CoreLib
    }

    if (-not (Get-Command Test-WingetPackageUpdateAvailable -ErrorAction SilentlyContinue)) {
        return $false
    }

    $packageId = Get-ClaudeCodeWingetPackageId
    $installedVersion = Get-ClaudeCodeInstalledVersion
    return (Test-WingetPackageUpdateAvailable -PackageId $packageId `
        -InstalledVersion $(if ($installedVersion) { $installedVersion } else { '' }))
}

function Import-ClaudeCodeWingetCore {
    param([string]$CoreLib)

    if (-not (Get-Command Invoke-WingetDepProcess -ErrorAction SilentlyContinue)) {
        . (Join-Path $CoreLib 'domain\Invoke-ToolDepPackage.ps1')
    }
    if (-not (Get-Command Get-WingetPackageInstalledVersion -ErrorAction SilentlyContinue)) {
        . (Join-Path $CoreLib 'domain\Ensure-ToolDeps.ps1')
    }
    Import-ClaudeCodeDepProgressCore -CoreLib $CoreLib
}

function Import-ClaudeCodeDepProgressCore {
    param([string]$CoreLib)

    if (Get-Command Update-ToolkitDepWingetProgressFromDecision -ErrorAction SilentlyContinue) {
        return
    }

    $importBlock = {
        param([string]$Root)

        $batchPath = Join-Path $Root 'ui\shell\BatchExecution.ps1'
        if (Test-Path -LiteralPath $batchPath) {
            . $batchPath
        }
        if (-not (Get-Command Update-ToolkitDepWingetProgressFromDecision -ErrorAction SilentlyContinue)) {
            $depViewPath = Join-Path $Root 'ui\shell\DepOperationView.ps1'
            if (Test-Path -LiteralPath $depViewPath) {
                . $depViewPath
            }
        }
    }

    $stack = @(Get-PSCallStack)
    if ($stack.Count -gt 1 -and $null -ne $stack[1].InvocationInfo) {
        $callerState = $stack[1].InvocationInfo.MyCommand.SessionState
        if ($null -ne $callerState) {
            $null = $callerState.InvokeScript($importBlock, $CoreLib)
            return
        }
    }

    & $importBlock $CoreLib
}

function New-ClaudeCodeWingetArgumentList {
    param(
        [ValidateSet('install', 'upgrade', 'uninstall')]
        [string]$Verb
    )

    $packageId = Get-ClaudeCodeWingetPackageId
    $args = @($Verb, '--id', $packageId, '-e')
    if ($Verb -in @('install', 'upgrade')) {
        $args += @(
            '--accept-package-agreements'
            '--accept-source-agreements'
            '--silent'
        )
    }
    return @($args)
}

function Invoke-ClaudeCodeWingetProcess {
    param(
        [ValidateSet('install', 'upgrade', 'uninstall')]
        [string]$Verb,
        [scriptblock]$OnOutputLine = $null,
        [scriptblock]$OnUiPoll = $null,
        [scriptblock]$OnChromePulse = $null
    )

    $argumentList = New-ClaudeCodeWingetArgumentList -Verb $Verb
    return Invoke-WingetDepProcess -ArgumentList $argumentList -OnOutputLine $OnOutputLine `
        -OnUiPoll $OnUiPoll -OnChromePulse $OnChromePulse
}

function Invoke-ClaudeCodeCliCommand {
    param(
        [string[]]$ArgumentList,
        [int]$TimeoutMs = 120000,
        [scriptblock]$OnUiPoll = $null,
        [scriptblock]$OnChromePulse = $null
    )

    if (-not (Test-ClaudeCodeCliAvailable)) {
        throw 'claude CLI not found'
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = (Get-Command claude).Source
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

        # 异步读取 stdout/stderr，避免管道塞满死锁；不用 OutputDataReceived 事件，防止批量调用时宿主崩溃
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()

        $deadline = [Environment]::TickCount + [Math]::Max(1000, $TimeoutMs)
        while (-not $process.HasExited) {
            if ([Environment]::TickCount -ge $deadline) {
                try { $process.Kill() } catch {}
                throw 'claude command timed out'
            }

            if ($OnChromePulse) { & $OnChromePulse }
            if ($OnUiPoll) { & $OnUiPoll }
            Start-Sleep -Milliseconds 50
        }

        $null = $process.WaitForExit()
        $stdoutText = $stdoutTask.GetAwaiter().GetResult()
        $stderrText = $stderrTask.GetAwaiter().GetResult()
        $exitCode = [int]$process.ExitCode

        return [pscustomobject]@{
            ExitCode = $exitCode
            Success  = ($exitCode -eq 0)
            StdOut   = $stdoutText
            StdErr   = $stderrText
            Output   = ($stdoutText + $stderrText)
        }
    }
    finally {
        if ($process) {
            try { $process.Dispose() } catch {}
        }
    }
}
