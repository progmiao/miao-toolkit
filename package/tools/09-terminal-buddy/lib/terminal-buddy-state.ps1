# terminal-buddy — 安装状态、Gitee Release 与文件操作

function Normalize-TerminalBuddyVersion {
    param([string]$Version)

    $value = [string]$Version
    if ([string]::IsNullOrWhiteSpace($value)) { return '' }
    return $value.Trim().TrimStart('v', 'V')
}

function Resolve-TerminalBuddyExecutable {
    $paths = Get-TerminalBuddyKnownPaths
    if (Test-Path -LiteralPath $paths.ExePath) {
        return [string]$paths.ExePath
    }

    $cmd = Get-Command terminal-buddy -ErrorAction SilentlyContinue
    if ($cmd) {
        return [string]$cmd.Source
    }

    $cmd = Get-Command terminal-buddy.exe -ErrorAction SilentlyContinue
    if ($cmd) {
        return [string]$cmd.Source
    }

    return $null
}

function Test-TerminalBuddyInstalled {
    $exe = Resolve-TerminalBuddyExecutable
    return -not [string]::IsNullOrWhiteSpace($exe)
}

function Get-TerminalBuddyInstalledVersion {
    $exe = Resolve-TerminalBuddyExecutable
    if ([string]::IsNullOrWhiteSpace($exe) -or -not (Test-Path -LiteralPath $exe)) {
        return $null
    }

    try {
        $info = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($exe)
        $version = if ($info.ProductVersion) { $info.ProductVersion } else { $info.FileVersion }
        $normalized = Normalize-TerminalBuddyVersion -Version $version
        if (-not [string]::IsNullOrWhiteSpace($normalized)) {
            return $normalized
        }
    }
    catch {}

    return $null
}

function Get-TerminalBuddyGiteeReleaseApiUrl {
    param([string]$ToolRoot)

    $cfg = Get-TerminalBuddyGiteeConfig -ToolRoot $ToolRoot
    $owner = if ($cfg.owner) { [string]$cfg.owner } else { $script:TerminalBuddyGiteeOwner }
    $repo = if ($cfg.repo) { [string]$cfg.repo } else { $script:TerminalBuddyGiteeRepo }
    return "https://gitee.com/api/v5/repos/$owner/$repo/releases/latest"
}

function Get-TerminalBuddyGiteeDownloadUrl {
    param(
        [string]$Tag,
        [string]$ToolRoot
    )

    $cfg = Get-TerminalBuddyGiteeConfig -ToolRoot $ToolRoot
    $owner = if ($cfg.owner) { [string]$cfg.owner } else { $script:TerminalBuddyGiteeOwner }
    $repo = if ($cfg.repo) { [string]$cfg.repo } else { $script:TerminalBuddyGiteeRepo }
    $asset = if ($cfg.assetName) { [string]$cfg.assetName } else { $script:TerminalBuddyAssetName }
    $tagName = [string]$Tag
    if (-not $tagName.StartsWith('v') -and -not $tagName.StartsWith('V')) {
        $tagName = "v$tagName"
    }

    return "https://gitee.com/$owner/$repo/releases/download/$tagName/$asset"
}

function Get-TerminalBuddyLatestRelease {
    param([string]$ToolRoot)

    $apiUrl = Get-TerminalBuddyGiteeReleaseApiUrl -ToolRoot $ToolRoot
    $release = Invoke-RestMethod -Uri $apiUrl -TimeoutSec $script:TerminalBuddyReleaseApiTimeoutSec
    $tag = Normalize-TerminalBuddyVersion -Version ([string]$release.tag_name)
    $downloadUrl = Get-TerminalBuddyGiteeDownloadUrl -Tag ([string]$release.tag_name) -ToolRoot $ToolRoot

    return [pscustomobject]@{
        Tag         = $tag
        TagRaw      = [string]$release.tag_name
        DownloadUrl = $downloadUrl
        ApiUrl      = $apiUrl
    }
}

