# 按依赖顺序加载 core/lib 模块（dot-source 须在脚本作用域，不可包在 function 内）

param(
    [string]$LibDirectory = (Split-Path $PSScriptRoot -Parent)
)

if ($script:MiaoCoreLoaded) { return }

$script:MiaoCoreLibDir = $LibDirectory
$lib = $LibDirectory

. (Join-Path $lib 'config\Paths.ps1')
. (Join-Path $lib 'config\ListLayout.ps1')
. (Join-Path $lib 'config\UserConfig.ps1')
. (Join-Path $lib 'config\Deps-State.ps1')
. (Join-Path $lib 'config\I18n.ps1')
. (Join-Path $lib 'domain\Discover-Tools.ps1')
. (Join-Path $lib 'domain\Mock-Tools.ps1')
. (Join-Path $lib 'domain\Ensure-ToolDeps.ps1')
. (Join-Path $lib 'domain\Invoke-Tool.ps1')
. (Join-Path $lib 'domain\Check-Update.ps1')
. (Join-Path $lib 'ui\console\Console-Menu.ps1')
. (Join-Path $lib 'ui\legacy\Show-BrandedPage.ps1')

foreach ($name in @(
        'Nav.ps1'
        'Layout.ps1'
        'Header.ps1'
        'Title.ps1'
        'Draw.ps1'
        'Exit.ps1'
        'Footer.ps1'
        'Page-Host.ps1'
        'Session.ps1'
    )) {
    . (Join-Path $lib "ui\shell\$name")
}

. (Join-Path $lib 'domain\Invoke-ToolkitDeps.ps1')
. (Join-Path $lib 'pages\help.ps1')
. (Join-Path $lib 'pages\lang.ps1')
. (Join-Path $lib 'pages\settings.ps1')
. (Join-Path $lib 'pages\update.ps1')
. (Join-Path $lib 'pages\install-deps.ps1')
. (Join-Path $lib 'pages\home.ps1')

$script:MiaoCoreLoaded = $true

function Initialize-MiaoCore {
    param([string]$LibDirectory = '')

    if ($script:MiaoCoreLoaded) { return }
    if ([string]::IsNullOrWhiteSpace($LibDirectory)) {
        $LibDirectory = Split-Path $PSScriptRoot -Parent
    }

    . (Join-Path $PSScriptRoot 'Load-Core.ps1') -LibDirectory $LibDirectory
}
