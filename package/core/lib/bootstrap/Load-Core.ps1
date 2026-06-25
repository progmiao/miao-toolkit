# 启动层：dot-source 首页与会话所需的最小模块集；其余页面见 Import-MiaoModule.ps1

param(
    [string]$LibDirectory = (Split-Path $PSScriptRoot -Parent)
)

if ($script:MiaoCoreLoaded) { return }

$script:MiaoCoreLibDir = $LibDirectory
$global:MiaoCoreLibDir = $LibDirectory
$lib = $LibDirectory

. (Join-Path $lib 'config\Paths.ps1')
. (Join-Path $lib 'config\ListLayout.ps1')
. (Join-Path $lib 'config\UserConfig.ps1')
. (Join-Path $lib 'config\I18n.ps1')
. (Join-Path $lib 'config\ToolkitInit.ps1')
. (Join-Path $lib 'domain\Discover-Tools.ps1')
. (Join-Path $lib 'domain\Ensure-ToolDeps.ps1')
. (Join-Path $lib 'config\Deps-State.ps1')
. (Join-Path $lib 'domain\Mock-Tools.ps1')
. (Join-Path $lib 'ui\console\Console-Menu.ps1')
. (Join-Path $lib 'ui\legacy\Show-BrandedPage.ps1')

foreach ($name in @(
        'Nav.ps1'
        'Layout.ps1'
        'Header.ps1'
        'Title.ps1'
        'CatalogRow.ps1'
        'Draw.ps1'
        'Exit.ps1'
        'Confirm.ps1'
        'Footer.ps1'
        'SystemToolbar.ps1'
        'ShellListModel.ps1'
        'ShellListLayout.ps1'
        'SingleSelectList.ps1'
        'MultiSelectList.ps1'
        'ToolkitShellList.ps1'
        'Page-Host.ps1'
        'Session.ps1'
    )) {
    . (Join-Path $lib "ui\shell\$name")
}

. (Join-Path $lib 'pages\home.ps1')
. (Join-Path $lib 'bootstrap\Import-MiaoModule.ps1')

foreach ($fnName in @(
        'Get-I18n'
        'Get-I18nRaw'
        'Get-MiaoI18nKeys'
        'Get-CurrentLocale'
        'Set-MiaoLocale'
        'Sync-MiaoLocaleFromShell'
        'Format-I18nPressEnterBack'
        'Format-I18nKeyDisplay'
        'Write-ToolkitShellFooter'
        'Invoke-ToolkitShellRegisteredFooter'
        'New-ShellSystemToolbarFooterRenderer'
        'New-ShellSystemToolbarConfig'
        'Register-ToolkitShellFooter'
        'Initialize-ToolkitShellBodyView'
        'Finalize-ToolkitShellBodyView'
        'Prepare-ToolkitShellBodyDraw'
        'Sync-ToolkitShellLayoutLineMetrics'
        'Initialize-PathsFromToolRoot'
        'Import-MiaoToolDepsModule'
        'ConvertTo-ToolMenuListRows'
        'Get-ToolMenuItems'
        'Get-ToolFromDirectory'
        'Get-ToolSectionTitle'
        'Get-ToolDepInstalledRecord'
        'Get-ToolDepInstalled'
        'Assign-ToolMenuNumbers'
        'Get-BundledToolsRoot'
        'Get-ExternalToolsRoot'
        'Update-ToolDependencyMenuProbe'
        'Get-ToolDependencyMenuAction'
        'Invoke-ToolDependencyMenuAction'
        'Invoke-ToolActionMenu'
        'Invoke-ToolBusinessAction'
    )) {
    $cmd = Get-Command -Name $fnName -CommandType Function -ErrorAction SilentlyContinue
    if ($cmd) {
        Set-Item -Path "function:global:$fnName" -Value $cmd.ScriptBlock -Force | Out-Null
    }
}

Export-MiaoShellListGlobals -LibRoot $lib

$script:MiaoCoreLoaded = $true
$global:MiaoCoreLoaded = $true

function Initialize-MiaoCore {
    param([string]$LibDirectory = '')

    if ($script:MiaoCoreLoaded) { return }
    if ([string]::IsNullOrWhiteSpace($LibDirectory)) {
        $LibDirectory = Split-Path $PSScriptRoot -Parent
    }

    . (Join-Path $PSScriptRoot 'Load-Core.ps1') -LibDirectory $LibDirectory
}
