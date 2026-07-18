function Resolve-ToolDependencyPackages {
    param($Dependencies)

    if ($null -eq $Dependencies) { return @() }

    if ($Dependencies -is [System.Array]) {
        return @($Dependencies)
    }

    if ($null -ne $Dependencies.PSObject.Properties['packages']) {
        return @($Dependencies.packages)
    }

    return @()
}

function Get-ToolDependencyPackages {
    param($Tool)

    if (-not $Tool) { return @() }
    return @(Resolve-ToolDependencyPackages -Dependencies $Tool.dependencies)
}

function Get-ToolDependencyMenus {
    param($Tool)

    if (-not $Tool -or -not $Tool.dependencies) { return $null }

    if ($null -ne $Tool.dependencies.PSObject.Properties['menus']) {
        return $Tool.dependencies.menus
    }

    if ($Tool.deps) { return $Tool.deps }

    return $null
}

function Get-ToolHasExternalDeps {
    param($Tool)

    if ($Tool.requiresInstall -eq $false) { return $false }
    return (@(Get-ToolDependencyPackages -Tool $Tool).Count -gt 0)
}

function Test-ToolDeps {
    param($Tool)

    if ($Tool.requiresInstall -eq $false) { return $true }
    if (-not (Get-ToolHasExternalDeps $Tool)) { return $true }

    foreach ($dep in @(Get-ToolDependencyPackages -Tool $Tool)) {
        if (-not $dep.checkCommand) { continue }
        $parts = $dep.checkCommand -split '\s+', 2
        $exe = $parts[0]
        if (-not (Get-Command $exe -ErrorAction SilentlyContinue)) {
            return $false
        }
    }
    return $true
}

function Get-WingetPackageInstalledVersionFromListText {
    param(
        [string]$Text,
        [string]$PackageId
    )

    if ([string]::IsNullOrWhiteSpace($Text) -or [string]::IsNullOrWhiteSpace($PackageId)) {
        return $null
    }

    $escapedId = [regex]::Escape($PackageId)
    foreach ($line in @($Text -split "`r?`n")) {
        $trim = [string]$line.Trim()
        if ([string]::IsNullOrWhiteSpace($trim)) { continue }
        if ($trim -match '(?i)(Usage:|使用方法:|无法识别参数|--output|Unknown .*argument|Windows Package Manager|Windows 程序包管理器|版权所有|Copyright \(C\)|----|名称\s+ID|Name\s+Id\s+)') {
            continue
        }
        if ($trim -notmatch $escapedId) { continue }
        if ($trim -match "$escapedId\s+(\d+(?:\.\d+)*)") {
            return [string]$Matches[1]
        }
    }

    return $null
}

function Get-WingetPackageInstalledVersion {
    param([string]$PackageId)

    if ([string]::IsNullOrWhiteSpace($PackageId)) { return $null }
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { return $null }

    try {
        $output = & winget list --id $PackageId -e --disable-interactivity --accept-source-agreements --output json 2>&1 |
            Out-String
        if ($output -and $output -notmatch '(?i)无法识别参数.*--output|Unknown .*argument.*--output') {
            $data = $output | ConvertFrom-Json
            if ($data.Sources) {
                foreach ($src in @($data.Sources)) {
                    foreach ($pkg in @($src.Packages)) {
                        if ($pkg.Version) {
                            return [string]$pkg.Version
                        }
                    }
                }
            }
        }
    }
    catch {
        # fall through to text parsing
    }

    try {
        $textOutput = & winget list --id $PackageId -e --disable-interactivity --accept-source-agreements 2>&1 |
            Out-String
        return Get-WingetPackageInstalledVersionFromListText -Text $textOutput -PackageId $PackageId
    }
    catch {
        return $null
    }
}

$script:WingetUpdateCheckNetworkPreflightSec = 5
$script:WingetUpdateCheckCommandTimeoutSec = 15

