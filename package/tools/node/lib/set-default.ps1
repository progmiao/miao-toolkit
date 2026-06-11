# node — 设置全局默认 Node 版本（volta install node@x）

param(
    [int]$PageSize = 0,
    [int]$ViewHeight = 0
)

$ErrorActionPreference = 'Stop'

$toolRoot = Split-Path $PSScriptRoot -Parent
$coreLib = Join-Path $toolRoot '..\..\core\lib'
. (Join-Path $coreLib 'config\Paths.ps1')
. (Join-Path $coreLib 'config\ListLayout.ps1')
. (Join-Path $coreLib 'config\UserConfig.ps1')
. (Join-Path $coreLib 'config\I18n.ps1')
. (Join-Path $coreLib 'ui\console\Console-Menu.ps1')
. (Join-Path $PSScriptRoot 'volta-node.ps1')
Initialize-PathsFromToolRoot -ToolRoot $toolRoot

$paging = Resolve-MenuPagingDefaults -PageSize $PageSize -ViewHeight $ViewHeight
$PageSize = $paging.PageSize
$ViewHeight = $paging.ViewHeight

$configPath = Join-Path $toolRoot 'index.json'
$toolConfig = Get-Content -Raw -Path $configPath -Encoding UTF8 | ConvertFrom-Json

Assert-VoltaAvailable

$voltaInfo = Get-VoltaNodeVersionInfo
$activeVersion = Get-ActiveNodeVersion
$installedVersions = @($voltaInfo.Map.Keys)

if ($installedVersions.Count -eq 0) {
    Write-MessageBlock -Title '暂无已安装版本' -Lines @(
        '请先在「浏览并安装」中安装 Node 版本。'
    ) -TitleColor Yellow
    exit 0
}

$items = Sort-NodeVersionItems -Items @(
    $installedVersions | ForEach-Object {
        New-NodeVersionMenuItem -Version $_
    }
)

$header = New-ToolMenuHeader -ToolConfig $toolConfig -SectionTitle '设置全局默认 · 选择版本'
$header.Description = 'Enter 确认后执行: volta install node@版本（设为 default）'

$selected = Show-PaginatedMenu -Header $header -Items $items -CountLabel '个版本' `
    -HideColHeader `
    -GetItemLabel {
        param($Item, [int]$Index)
        Format-NodeVersionMenuLabel -Item $Item -InstalledMap $voltaInfo.Map `
            -DefaultVersion $voltaInfo.Default -ActiveVersion $activeVersion
    }

if (-not $selected) {
    Write-MessageBlock -Title '已取消' -TitleColor Yellow
    exit 0
}

$ver = $selected.Version
if ($ver -eq $voltaInfo.Default) {
    Write-MessageBlock -Title '无需更改' -Lines @("v$ver 已是全局默认版本。") -TitleColor DarkGray
    exit 0
}

Write-MessageBlock -Title '设置全局默认' -Lines @("执行: volta install node@$ver") -TitleColor Green
& volta install "node@$ver"
$code = $LASTEXITCODE

$after = @()
if ($code -eq 0) {
    $after += '已设为全局默认。'
    if (Get-Command node -ErrorAction SilentlyContinue) {
        $after += "当前 node: $(node -v)"
    }
}
else {
    $after += '设置未成功，请查看上方 Volta 输出。'
}

Write-MessageBlock -Title $(if ($code -eq 0) { '完成' } else { '提示' }) -Lines $after `
    -TitleColor $(if ($code -eq 0) { 'Green' } else { 'Yellow' })

exit $code
