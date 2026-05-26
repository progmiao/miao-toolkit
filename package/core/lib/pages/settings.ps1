# 设置 hub 页

function New-SettingsMenuEntry {
    return [pscustomobject]@{
        _kind       = 'settings'
        id          = 'settings'
        displayName = (Get-I18n -Key 'settings.menuEntry')
        summary     = (Get-I18n -Key 'settings.menuEntrySummary')
    }
}

function Test-IsSettingsMenuEntry {
    param($Item)
    return ($Item -and $Item._kind -eq 'settings')
}

function Get-SettingsActions {
    return @(
        [pscustomobject]@{
            id      = 'lang'
            label   = (Get-I18n -Key 'settings.action.lang')
            summary = (Get-I18n -Key 'settings.action.langSummary')
            enabled = $true
        }
        [pscustomobject]@{
            id      = 'version'
            label   = (Get-I18n -Key 'settings.action.version')
            summary = (Get-I18n -Key 'settings.action.versionSummary')
            enabled = $true
        }
        [pscustomobject]@{
            id      = 'update'
            label   = (Get-I18n -Key 'settings.action.update')
            summary = (Get-I18n -Key 'settings.action.updateSummary')
            enabled = $true
        }
        [pscustomobject]@{
            id      = 'help'
            label   = (Get-I18n -Key 'settings.action.help')
            summary = (Get-I18n -Key 'settings.action.helpSummary')
            enabled = $true
        }
        [pscustomobject]@{
            id      = 'install'
            label   = (Get-I18n -Key 'settings.action.install')
            summary = (Get-I18n -Key 'settings.action.installSummary')
            enabled = $true
        }
    )
}

function Format-SettingsActionLabel {
    param($Action, [int]$Index)
    return "$($Action.label)    $($Action.summary)"
}

function Test-SettingsActionEnabled {
    param($Action, [int]$Index)
    return [bool]$Action.enabled
}

function Show-SettingsMenu {
    param(
        [hashtable]$ToolkitShell = $null,
        [scriptblock]$RenderFooter = $null,
        [switch]$EscMeansBack
    )

    $header = New-ToolkitMenuHeader -HideSectionTitle
    $actions = @(Get-SettingsActions)

    if ($ToolkitShell) {
        return Show-PaginatedMenu -Header $header -Items $actions -CountLabel (Get-I18n -Key 'menu.countItems') `
            -GetItemLabel ${function:Format-SettingsActionLabel} `
            -TestItemEnabled ${function:Test-SettingsActionEnabled} `
            -HideColHeader -ToolkitShell $ToolkitShell -RenderFooter $RenderFooter `
            -EscMeansBack:$EscMeansBack `
            -LetterKeys @{ h = (Get-ShellNavMarker -Action 'help') }
    }

    $headerFull = New-ToolkitMenuHeader -SectionTitle (Get-I18n -Key 'settings.sectionTitle')
    return Show-PaginatedMenu -Header $headerFull -Items $actions -CountLabel (Get-I18n -Key 'menu.countItems') `
        -GetItemLabel ${function:Format-SettingsActionLabel} `
        -TestItemEnabled ${function:Test-SettingsActionEnabled}
}

function Invoke-SettingsPage {
    param(
        [hashtable]$Shell,
        [array]$Tools,
        [switch]$Preview
    )

    $renderFooter = New-ShellDefaultFooterRenderer -Shell $Shell -ShowHelp -ShowBack

    while ($true) {
        Initialize-ToolkitShellBodyView -Shell $Shell `
            -SectionTitle (Get-I18n -Key 'settings.sectionTitle') `
            -FooterTemplate DefaultBar

        $picked = Show-SettingsMenu -ToolkitShell $Shell -RenderFooter $renderFooter -EscMeansBack

        if ($null -eq $picked) {
            return (Get-ShellNavMarker -Action 'back')
        }
        if (Test-ShellNavMarker $picked) {
            return $picked
        }

        switch ($picked.id) {
            'help' {
                return (Get-ShellNavMarker -Action 'help')
            }
            'update' {
                return (Get-ShellNavMarker -Action 'update')
            }
            'lang' {
                return (Get-ShellNavMarker -Action 'lang')
            }
            default {
                Invoke-SettingsAction -Action $picked -Tools $Tools -Preview:$Preview
            }
        }
    }
}

function Invoke-ShellSettingsView {
    param(
        [hashtable]$Shell,
        [array]$Tools,
        [switch]$Preview
    )

    return Invoke-SettingsPage -Shell $Shell -Tools $Tools -Preview:$Preview
}

function Wait-SettingsContinue {
    Write-Host ''
    Read-Host (Get-I18n -Key 'settings.pressEnterToBack')
}

function Show-ToolkitVersionInfo {
    $manifest = Get-Manifest
    $released = Format-ReleaseDate $manifest.releaseDate
    $lines = @(
        "$(Get-I18n -Key 'settings.versionLabel'): $($manifest.version)"
        "$(Get-I18n -Key 'settings.releaseDateLabel'): $released"
        (Format-ProductAuthorLine)
        (Format-ProductEmailLine)
        "$(Get-I18n -Key 'settings.localeLabel'): $(Get-CurrentLocale)"
    )

    Write-MessageBlock -Title (Get-I18n -Key 'settings.versionTitle') -Lines $lines -TitleColor Cyan
    Wait-SettingsContinue
}

function Write-ToolkitVersionLine {
    Write-Host (Get-Manifest).version
}

function Invoke-SettingsAction {
    param(
        $Action,
        [array]$Tools,
        [switch]$Preview
    )

    switch ($Action.id) {
        'lang' {
            Show-LanguagePicker -Standalone | Out-Null
        }
        'version' {
            Show-ToolkitVersionInfo
        }
        'update' {
            Invoke-ToolkitUpdate -FromSettings -Preview:$Preview | Out-Null
        }
        'help' {
            $next = Show-ToolkitHelpPage -Tools $Tools
            if (Test-IsSettingsMenuEntry $next) {
                Start-SettingsSession -Tools $Tools -Preview:$Preview
            }
        }
        'install' {
            return (Get-ShellNavMarker -Action 'install')
        }
    }
}

function Start-SettingsSession {
    param(
        [array]$Tools,
        [switch]$Preview
    )

    return (Start-ToolkitShellSession -Tools $Tools -Preview:$Preview -InitialView Settings)
}