function Invoke-WingetCliWithTimeout {
    param(
        [Parameter(Mandatory)]
        [string[]]$ArgumentList,
        [int]$TimeoutSec = 0,
        [scriptblock]$OnPulse = $null
    )

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        return @{
            TimedOut = $false
            ExitCode = -1
            Output   = ''
            Success  = $false
        }
    }

    if ($TimeoutSec -le 0) {
        try {
            $output = & winget @ArgumentList 2>&1 | Out-String
            $exitCode = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
            return @{
                TimedOut = $false
                ExitCode = $exitCode
                Output   = [string]$output
                Success  = ($exitCode -eq 0)
            }
        }
        catch {
            return @{
                TimedOut = $false
                ExitCode = -1
                Output   = [string]$_.Exception.Message
                Success  = $false
            }
        }
    }

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

    $process = $null
    try {
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $psi
        $null = $process.Start()

        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $deadline = [Environment]::TickCount + ($TimeoutSec * 1000)

        while (-not $process.HasExited) {
            if ([Environment]::TickCount -ge $deadline) {
                try { $process.Kill() } catch {}
                return @{
                    TimedOut = $true
                    ExitCode = -1
                    Output   = ''
                    Success  = $false
                }
            }
            if ($OnPulse) { & $OnPulse }
            Start-Sleep -Milliseconds 50
        }

        $null = $process.WaitForExit()
        $output = ($stdoutTask.GetAwaiter().GetResult() + $stderrTask.GetAwaiter().GetResult())
        $exitCode = [int]$process.ExitCode
        return @{
            TimedOut = $false
            ExitCode = $exitCode
            Output   = [string]$output
            Success  = ($exitCode -eq 0)
        }
    }
    catch {
        return @{
            TimedOut = $false
            ExitCode = -1
            Output   = [string]$_.Exception.Message
            Success  = $false
        }
    }
    finally {
        if ($process) {
            try { $process.Dispose() } catch {}
        }
    }
}

function Test-WingetCatalogNetworkReachable {
    param(
        [int]$TimeoutSec = 0,
        [scriptblock]$OnPulse = $null
    )

    $timeout = if ($TimeoutSec -gt 0) { $TimeoutSec } else { $script:WingetUpdateCheckNetworkPreflightSec }
    $timeout = [Math]::Max(2, [int]$timeout)

    $urls = @(
        'https://cdn.winget.microsoft.com/cache/'
        'https://www.microsoft.com'
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

function Get-WingetPackageLatestVersion {
    param(
        [string]$PackageId,
        [int]$CommandTimeoutSec = 0,
        [scriptblock]$OnPulse = $null
    )

    if ([string]::IsNullOrWhiteSpace($PackageId)) { return $null }
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { return $null }

    try {
        $args = @(
            'show'
            '--id'
            $PackageId
            '-e'
            '--disable-interactivity'
            '--accept-source-agreements'
            '--output'
            'json'
        )
        $wingetResult = if ($CommandTimeoutSec -gt 0) {
            Invoke-WingetCliWithTimeout -ArgumentList $args -TimeoutSec $CommandTimeoutSec -OnPulse $OnPulse
        }
        else {
            $output = & winget @args 2>&1 | Out-String
            @{
                TimedOut = $false
                Output   = [string]$output
            }
        }

        if ($wingetResult.TimedOut) { return $null }
        $output = [string]$wingetResult.Output
        if (-not $output) { return $null }

        $data = $output | ConvertFrom-Json
        if ($data.Versions) {
            foreach ($ver in @($data.Versions)) {
                if ($ver.PackageVersion) {
                    return [string]$ver.PackageVersion
                }
            }
        }
        if ($data.Version) {
            return [string]$data.Version
        }
    }
    catch {
        return $null
    }

    return $null
}

function Test-WingetPackageUpdateAvailableCore {
    param(
        [string]$PackageId,
        [string]$InstalledVersion = '',
        [int]$CommandTimeoutSec = 0,
        [scriptblock]$OnPulse = $null
    )

    if ([string]::IsNullOrWhiteSpace($PackageId)) {
        return @{ Available = $false; TimedOut = $false }
    }
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        return @{ Available = $false; TimedOut = $false }
    }

    if (-not [string]::IsNullOrWhiteSpace($InstalledVersion)) {
        $latest = Get-WingetPackageLatestVersion -PackageId $PackageId `
            -CommandTimeoutSec $CommandTimeoutSec -OnPulse $OnPulse
        if ($latest) {
            $available = Test-VersionIsNewer -Candidate $latest -Baseline $InstalledVersion
            return @{ Available = [bool]$available; TimedOut = $false }
        }
        if ($CommandTimeoutSec -gt 0) {
            $probeArgs = @(
                'show'
                '--id'
                $PackageId
                '-e'
                '--disable-interactivity'
                '--accept-source-agreements'
                '--output'
                'json'
            )
            $probe = Invoke-WingetCliWithTimeout -ArgumentList $probeArgs `
                -TimeoutSec $CommandTimeoutSec -OnPulse $OnPulse
            if ($probe.TimedOut) {
                return @{ Available = $false; TimedOut = $true }
            }
        }
    }

    try {
        $upgradeArgs = @(
            'upgrade'
            '--id'
            $PackageId
            '--disable-interactivity'
            '--accept-source-agreements'
        )
        $wingetResult = if ($CommandTimeoutSec -gt 0) {
            Invoke-WingetCliWithTimeout -ArgumentList $upgradeArgs -TimeoutSec $CommandTimeoutSec -OnPulse $OnPulse
        }
        else {
            $output = & winget @upgradeArgs 2>&1 | Out-String
            @{
                TimedOut = $false
                Output   = [string]$output
                ExitCode = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
            }
        }

        if ($wingetResult.TimedOut) {
            return @{ Available = $false; TimedOut = $true }
        }

        $output = [string]$wingetResult.Output
        if ($output -match 'No applicable upgrade|No available upgrade|没有适用的升级|找不到可用的升级|没有可用的升级') {
            return @{ Available = $false; TimedOut = $false }
        }
        $exitCode = if ($null -ne $wingetResult.ExitCode) { [int]$wingetResult.ExitCode } else { 0 }
        if ($exitCode -eq -1978335189) {
            return @{ Available = $false; TimedOut = $false }
        }
        return @{ Available = ($exitCode -eq 0); TimedOut = $false }
    }
    catch {
        return @{ Available = $false; TimedOut = $false }
    }
}

