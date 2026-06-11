# 工具箱自身更新页（miao sys update）

function Get-ToolkitUpdateStatusLines {
    param($Info)

    if (-not $Info) {
        return @((New-BrandedHelpLine -Text (Get-I18n -Key 'page.update.checkFailed')))
    }

    $lines = @(
        (New-BrandedHelpLine -Text (Format-I18nLabelLine -LabelKey 'common.version' -Value "v$($Info.CurrentVersion)"))
        (New-BrandedHelpLine -Text (Format-I18nLabelLine -LabelKey 'common.releaseDate' -Value $Info.CurrentReleasedAt))
    )

    if ($Info.IsLatest) {
        $lines += New-BrandedHelpLine -Text (Get-I18n -Key 'page.update.statusLatest')
    }
    else {
        $lines += New-BrandedHelpLine -Text (Get-I18n -Key 'page.update.statusAvailable' -Vars @{
            latestVersion = $Info.LatestVersion
        })
        if ($Info.LatestReleasedAt -and $Info.LatestReleasedAt -ne '-') {
            $lines += New-BrandedHelpLine -Text "$(Get-I18n -Key 'page.update.latestReleaseLabel'): $($Info.LatestReleasedAt)"
        }
    }

    $lines += New-BrandedHelpLine -Text (Get-I18n -Key 'page.update.executeNotImplemented')
    return $lines
}

function Invoke-UpdatePage {
    param([hashtable]$Shell)

    Reset-UpdateAvailabilityCache
    $info = Get-UpdateAvailability
    $lines = Get-ToolkitUpdateStatusLines -Info $info
    return Invoke-ToolkitShellContentView -Shell $Shell `
        -SectionTitle (Get-I18n -Key 'page.update.pageTitle') `
        -Lines $lines `
        -ToolbarConfig (New-ShellSystemToolbarConfig -HideSystem -HideHelp)
}

function Invoke-ShellUpdateView {
    param([hashtable]$Shell)

    return Invoke-UpdatePage -Shell $Shell
}

function Invoke-ToolkitSysUpdate {
    param([array]$Tools = @())

    return (Start-ToolkitShellSession -Tools $Tools -InitialView Update)
}