function Test-TerminalBuddyNetworkReachable {
    param(
        [string]$Url,
        [int]$TimeoutSec = 8
    )

    $prevProgressPreference = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        $request = [System.Net.HttpWebRequest]::Create($Url)
        $request.Method = 'HEAD'
        $request.Timeout = $TimeoutSec * 1000
        $response = $request.GetResponse()
        try {
            $code = [int]$response.StatusCode
            return ($code -ge 200 -and $code -lt 400)
        }
        finally {
            $response.Close()
        }
    }
    catch {
        return $false
    }
    finally {
        $ProgressPreference = $prevProgressPreference
    }
}

function Compare-TerminalBuddyVersion {
    param(
        [string]$Installed,
        [string]$Latest
    )

    $left = Normalize-TerminalBuddyVersion -Version $Installed
    $right = Normalize-TerminalBuddyVersion -Version $Latest
    if ([string]::IsNullOrWhiteSpace($left)) { return -1 }
    if ([string]::IsNullOrWhiteSpace($right)) { return 0 }

    try {
        return ([version]$left).CompareTo([version]$right)
    }
    catch {
        return [string]::Compare($left, $right, [StringComparison]::OrdinalIgnoreCase)
    }
}

function Resolve-TerminalBuddyUpdateCheck {
    param(
        [string]$ToolRoot,
        [scriptblock]$OnPulse = $null
    )

    if (-not (Test-TerminalBuddyInstalled)) {
        return [pscustomobject]@{
            Available  = $false
            Skipped    = $true
            SkipReason = 'not-installed'
            Latest     = $null
        }
    }

    $installedVersion = Get-TerminalBuddyInstalledVersion
    $apiUrl = Get-TerminalBuddyGiteeReleaseApiUrl -ToolRoot $ToolRoot
    if (-not (Test-TerminalBuddyNetworkReachable -Url $apiUrl)) {
        return [pscustomobject]@{
            Available  = $false
            Skipped    = $true
            SkipReason = 'network'
            Latest     = $null
            Installed  = $installedVersion
        }
    }

    if ($OnPulse) { & $OnPulse }

    try {
        $latest = Get-TerminalBuddyLatestRelease -ToolRoot $ToolRoot
        if ($OnPulse) { & $OnPulse }

        $cmp = Compare-TerminalBuddyVersion -Installed $installedVersion -Latest $latest.Tag
        return [pscustomobject]@{
            Available  = ($cmp -lt 0)
            Skipped    = $false
            SkipReason = ''
            Latest     = $latest
            Installed  = $installedVersion
        }
    }
    catch {
        return [pscustomobject]@{
            Available  = $false
            Skipped    = $true
            SkipReason = 'error'
            Latest     = $null
            Installed  = $installedVersion
            Detail     = [string]$_.Exception.Message
        }
    }
}

function Stop-TerminalBuddyRunningProcesses {
    Get-Process -Name 'terminal-buddy' -ErrorAction SilentlyContinue | ForEach-Object {
        try { $_.CloseMainWindow() | Out-Null } catch {}
    }
    Start-Sleep -Milliseconds 400
    Get-Process -Name 'terminal-buddy' -ErrorAction SilentlyContinue | ForEach-Object {
        try { $_.Kill() } catch {}
    }
}