function Resolve-WingetPackageUpdateCheck {
    param(
        [string]$PackageId,
        [string]$InstalledVersion = '',
        [int]$NetworkPreflightTimeoutSec = 0,
        [int]$CommandTimeoutSec = 0,
        [switch]$SkipNetworkPreflight,
        [scriptblock]$OnPulse = $null
    )

    $networkTimeout = if ($NetworkPreflightTimeoutSec -gt 0) {
        $NetworkPreflightTimeoutSec
    }
    else {
        $script:WingetUpdateCheckNetworkPreflightSec
    }
    $cmdTimeout = if ($CommandTimeoutSec -gt 0) {
        $CommandTimeoutSec
    }
    else {
        $script:WingetUpdateCheckCommandTimeoutSec
    }

    if (-not $SkipNetworkPreflight) {
        if ($OnPulse) { & $OnPulse }
        if (-not (Test-WingetCatalogNetworkReachable -TimeoutSec $networkTimeout -OnPulse $OnPulse)) {
            return @{
                Available  = $false
                Skipped    = $true
                SkipReason = 'network'
                Detail     = ''
            }
        }
    }

    if ($OnPulse) { & $OnPulse }
    $coreResult = Test-WingetPackageUpdateAvailableCore -PackageId $PackageId `
        -InstalledVersion $InstalledVersion -CommandTimeoutSec $cmdTimeout -OnPulse $OnPulse

    if ($coreResult.TimedOut) {
        return @{
            Available  = $false
            Skipped    = $true
            SkipReason = 'timeout'
            Detail     = ''
        }
    }

    return @{
        Available  = [bool]$coreResult.Available
        Skipped    = $false
        SkipReason = ''
        Detail     = ''
    }
}

function Test-WingetPackageUpdateAvailable {
    param(
        [string]$PackageId,
        [string]$InstalledVersion = ''
    )

    if ([string]::IsNullOrWhiteSpace($PackageId)) { return $false }
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { return $false }

    $coreResult = Test-WingetPackageUpdateAvailableCore -PackageId $PackageId `
        -InstalledVersion $InstalledVersion
    return [bool]$coreResult.Available
}

function Test-WingetDepResultIsAlreadyLatest {
    param($Result)

    if (-not $Result) { return $false }
    if ($Result.Success) { return $false }

    foreach ($line in @($Result.Lines)) {
        if ([string]$line -match 'No applicable upgrade|No available upgrade|没有适用的升级|找不到可用的升级|没有可用的升级|already installed') {
            return $true
        }
    }

    $code = $Result.ExitCode
    if ($null -ne $code -and [int]$code -in @(-1978335189, -1978335188)) {
        return $true
    }

    return $false
}

function Test-WingetDepResultNoApplicableInstaller {
    param($Result)

    if (-not $Result) { return $false }
    if ($Result.Success) { return $false }

    foreach ($line in @($Result.Lines)) {
        if ([string]$line -match '找不到适用的安装程序|No applicable installer') {
            return $true
        }
    }

    $code = $Result.ExitCode
    if ($null -ne $code -and [int]$code -eq -1978335216) {
        return $true
    }

    return $false
}

function Test-WingetDepResultIsUacDeclined {
    param($Result)

    if (-not $Result) { return $false }
    if ($Result.Success) { return $false }

    $code = $Result.ExitCode
    if ($null -ne $code) {
        $intCode = [int]$code
        if ($intCode -in @(1223, -2147023673)) {
            return $true
        }
    }

    foreach ($line in @($Result.Lines)) {
        $trim = [string]$line
        if ($trim -match 'access\s+denied|拒绝访问|requires elevation|需要提升|UAC|用户拒绝|The operation was canceled by the user') {
            return $true
        }
    }

    return $false
}

