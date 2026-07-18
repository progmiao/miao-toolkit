# 首页：工具列表（统一 Shell 列表 + 系统工具栏）

function Get-HomeToolListRows {
    param([array]$Tools)

    return @($Tools | ForEach-Object {
        $tool = $_
        New-ShellListRow -Id ([string]$tool.id) -Cells @(
            (Get-ToolCommandName -Tool $tool)
            [string]$tool.name
            [string]$tool.description
        ) -Payload $tool -Number ([int]$tool.no)
    })
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
            Clear-ShellListCache -Shell $Shell -CacheKey 'Home'
            $Shell['HeaderLocale'] = $currentLocale
            $null = Sync-ToolkitSessionInitState -Shell $Shell -Refresh
        }
        elseif ([int]$Shell.HomeListLayoutWidth -ne $layoutWidth) {
            Clear-ShellListCache -Shell $Shell -CacheKey 'Home'
        }
        $Shell['HomeListLayoutWidth'] = $layoutWidth
    }

    return Invoke-ToolkitShellList @{
        Mode         = 'Single'
        Shell        = $Shell
        SectionTitle = (Get-I18n -Key 'page.home.toolList')
        Rows         = (Get-HomeToolListRows -Tools $Tools)
        CacheKey     = 'Home'
        Toolbar      = (New-ShellSystemToolbarConfig -HideBack)
    }
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
