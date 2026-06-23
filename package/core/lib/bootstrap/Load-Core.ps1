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
        'SingleSelectList.ps1'
        'MultiSelectList.ps1'
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
        'Invoke-ShellSingleSelectList'
        'Invoke-ShellMultiSelectList'
        'Clear-ShellSingleSelectListCache'
        'Clear-ShellMultiSelectListCache'
        'New-ShellListColumnLayout'
        'Normalize-ShellListRows'
        'Build-ShellSingleSelectListRowCache'
        'Build-ShellSingleSelectListRowSpec'
        'Write-ShellSingleSelectListRow'
        'Invoke-ShellSingleSelectListDrawRow'
        'New-ShellSingleSelectListDrawHandlers'
        'Format-MenuTableCell'
        'New-ShellListRowBodySegments'
        'Prepare-ConsoleRowWrite'
        'Get-SafeWriteLineWidth'
        'Set-ConsoleCursorAfterRowWrite'
        'Get-DisplayWidth'
        'Truncate-DisplayText'
        'Resolve-ToolMenuActionName'
        'Resolve-ToolMenuActionDescription'
        'Get-ToolMenuItemCommand'
        'Get-ShellListItemCommand'
        'Show-PaginatedMenu'
        'Redraw-PaginatedMenuPage'
        'Update-PaginatedMenuSelection'
        'Select-MenuPageSelectionIndex'
        'Set-MenuListScrollOffset'
        'Test-MenuNumberBufferPrefix'
        'Test-MenuSearchBufferPrefix'
        'Get-MenuMaxDisplayNumber'
        'Set-MenuInputCursorPosition'
        'Get-MenuMaxDisplayNumber'
        'Initialize-ShellMultiSelectListDependencies'
        'Get-ShellMultiSelectMenuCommand'
        'Format-ShellMultiSelectCheckMark'
        'Build-ShellMultiSelectListRowSpec'
        'Invoke-ShellMultiSelectListDrawRow'
        'Build-ShellMultiSelectListRowCache'
        'Get-ShellMultiSelectListRowCache'
        'Clear-ShellMultiSelectListCache'
        'New-ShellMultiSelectListDrawHandlers'
        'Get-ShellMultiSelectCheckedSet'
        'Test-ShellMultiSelectIndexChecked'
        'Find-ShellMultiSelectFirstFocusIndex'
        'Resolve-ShellMultiSelectListPick'
        'Show-ShellMultiSelectListMenu'
        'Get-ShellSingleSelectListRowCache'
        'Format-ListDisplayNumber'
        'Resolve-ListNumberIndexDefault'
        'Initialize-PathsFromToolRoot'
        'Import-MiaoToolDepsModule'
        'ConvertTo-ToolMenuListRows'
        'Get-ToolMenuItems'
        'Get-ToolFromDirectory'
        'Get-ToolSectionTitle'
        'Assign-ToolMenuNumbers'
        'Get-BundledToolsRoot'
        'Get-ExternalToolsRoot'
        'Update-ToolDependencyMenuProbe'
        'Test-ToolDependencyMenuAction'
        'Invoke-ToolDependencyMenuAction'
        'Invoke-ToolActionMenu'
        'Invoke-ToolBusinessAction'
    )) {
    $cmd = Get-Command -Name $fnName -CommandType Function -ErrorAction SilentlyContinue
    if ($cmd) {
        Set-Item -Path "function:global:$fnName" -Value $cmd.ScriptBlock -Force | Out-Null
    }
}

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