function Test-WingetDepExitCodeIsInstallerUserAbort {
    param($ExitCode)

    if ($null -eq $ExitCode) { return $false }
    return [int]$ExitCode -in @(1602, 1603)
}

function Test-WingetDepResultIsUserCancelled {
    param($Result)

    if (-not $Result) { return $false }
    if ($Result.Cancelled) { return $true }

    foreach ($line in @($Result.Lines)) {
        $trim = [string]$line
        if ($trim -match 'cancelled|canceled|已取消|用户取消|operation was cancelled|Operation cancelled') {
            return $true
        }
        if ($trim -match '退出代码为:\s*160[23]|exit code.*160[23]|exit code is:\s*160[23]') {
            return $true
        }
        if ($trim -match '(安装失败|Install failed|卸载失败|Uninstall failed).*(1602|1603)|(1602|1603).*(安装失败|Install failed|卸载失败|Uninstall failed)') {
            return $true
        }
    }

    $code = $Result.ExitCode
    if ($null -ne $code) {
        $intCode = [int]$code
        if ($intCode -in @(-1978335212, -1978335186, -1978335231, -1978335189, -1978335188)) {
            return $true
        }
        if (Test-WingetDepExitCodeIsInstallerUserAbort -ExitCode $intCode) {
            return $true
        }
    }

    return $false
}

function Get-WingetDepResultDeclineKind {
    param($Result)

    if (-not $Result -or $Result.Success) { return $null }
    if (Test-WingetDepResultIsUacDeclined -Result $Result) { return 'uac' }
    if (Test-WingetDepResultIsUserCancelled -Result $Result) { return 'user' }
    return $null
}

function Test-WingetDepResultIsAlreadyRemoved {
    param($Result)

    if (-not $Result) { return $false }
    if ($Result.Success) { return $false }

    foreach ($line in @($Result.Lines)) {
        if ([string]$line -match 'not installed|No installed package|No package found|未安装|没有安装|找不到.*包|找不到.*应用|cannot be found') {
            return $true
        }
    }

    return $false
}

function Test-WingetDepResultReportsUninstallSuccess {
    param($Result)

    if (-not $Result) { return $false }

    foreach ($line in @($Result.Lines)) {
        if ([string]$line -match '卸载成功|已成功卸载|Successfully uninstalled|uninstalled successfully|Uninstall successful') {
            return $true
        }
    }

    return $false
}

function Test-ToolDepPackageRemovedAfterAction {
    param($Package)

    if (-not $Package) { return $false }

    $packageId = $null
    if ($Package.install -and $Package.install.packageId) {
        $packageId = [string]$Package.install.packageId
    }

    if (-not [string]::IsNullOrWhiteSpace($packageId)) {
        $version = Get-WingetPackageInstalledVersion -PackageId $packageId
        return [string]::IsNullOrWhiteSpace($version)
    }

    $checkCommand = if ($Package.checkCommand) { [string]$Package.checkCommand } else { '' }
    if ($checkCommand) {
        return -not (Test-ToolDepCommandAvailable -CheckCommand $checkCommand)
    }

    return $false
}

function Get-ToolDependencyStatus {
    param($Tool)

    if (-not (Get-ToolHasExternalDeps $Tool)) {
        return 'installed'
    }

    if (Get-ToolDepInstalled $Tool) {
        return 'installed'
    }

    return 'notInstalled'
}

function Invoke-ToolInstall {
    param(
        $Tool,
        [hashtable]$Shell = $null,
        [string]$SectionTitle = ''
    )

    if (-not (Get-ToolHasExternalDeps $Tool)) { return $true }

    return Start-ToolkitDepOperation -Tool $Tool -Intent install -Shell $Shell `
        -SectionTitle $SectionTitle
}

function Invoke-ToolUpdate {
    param(
        $Tool,
        [hashtable]$Shell = $null,
        [string]$SectionTitle = ''
    )

    if (-not (Get-ToolHasExternalDeps $Tool)) { return $true }

    return Start-ToolkitDepOperation -Tool $Tool -Intent update -Shell $Shell `
        -SectionTitle $SectionTitle
}

function Ensure-ToolDeps {
    param($Tool)

    if ($env:MIAO_SKIP_DEPS -eq '1') {
        return $true
    }

    return (Get-ToolDepInstalled $Tool)
}
