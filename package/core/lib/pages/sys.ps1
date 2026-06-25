# 系统 hub 页（单选列表 + 系统工具栏：Q 返回、H 帮助，无 S）

function New-SysMenuEntry {
    return [pscustomobject]@{
        _kind       = 'sys'
        command     = 'sys'
        name        = (Get-I18n -Key 'page.sys.menuEntry')
        description = (Get-I18n -Key 'page.sys.menuEntrySummary')
    }
}

function Test-IsSysMenuEntry {
    param($Item)
    return ($Item -and $Item._kind -eq 'sys')
}

function Get-SysActions {
    return @(
        [pscustomobject]@{
            command     = 'lang'
            name        = (Get-I18n -Key 'common.language')
            description = (Get-I18n -Key 'page.sys.action.langSummary')
            enabled     = $true
        }
        [pscustomobject]@{
            command     = 'init'
            name        = (Get-I18n -Key 'page.sys.action.init')
            description = (Get-I18n -Key 'page.sys.action.initSummary')
            enabled     = $true
        }
        [pscustomobject]@{
            command     = 'update'
            name        = (Get-I18n -Key 'page.sys.action.update')
            description = (Get-I18n -Key 'page.sys.action.updateSummary')
            enabled     = $true
        }
        [pscustomobject]@{
            command     = 'uninstall'
            name        = (Get-I18n -Key 'page.sys.action.uninstall')
            description = (Get-I18n -Key 'page.sys.action.uninstallSummary')
            enabled     = $true
        }
        [pscustomobject]@{
            command     = 'help'
            name        = (Get-I18n -Key 'common.help')
            description = (Get-I18n -Key 'page.sys.action.helpSummary')
            enabled     = $true
        }
    )
}

function Get-SysListRows {
    return @(Get-SysActions | ForEach-Object {
        $action = $_
        $name = if ($action.name) { [string]$action.name } else { (Get-I18n -Key 'common.unrecognized') }
        $description = if ($action.description) { [string]$action.description } else { '' }
        New-ShellListRow -Id ([string]$action.command) -Cells @(
            (Get-ShellListItemCommand $action)
            $name
            $description
        ) -Payload $action -Enabled ([bool]$action.enabled)
    })
}

function Invoke-SysPage {
    param(
        [hashtable]$Shell,
        [array]$Tools
    )

    $toolbar = New-ShellSystemToolbarConfig -HideSystem

    while ($true) {
        $currentLocale = Get-CurrentLocale
        if (-not $Shell.HeaderLocale -or $Shell.HeaderLocale -ne $currentLocale) {
            $Shell['HeaderLocale'] = $currentLocale
            Clear-ShellListCache -Shell $Shell -CacheKey 'Sys'
        }

        $result = Invoke-ToolkitShellList @{
            Mode         = 'Single'
            Shell        = $Shell
            SectionTitle = (Get-I18n -Key 'page.sys.sectionTitle')
            Rows         = (Get-SysListRows)
            CacheKey     = 'Sys'
            Toolbar      = $toolbar
        }

        $nav = Get-ShellListSelectNavMarker $result
        if ($nav) { return $nav }
        if ($result.Action -ne 'Pick' -or @($result.Payloads).Count -eq 0) {
            return (Get-ShellNavMarker -Action 'back')
        }

        $picked = $result.Payloads[0]

        switch ($picked.command) {
            'help' {
                return (Get-ShellNavMarker -Action 'help')
            }
            'update' {
                return (Get-ShellNavMarker -Action 'update')
            }
            'lang' {
                return (Get-ShellNavMarker -Action 'lang')
            }
            'init' {
                return (Get-ShellNavMarker -Action 'init')
            }
            'uninstall' {
                return (Get-ShellNavMarker -Action 'sysUninstall')
            }
            default {
                $nav = Invoke-SysAction -Action $picked -Tools $Tools
                if ($nav) {
                    return $nav
                }
            }
        }
    }
}

function Invoke-ShellSysView {
    param(
        [hashtable]$Shell,
        [array]$Tools
    )

    return Invoke-SysPage -Shell $Shell -Tools $Tools
}

function Invoke-SysAction {
    param(
        $Action,
        [array]$Tools
    )

    switch ($Action.command) {
        'lang' {
            return (Get-ShellNavMarker -Action 'lang')
        }
        'update' {
            return (Get-ShellNavMarker -Action 'update')
        }
        'init' {
            return (Get-ShellNavMarker -Action 'init')
        }
        'help' {
            $next = Show-ToolkitHelpPage -Tools $Tools
            if (Test-IsSysMenuEntry $next) {
                Start-SysSession -Tools $Tools
            }
        }
        'uninstall' {
            return (Get-ShellNavMarker -Action 'sysUninstall')
        }
    }
}

function Start-SysSession {
    param([array]$Tools)

    return (Start-ToolkitShellSession -Tools $Tools -InitialView Sys)
}

function Invoke-ToolkitSysUninstall {
    param([hashtable]$Shell = $null)

    $lines = @(
        (New-BrandedHelpLine -Text (Get-I18n -Key 'page.sysUninstall.notImplemented'))
    )

    if ($Shell) {
        return Invoke-ToolkitShellContentView -Shell $Shell `
            -SectionTitle (Get-I18n -Key 'page.sysUninstall.pageTitle') `
            -Lines $lines `
            -ToolbarConfig (New-ShellSystemToolbarConfig -HideSystem -HideHelp)
    }

    foreach ($line in $lines) {
        Write-Host $line.Text -ForegroundColor $line.Color
    }
    return 0
}
