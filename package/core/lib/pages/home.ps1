# 首页：工具列表（单选列表 + 系统工具栏）

function Get-HomeToolListRows {
    param([array]$Tools)

    return ConvertTo-ShellListRows -Items $Tools -KeepSource -MapCells {
        param($Tool, [int]$Index)
        @(
            (Get-ToolCommandName -Tool $Tool)
            [string]$Tool.name
            [string]$Tool.description
        )
    } -GetNumber {
        param($Tool, [int]$Index)
        return [int]$Tool.no
    }
}

function Invoke-HomePage {
    param(
        [array]$Tools,
        [hashtable]$Shell
    )

    if ($Shell) {
        $currentLocale = Get-CurrentLocale
        $layoutWidth = Get-ToolkitShellLayoutBarInnerWidth -Shell $Shell
        if (-not $Shell.HeaderLocale -or $Shell.HeaderLocale -ne $currentLocale) {
            Update-ToolkitShellBrandHeader -Shell $Shell
            Clear-ShellSingleSelectListCache -Shell $Shell -CacheKey 'Home'
        }
        elseif ([int]$Shell.HomeListLayoutWidth -ne $layoutWidth) {
            Clear-ShellSingleSelectListCache -Shell $Shell -CacheKey 'Home'
        }
        $Shell['HomeListLayoutWidth'] = $layoutWidth
    }

    return Invoke-ShellSingleSelectList -Shell $Shell `
        -SectionTitle (Get-I18n -Key 'page.home.toolList') `
        -Rows (Get-HomeToolListRows -Tools $Tools) `
        -CacheKey 'Home' `
        -ColumnLayout (New-ShellListColumnLayout -Preset ToolList) `
        -ToolbarConfig (New-ShellSystemToolbarConfig -HideBack)
}

function Show-ToolkitMenu {
    param(
        [array]$Tools,
        [hashtable]$ToolkitShell = $null
    )

    return Invoke-HomePage -Tools $Tools -Shell $ToolkitShell
}

function Start-ToolkitSession {
    param([array]$Tools)

    return (Start-ToolkitShellSession -Tools $Tools)
}