function Update-TerminalBuddyDownloadProgress {
    param(
        [string]$ToolRoot,
        $Ui,
        $RedrawView,
        [string]$VersionLabel,
        [int]$Percent
    )

    if ($null -eq $Ui) { return }

    $Ui.ItemSubPercent = [Math]::Max(0, [Math]::Min(95, [int]$Percent))
    if ([string]::IsNullOrWhiteSpace($ToolRoot) -or -not $RedrawView) { return }
    if (-not (Get-Command Set-ToolkitDepOperationInFlightStatus -ErrorAction SilentlyContinue)) { return }

    $statusText = Get-TerminalBuddyI18n -ToolRoot $ToolRoot -Key 'terminal-buddy.app.downloadProgress' `
        -Vars @{ version = $VersionLabel; percent = [string]$Ui.ItemSubPercent }
    Set-ToolkitDepOperationInFlightStatus -Ui $Ui -MainText $statusText -AdvanceSpinner
    & $RedrawView
}

function Invoke-TerminalBuddyDownloadFile {
    param(
        [string]$Url,
        [string]$Destination,
        [string]$ToolRoot = '',
        $Ui = $null,
        $RedrawView = $null,
        [string]$VersionLabel = '',
        [scriptblock]$OnPulse = $null
    )

    $prevProgressPreference = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'

    try {
        $destDir = Split-Path -Parent $Destination
        if (-not (Test-Path -LiteralPath $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }

        $tmpPath = "$Destination.download"
        if (Test-Path -LiteralPath $tmpPath) {
            Remove-Item -LiteralPath $tmpPath -Force -ErrorAction SilentlyContinue
        }

        $request = [System.Net.HttpWebRequest]::Create($Url)
        $request.Method = 'GET'
        $request.Timeout = $script:TerminalBuddyDownloadTimeoutSec * 1000
        $request.ReadWriteTimeout = $script:TerminalBuddyDownloadTimeoutSec * 1000
        $response = $request.GetResponse()

        try {
            $total = [int64]$response.ContentLength
            $stream = $response.GetResponseStream()
            $fileStream = [System.IO.File]::Create($tmpPath)
            try {
                $buffer = New-Object byte[] 65536
                $readTotal = [int64]0
                $lastPct = -1
                $lastUiTick = [Environment]::TickCount

                while ($true) {
                    $read = $stream.Read($buffer, 0, $buffer.Length)
                    if ($read -le 0) { break }

                    $fileStream.Write($buffer, 0, $read)
                    $readTotal += $read

                    $nowTick = [Environment]::TickCount
                    if ($nowTick - $lastUiTick -ge 120) {
                        if ($total -gt 0) {
                            $pct = [int][Math]::Min(95, [Math]::Max(1, [Math]::Round(100 * $readTotal / [double]$total)))
                            if ($pct -ne $lastPct) {
                                $lastPct = $pct
                                Update-TerminalBuddyDownloadProgress -ToolRoot $ToolRoot -Ui $Ui `
                                    -RedrawView $RedrawView -VersionLabel $VersionLabel -Percent $pct
                            }
                        }
                        elseif ($Ui) {
                            $Ui.ItemSubPercent = [Math]::Min(95, [int]$Ui.ItemSubPercent + 1)
                            if ($RedrawView) { & $RedrawView }
                        }

                        $lastUiTick = $nowTick
                    }

                    if ($OnPulse -and ($nowTick - $lastUiTick) -ge 80) {
                        & $OnPulse
                    }
                }
            }
            finally {
                $fileStream.Dispose()
            }
        }
        finally {
            $response.Close()
        }

        if ($Ui) {
            Update-TerminalBuddyDownloadProgress -ToolRoot $ToolRoot -Ui $Ui -RedrawView $RedrawView `
                -VersionLabel $VersionLabel -Percent 95
        }

        if (Test-Path -LiteralPath $Destination) {
            Remove-Item -LiteralPath $Destination -Force
        }

        Move-Item -LiteralPath $tmpPath -Destination $Destination -Force
        return $Destination
    }
    finally {
        $ProgressPreference = $prevProgressPreference
    }
}

function Set-TerminalBuddyInstallMarker {
    param(
        [string]$MarkerPath,
        [string]$Version
    )

    $payload = @{
        version   = Normalize-TerminalBuddyVersion -Version $Version
        installed = (Get-Date).ToString('o')
        source    = 'miao-toolkit'
    } | ConvertTo-Json -Compress

    Set-Content -LiteralPath $MarkerPath -Value $payload -Encoding UTF8
}

function New-TerminalBuddyShortcut {
    param(
        [string]$ShortcutPath,
        [string]$ExePath
    )

    if ([string]::IsNullOrWhiteSpace($ShortcutPath)) {
        return $false
    }

    $shortcutDir = Split-Path -Parent $ShortcutPath
    if (-not (Test-Path -LiteralPath $shortcutDir)) {
        New-Item -ItemType Directory -Path $shortcutDir -Force | Out-Null
    }

    $wsh = New-Object -ComObject WScript.Shell
    $shortcut = $wsh.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath = $ExePath
    $shortcut.WorkingDirectory = Split-Path -Parent $ExePath
    $shortcut.Description = 'TerminalBuddy'
    $shortcut.Save()
    return (Test-Path -LiteralPath $ShortcutPath)
}

function New-TerminalBuddyStartMenuShortcut {
    param([string]$ExePath)

    $paths = Get-TerminalBuddyKnownPaths
    return (New-TerminalBuddyShortcut -ShortcutPath $paths.ShortcutPath -ExePath $ExePath)
}

function New-TerminalBuddyDesktopShortcut {
    param([string]$ExePath)

    $paths = Get-TerminalBuddyKnownPaths
    return (New-TerminalBuddyShortcut -ShortcutPath $paths.DesktopShortcutPath -ExePath $ExePath)
}

function Install-TerminalBuddyShortcuts {
    param([string]$ExePath)

    $startMenuOk = New-TerminalBuddyStartMenuShortcut -ExePath $ExePath
    $desktopOk = New-TerminalBuddyDesktopShortcut -ExePath $ExePath
    return @{
        StartMenu = [bool]$startMenuOk
        Desktop   = [bool]$desktopOk
    }
}

function Install-TerminalBuddyRelease {
    param(
        [string]$ToolRoot,
        $Release,
        $Ui = $null,
        $RedrawView = $null,
        [scriptblock]$OnPulse = $null
    )

    $paths = Get-TerminalBuddyKnownPaths
    if (-not (Test-Path -LiteralPath $paths.InstallDir)) {
        New-Item -ItemType Directory -Path $paths.InstallDir -Force | Out-Null
    }

    Stop-TerminalBuddyRunningProcesses
    if ($OnPulse) { & $OnPulse }

    $versionLabel = Normalize-TerminalBuddyVersion -Version $Release.Tag
    Invoke-TerminalBuddyDownloadFile -Url $Release.DownloadUrl -Destination $paths.ExePath `
        -ToolRoot $ToolRoot -Ui $Ui -RedrawView $RedrawView -VersionLabel $versionLabel -OnPulse $OnPulse

    if ($Ui -and $RedrawView -and (Get-Command Set-ToolkitDepOperationInFlightStatus -ErrorAction SilentlyContinue)) {
        Set-ToolkitDepOperationInFlightStatus -Ui $Ui -MainText (Get-TerminalBuddyI18n -ToolRoot $ToolRoot `
            -Key 'terminal-buddy.app.installInProgress' -Vars @{ path = $paths.InstallDir }) -AdvanceSpinner
        & $RedrawView
    }

    Set-TerminalBuddyInstallMarker -MarkerPath $paths.MarkerPath -Version $Release.Tag
    $shortcuts = Install-TerminalBuddyShortcuts -ExePath $paths.ExePath

    if ($Ui) {
        $Ui.ItemSubPercent = 100
        if ($RedrawView) { & $RedrawView }
    }

    return [pscustomobject]@{
        Ok         = $true
        ExePath    = [string]$paths.ExePath
        Version    = $versionLabel
        Shortcuts  = $shortcuts
    }
}

function Uninstall-TerminalBuddyManaged {
    param([scriptblock]$OnPulse = $null)

    $paths = Get-TerminalBuddyKnownPaths
    Stop-TerminalBuddyRunningProcesses
    if ($OnPulse) { & $OnPulse }

    if (Test-Path -LiteralPath $paths.ShortcutPath) {
        Remove-Item -LiteralPath $paths.ShortcutPath -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $paths.DesktopShortcutPath) {
        Remove-Item -LiteralPath $paths.DesktopShortcutPath -Force -ErrorAction SilentlyContinue
    }

    $removed = $false
    if (Test-Path -LiteralPath $paths.InstallDir) {
        Remove-Item -LiteralPath $paths.InstallDir -Recurse -Force -ErrorAction SilentlyContinue
        $removed = -not (Test-Path -LiteralPath $paths.InstallDir)
    }

    return [pscustomobject]@{
        Ok      = $removed -or -not (Test-TerminalBuddyInstalled)
        Removed = $removed
    }
}
