# node — 为项目指定 Node 版本（volta pin node@x）

param(
    [int]$PageSize = 0,
    [int]$ViewHeight = 0,
    [switch]$LtsOnly
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

$packageJson = Join-Path (Get-Location) 'package.json'
if (-not (Test-Path $packageJson)) {
    Write-MessageBlock -Title '需要项目目录' -Lines @(
        '请在包含 package.json 的项目根目录执行此功能。'
    ) -TitleColor Red
    exit 1
}

Assert-VoltaAvailable

$voltaInfo = Get-VoltaNodeVersionInfo
$activeVersion = Get-ActiveNodeVersion
$items = [System.Collections.Generic.List[object]]::new()
$seen = @{}

foreach ($ver in $voltaInfo.Map.Keys) {
    if (-not $seen[$ver]) {
        $items.Add((New-NodeVersionMenuItem -Version $ver))
        $seen[$ver] = $true
    }
}

try {
    foreach ($r in (Get-RemoteNodeVersions -LtsOnly:$LtsOnly)) {
        if (-not $seen[$r.Version]) {
            $items.Add($r)
            $seen[$r.Version] = $true
        }
    }
}
catch {
    if ($items.Count -eq 0) {
        Write-MessageBlock -Title '加载失败' -Lines @($_.Exception.Message) -TitleColor Red
        exit 1
    }
}

$sorted = Sort-NodeVersionItems -Items @($items.ToArray())
if ($sorted.Count -eq 0) {
    Write-MessageBlock -Title '无可用版本' -TitleColor Yellow
    exit 0
}

$header = New-ToolMenuHeader -ToolConfig $toolConfig -SectionTitle '为项目指定 · 选择版本'
$header.Description = 'Enter 确认后执行: volta pin node@版本（未安装时 Volta 将按需拉取）'

$selected = Show-PaginatedMenu -Header $header -Items $sorted -CountLabel '个版本' `
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
$needsInstall = -not $voltaInfo.Map.ContainsKey($ver)
$lines = @("项目: $(Split-Path $packageJson -Leaf)", "执行: volta pin node@$ver")
if ($needsInstall) {
    $lines += '该版本尚未安装，Volta 可能在首次使用时自动下载。'
}

Write-MessageBlock -Title '为项目指定' -Lines $lines -TitleColor Green
& volta pin "node@$ver"
$code = $LASTEXITCODE

$after = @()
if ($code -eq 0) {
    $after += '已为当前项目锁定 Node 版本。'
}
else {
    $after += '指定未成功，请查看上方 Volta 输出。'
}

Write-MessageBlock -Title $(if ($code -eq 0) { '完成' } else { '提示' }) -Lines $after `
    -TitleColor $(if ($code -eq 0) { 'Green' } else { 'Yellow' })

exit $code
