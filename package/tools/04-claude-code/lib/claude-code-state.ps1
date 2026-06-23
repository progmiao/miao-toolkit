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

function Get-ClaudeCodeCliVersion {
    if (-not (Test-ClaudeCodeCliAvailable)) {
        return $null
    }

    try {
        $output = & claude --version 2>&1
        $line = @($output | ForEach-Object { [string]$_ } | Where-Object {
            -not [string]::IsNullOrWhiteSpace($_)
        } | Select-Object -First 1)
        if ([string]::IsNullOrWhiteSpace($line)) { return $null }
        if ($line -match '(\d+\.\d+\.\d+)') {
            return $Matches[1]
        }
        return $line.Trim()
    }
    catch {
        return $null
    }
}

function Test-ClaudeCodeInstalled {
    if (-not (Get-Command Get-WingetPackageInstalledVersion -ErrorAction SilentlyContinue)) {
        return (Test-ClaudeCodeCliAvailable)
    }

    $packageId = Get-ClaudeCodeWingetPackageId
    $wingetVersion = Get-WingetPackageInstalledVersion -PackageId $packageId
    if (-not [string]::IsNullOrWhiteSpace($wingetVersion)) {
        return $true
    }

    return (Test-ClaudeCodeCliAvailable)
}

function Get-ClaudeCodeInstalledVersion {
    if (Get-Command Get-WingetPackageInstalledVersion -ErrorAction SilentlyContinue) {
        $wingetVersion = Get-WingetPackageInstalledVersion -PackageId (Get-ClaudeCodeWingetPackageId)
        if (-not [string]::IsNullOrWhiteSpace($wingetVersion)) {
            return [string]$wingetVersion
        }
    }

    return Get-ClaudeCodeCliVersion
}

function Import-ClaudeCodeWingetCore {
    param([string]$CoreLib)

    if (-not (Get-Command Invoke-WingetDepProcess -ErrorAction SilentlyContinue)) {
        . (Join-Path $CoreLib 'domain\Invoke-ToolDepPackage.ps1')
    }
    if (-not (Get-Command Get-WingetPackageInstalledVersion -ErrorAction SilentlyContinue)) {
        . (Join-Path $CoreLib 'domain\Ensure-ToolDeps.ps1')
    }
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
        [scriptblock]$OnOutputLine = $null
    )

    $argumentList = New-ClaudeCodeWingetArgumentList -Verb $Verb
    return Invoke-WingetDepProcess -ArgumentList $argumentList -OnOutputLine $OnOutputLine
}

function Invoke-ClaudeCodeCliCommand {
    param(
        [string[]]$ArgumentList,
        [int]$TimeoutMs = 120000
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

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    $stdout = New-Object System.Text.StringBuilder
    $stderr = New-Object System.Text.StringBuilder

    $outHandler = {
        if (-not [string]::IsNullOrEmpty($EventArgs.Data)) {
            $null = $stdout.AppendLine($EventArgs.Data)
        }
    }.GetNewClosure()
    $errHandler = {
        if (-not [string]::IsNullOrEmpty($EventArgs.Data)) {
            $null = $stderr.AppendLine($EventArgs.Data)
        }
    }.GetNewClosure()

    $null = $process.add_OutputDataReceived($outHandler)
    $null = $process.add_ErrorDataReceived($errHandler)
    $null = $process.Start()
    $process.BeginOutputReadLine()
    $process.BeginErrorReadLine()

    if (-not $process.WaitForExit($TimeoutMs)) {
        try { $process.Kill() } catch {}
        throw 'claude command timed out'
    }

    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        StdOut   = $stdout.ToString()
        StdErr   = $stderr.ToString()
        Output   = ($stdout.ToString() + $stderr.ToString())
    }
}
