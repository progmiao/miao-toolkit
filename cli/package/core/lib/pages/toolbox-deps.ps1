# 工具箱级第三方依赖专页（install / update / uninstall 列表，update·uninstall 待完善）

function Invoke-ToolboxDepPlaceholderPage {
    param(
        [hashtable]$Shell,
        [string]$TitleKey,
        [string]$BodyKey
    )

    $lines = @(
        (New-BrandedHelpLine -Text (Get-I18n -Key $BodyKey) -Color ([System.ConsoleColor]::DarkGray))
    )

    return Invoke-ToolkitShellContentView -Shell $Shell `
        -SectionTitle (Get-I18n -Key $TitleKey) `
        -Lines $lines `
        -ToolbarConfig (New-ShellSystemToolbarConfig -HideSystem)
}

function Invoke-ToolboxDepUpdatePage {
    param(
        [hashtable]$Shell,
        [array]$Tools,
        [switch]$SelectAll
    )

    return Invoke-ToolboxDepPlaceholderPage -Shell $Shell `
        -TitleKey 'page.toolboxDeps.update.pageTitle' `
        -BodyKey 'page.toolboxDeps.update.notImplemented'
}

function Invoke-ToolboxDepUninstallPage {
    param(
        [hashtable]$Shell,
        [array]$Tools,
        [switch]$SelectAll
    )

    return Invoke-ToolboxDepPlaceholderPage -Shell $Shell `
        -TitleKey 'page.toolboxDeps.uninstall.pageTitle' `
        -BodyKey 'page.toolboxDeps.uninstall.notImplemented'
}

function Start-ToolboxDepUpdateSession {
    param(
        [array]$Tools,
        [switch]$SelectAll
    )

    return (Start-ToolkitShellSession -Tools $Tools `
        -InitialView ToolboxDepUpdate -ToolboxDepSelectAll:($SelectAll.IsPresent))
}

function Start-ToolboxDepUninstallSession {
    param(
        [array]$Tools,
        [switch]$SelectAll
    )

    return (Start-ToolkitShellSession -Tools $Tools `
        -InitialView ToolboxDepUninstall -ToolboxDepSelectAll:($SelectAll.IsPresent))
}
