# 更新页

function Get-ToolkitUpdateStatusLines {
    param($Info)

    if (-not $Info) {
        return @((New-BrandedHelpLine -Text (Get-I18n -Key 'update.checkFailed')))
    }

    $lines = @(
        (New-BrandedHelpLine -Text "$(Get-I18n -Key 'settings.versionLabel'): v$($Info.CurrentVersion)")
        (New-BrandedHelpLine -Text "$(Get-I18n -Key 'settings.releaseDateLabel'): $($Info.CurrentReleasedAt)")
    )

    if ($Info.IsLatest) {
        $lines += New-BrandedHelpLine -Text (Get-I18n -Key 'update.statusLatest')
    }
    else {
        $lines += New-BrandedHelpLine -Text (Get-I18n -Key 'update.statusAvailable' -Vars @{
            latestVersion = $Info.LatestVersion
        })
        if ($Info.LatestReleasedAt -and $Info.LatestReleasedAt -ne '-') {
            $lines += New-BrandedHelpLine -Text "$(Get-I18n -Key 'update.latestReleaseLabel'): $($Info.LatestReleasedAt)"
        }
    }

    $lines += New-BrandedHelpLine -Text (Get-I18n -Key 'update.executePlaceholder')
    return $lines
}

function Invoke-UpdatePage {
    param([hashtable]$Shell)

    Reset-UpdateAvailabilityCache
    $info = Get-UpdateAvailability
    $lines = Get-ToolkitUpdateStatusLines -Info $info
    return Invoke-ToolkitShellContentView -Shell $Shell `
        -SectionTitle (Get-I18n -Key 'update.pageTitle') `
        -Lines $lines -ShowBack
}

function Invoke-ShellUpdateView {
    param([hashtable]$Shell)

    return Invoke-UpdatePage -Shell $Shell
}

function Start-ToolkitUpdatePage {
    param(
        [switch]$FromSettings,
        [switch]$Preview,
        [hashtable]$Shell = $null
    )

    Reset-UpdateAvailabilityCache
    $info = Get-UpdateAvailability
    $lines = Get-ToolkitUpdateStatusLines -Info $info

    if ($Shell) {
        return Invoke-UpdatePage -Shell $Shell
    }

    $letterKeys = @{}
    if ($FromSettings) {
        $letterKeys['s'] = New-SettingsMenuEntry
    }

    $null = Show-BrandedContentPage -SectionTitle (Get-I18n -Key 'update.pageTitle') `
        -Lines $lines -LetterKeys $letterKeys

    return 0
}

function Invoke-ToolkitUpdate {
    param(
        [switch]$FromSettings,
        [switch]$Preview
    )

    if ($FromSettings) {
        return (Start-ToolkitUpdatePage -FromSettings -Preview:$Preview)
    }

    Invoke-StandalonePage {
        param([hashtable]$Shell)

        $nav = Invoke-UpdatePage -Shell $Shell
        if (Test-ShellNavMarker $nav 'quit') { Invoke-MiaoShellQuit }
    }

    return 0
}
