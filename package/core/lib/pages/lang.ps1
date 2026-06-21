# 语言选择页（单选列表；摘要列标记当前语种）

function Get-LangLocaleMenuItems {
    return @(
        foreach ($entry in @(Get-ToolkitLocaleRegistry)) {
            [pscustomobject]@{
                command     = [string]$entry.code
                name        = [string]$entry.name
                enabled     = $true
            }
        }
    )
}

function Get-LangLocaleSummaryText {
    param([string]$LocaleCode)

    if ((Get-CurrentLocale) -eq $LocaleCode) {
        return (Get-I18n -Key 'page.lang.inUse')
    }
    return ''
}

function Get-LangListRows {
    return ConvertTo-ShellListRows -Items @(Get-LangLocaleMenuItems) -KeepSource -MapCells {
        param($Item, [int]$Index)
        @(
            (Get-ShellListItemCommand $Item)
            [string]$Item.name
            (Get-LangLocaleSummaryText -LocaleCode $Item.command)
        )
    }
}

function Invoke-LangPage {
    param([hashtable]$Shell)

    $toolbar = New-ShellSystemToolbarConfig -HideSystem

    $currentLocale = Get-CurrentLocale
    if (-not $Shell.HeaderLocale -or $Shell.HeaderLocale -ne $currentLocale) {
        Clear-ShellSingleSelectListCache -Shell $Shell -CacheKey 'Lang'
    }

    $picked = Invoke-ShellSingleSelectList -Shell $Shell `
        -SectionTitle (Format-I18nSelectLanguageSectionTitle) `
        -Rows (Get-LangListRows) `
        -CacheKey 'Lang' `
        -ColumnLayout (New-ShellListColumnLayout -Preset MenuList) `
        -ToolbarConfig $toolbar

    if (-not $picked) {
        return (Get-ShellNavMarker -Action 'back')
    }
    if (Test-ShellNavMarker $picked) {
        return $picked
    }

    if ((Get-CurrentLocale) -ne $picked.command) {
        Set-UserLocale $picked.command
        $Shell['HeaderLocale'] = (Get-CurrentLocale)
        Clear-ShellSingleSelectListCache -Shell $Shell -CacheKey 'Lang'
        Clear-ShellSingleSelectListCache -Shell $Shell -CacheKey 'Home'
        Clear-ShellSingleSelectListCache -Shell $Shell -CacheKey 'Sys'
        Clear-ShellSingleSelectListCache -Shell $Shell -CacheKey 'Node'
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

    $picked = Show-LanguageMenu -WithSectionTitle

    if (-not $picked) {
        return $null
    }
    if (Test-ShellNavMarker $picked) {
        return $null
    }

    if ((Get-CurrentLocale) -eq $picked.command) {
        Write-MessageBlock -Title (Get-I18n -Key 'common.language') `
            -Lines @(Get-I18n -Key 'page.lang.alreadyCurrent' -Vars @{ locale = (Get-LocaleDisplayName $picked.command) }) `
            -TitleColor Yellow
    }
    else {
        Set-UserLocale $picked.command
        Write-MessageBlock -Title (Get-I18n -Key 'common.language') `
            -Lines @(Get-I18n -Key 'page.lang.changed' -Vars @{ locale = (Get-LocaleDisplayName $picked.command) }) `
            -TitleColor Green
    }

    return $picked.command
}

function Show-LanguageMenu {
    param(
        [hashtable]$ToolkitShell = $null,
        [switch]$WithSectionTitle
    )

    if ($ToolkitShell) {
        return Invoke-LangPage -Shell $ToolkitShell
    }

    $header = if ($WithSectionTitle) {
        New-ToolkitMenuHeader -SectionTitle (Format-I18nSelectLanguageSectionTitle)
    }
    else {
        New-ToolkitMenuHeader -HideSectionTitle
    }

    $items = @(Get-LangLocaleMenuItems)
    return Show-PaginatedMenu -Header $header -Items $items -CountLabel (Get-I18n -Key 'common.piece') `
        -HideColHeader `
        -GetItemLabel {
            param($Item, [int]$Index)
            $summary = Get-LangLocaleSummaryText -LocaleCode $Item.command
            "$(Get-ShellListItemCommand $Item)    $($Item.name)    $summary"
        }
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
            $inUse = Get-I18n -Key 'page.lang.inUse'
            foreach ($entry in @(Get-ToolkitLocaleRegistry)) {
                $code = [string]$entry.code
                $status = if ((Get-CurrentLocale) -eq $code) { $inUse } else { '' }
                Write-Host "$code  $([string]$entry.name)  $status"
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
                Write-Host (Get-I18n -Key 'message.languageChangeFailed' -Vars @{ detail = $detail }) -ForegroundColor Red
                return 1
            }
        }
    }
}
