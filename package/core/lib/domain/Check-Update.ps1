# 版本可用性检查（会话内缓存，见 docs/UPDATE.md §六）

function Format-ReleaseDate {
    param([string]$Raw)

    if ([string]::IsNullOrWhiteSpace($Raw)) { return '-' }
    try {
        return ([DateTime]::Parse($Raw)).ToString('yyyy-MM-dd')
    }
    catch {
        if ($Raw -match '^(\d{4}-\d{2}-\d{2})') { return $Matches[1] }
        return $Raw
    }
}

function Normalize-Semver {
    param([string]$Version)

    if ([string]::IsNullOrWhiteSpace($Version)) { return '0.0.0' }
    $v = ($Version -replace '^v', '').Trim()
    $v = ($v -split '-')[0]
    if ($v -match '^\d+(\.\d+){0,2}$') { return $v }
    return $v
}

function Test-VersionIsNewer {
    param(
        [string]$Candidate,
        [string]$Baseline
    )

    try {
        $c = [version](Normalize-Semver $Candidate)
        $b = [version](Normalize-Semver $Baseline)
        return ($c -gt $b)
    }
    catch {
        return ($Candidate -ne $Baseline)
    }
}

function Get-DevMockLatestRelease {
    if (-not $env:MIAO_DEV_LATEST_VERSION) { return $null }

    return [pscustomobject]@{
        Version    = $env:MIAO_DEV_LATEST_VERSION
        ReleasedAt = $(if ($env:MIAO_DEV_LATEST_RELEASED_AT) { $env:MIAO_DEV_LATEST_RELEASED_AT } else { '' })
    }
}

function Get-RemoteLatestRelease {
    param([string]$Repository)

    if ([string]::IsNullOrWhiteSpace($Repository)) { return $null }

    $mock = Get-DevMockLatestRelease
    if ($mock) { return $mock }

    if ($env:MIAO_SKIP_UPDATE_CHECK -eq '1') { return $null }

    $uri = "https://api.github.com/repos/$Repository/releases/latest"
    try {
        $resp = Invoke-RestMethod -Uri $uri -TimeoutSec 3 -Headers @{ 'User-Agent' = (Get-UserAgent) }
        $tag = ($resp.tag_name -replace '^v', '').Trim()
        return [pscustomobject]@{
            Version    = $tag
            ReleasedAt = $resp.published_at
        }
    }
    catch {
        return $null
    }
}

function Reset-UpdateAvailabilityCache {
    $script:UpdateAvailability = $null
    $script:UpdateHintShown = $false
}

function Get-UpdateAvailability {
    param([switch]$ForceRefresh)

    if ($ForceRefresh) {
        Reset-UpdateAvailabilityCache
    }

    if ($script:UpdateAvailability) {
        return $script:UpdateAvailability
    }

    $local = Get-Manifest
    $currentVersion = $local.version
    $currentReleasedAt = Format-ReleaseDate $local.releaseDate

    $remote = Get-RemoteLatestRelease -Repository $local.repository
    $isLatest = $true
    $latestVersion = $currentVersion
    $latestReleasedAt = $currentReleasedAt

    if ($remote -and $remote.Version) {
        $latestVersion = $remote.Version
        $latestReleasedAt = Format-ReleaseDate $remote.ReleasedAt
        $isLatest = -not (Test-VersionIsNewer -Candidate $remote.Version -Baseline $currentVersion)
    }

    $script:UpdateAvailability = [pscustomobject]@{
        IsLatest           = $isLatest
        CurrentVersion     = $currentVersion
        CurrentReleasedAt  = $currentReleasedAt
        LatestVersion      = $latestVersion
        LatestReleasedAt   = $latestReleasedAt
    }

    return $script:UpdateAvailability
}

function Register-UpdateDisplayed {
    $script:UpdateHintShown = $true
}

function Invoke-SessionUpdateHint {
    if ($script:UpdateHintShown) { return }
    if ($env:MIAO_SKIP_UPDATE_CHECK -eq '1') { return }

    $info = Get-UpdateAvailability
    if ($info.IsLatest) { return }

    $message = Get-I18n -Key 'page.update.sessionHint' -Vars @{
        latestVersion  = $info.LatestVersion
        currentVersion = $info.CurrentVersion
    }

    Write-Host $message -ForegroundColor Yellow
    Register-UpdateDisplayed
}

function Test-ShouldCheckUpdate {
    param([string]$CommandHead)
    return $false
}
