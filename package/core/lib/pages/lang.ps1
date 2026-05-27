# 语言选择页

function Invoke-LangPage {
    param([hashtable]$Shell)

    $locales = @((Get-I18nConfig).locales | ForEach-Object { [string]$_ })
    $items = @(
        foreach ($code in $locales) {
            $current = (Get-CurrentLocale -eq $code)
            $mark = if ($current) { ' *' } else { '' }
            [pscustomobject]@{
                id    = $code
                label = "$(Get-LocaleDisplayName $code)$mark"
            }
        }
    )

    $header = New-ToolkitMenuHeader -HideSectionTitle
    Initialize-ToolkitShellBodyView -Shell $Shell `
        -SectionTitle (Get-I18n -Key 'page.lang.sectionTitle') `
        -FooterTemplate DefaultBar
    $renderFooter = New-ShellDefaultFooterRenderer -Shell $Shell -ShowHelp -ShowBack
    $picked = Show-PaginatedMenu -Header $header -Items $items -CountLabel (Get-I18n -Key 'common.unit.item') `
        -GetItemLabel {
            param($Item, $Index)
            return $Item.label
        } `
        -HideColHeader -ToolkitShell $Shell -RenderFooter $renderFooter -EscMeansBack

    if (-not $picked) {
        return (Get-ShellNavMarker -Action 'back')
    }
    if (Test-ShellNavMarker $picked) {
        return $picked
    }

    if ((Get-CurrentLocale) -ne $picked.id) {
        Set-UserLocale $picked.id
        Update-ToolkitShellBrandHeader -Shell $Shell
    }

    return (Get-ShellNavMarker -Action 'back')
}

function Show-LanguagePicker {
    param(
        [switch]$Standalone,
        [hashtable]$ToolkitShell = $null,
        [array]$Tools = @()
    )

    if ($ToolkitShell) {
        return Invoke-LangPage -Shell $ToolkitShell
    }

    if ($Standalone) {
        return (Start-ToolkitShellSession -Tools $Tools -InitialView Lang)
    }

    $locales = @((Get-I18nConfig).locales | ForEach-Object { [string]$_ })
    $items = @(
        foreach ($code in $locales) {
            $current = (Get-CurrentLocale -eq $code)
            $mark = if ($current) { ' *' } else { '' }
            [pscustomobject]@{
                id    = $code
                label = "$(Get-LocaleDisplayName $code)$mark"
            }
        }
    )

    $headerFull = New-ToolkitMenuHeader -SectionTitle (Get-I18n -Key 'page.lang.sectionTitle')
    $picked = Show-PaginatedMenu -Header $headerFull -Items $items -CountLabel (Get-I18n -Key 'common.unit.item') `
        -GetItemLabel {
            param($Item, $Index)
            return $Item.label
        }

    if (-not $picked) {
        return $null
    }
    if (Test-ShellNavMarker $picked) {
        return $null
    }

    if ((Get-CurrentLocale) -eq $picked.id) {
        Write-MessageBlock -Title (Get-I18n -Key 'page.lang.title') `
            -Lines @(Get-I18n -Key 'page.lang.alreadyCurrent' -Vars @{ locale = (Get-LocaleDisplayName $picked.id) }) `
            -TitleColor Yellow
    }
    else {
        Set-UserLocale $picked.id
        Write-MessageBlock -Title (Get-I18n -Key 'page.lang.title') `
            -Lines @(Get-I18n -Key 'page.lang.changed' -Vars @{ locale = (Get-LocaleDisplayName $picked.id) }) `
            -TitleColor Green
    }

    return $picked.id
}

function Invoke-LangCommand {
    param(
        [string[]]$Rest,
        [array]$Tools = @()
    )

    if ($Rest.Count -eq 0) {
        return (Start-ToolkitShellSession -Tools $Tools -InitialView Lang)
    }

    $sub = $Rest[0]
    switch -Regex ($sub) {
        '^(list|ls)$' {
            foreach ($code in @((Get-I18nConfig).locales)) {
                $mark = if ((Get-CurrentLocale) -eq $code) { ' *' } else { '' }
                Write-Host "$code  $(Get-LocaleDisplayName $code)$mark"
            }
            return 0
        }
        '^show$' {
            Write-Host (Get-CurrentLocale)
            return 0
        }
        default {
            try {
                Set-UserLocale $sub
                Write-Host (Get-I18n -Key 'page.lang.changed' -Vars @{ locale = (Get-LocaleDisplayName $sub) })
                return 0
            }
            catch {
                $detail = $_.Exception.Message
                if ([string]::IsNullOrWhiteSpace($detail)) {
                    $detail = $_.Exception.GetType().FullName
                }
                Write-Host (Get-I18n -Key 'error.languageChangeFailed' -Vars @{ detail = $detail }) -ForegroundColor Red
                return 1
            }
        }
    }
}
