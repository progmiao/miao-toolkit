# node — 浏览并安装（nodejs.org 版本列表）

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
Initialize-PathsFromToolRoot -ToolRoot $toolRoot

$paging = Resolve-MenuPagingDefaults -PageSize $PageSize -ViewHeight $ViewHeight
$PageSize = $paging.PageSize
$ViewHeight = $paging.ViewHeight

$configPath = Join-Path $toolRoot 'index.json'
$toolConfig = Get-Content -Raw -Path $configPath -Encoding UTF8 | ConvertFrom-Json

function Get-InstalledNodeVersions {
    if (-not (Get-Command volta -ErrorAction SilentlyContinue)) {
        return @{ Map = @{}; Default = $null }
    }

    $installed = @{}
    $defaultVer = $null
    $raw = & volta list 2>$null | Out-String

    foreach ($line in ($raw -split "`n")) {
        if ($line -match 'node@([0-9.]+)(?:\s+\(default\))?') {
            $ver = $Matches[1]
            $installed[$ver] = $true
            if ($line -match '\(default\)') { $defaultVer = $ver }
        }
    }

    return @{ Map = $installed; Default = $defaultVer }
}

function Get-ActiveNodeVersion {
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) { return $null }
    try {
        $v = (& node -v 2>$null).ToString().Trim()
        if ($v) { return ($v -replace '^v', '') }
    }
    catch {}
    return $null
}

function Get-AllRemoteVersions {
    param([bool]$LtsOnly)

    $releases = Invoke-RestMethod 'https://nodejs.org/dist/index.json'
    if ($LtsOnly) {
        $releases = $releases | Where-Object { $_.lts -ne $false }
    }

    return $releases | ForEach-Object {
        [PSCustomObject]@{
            Version = ($_.version -replace '^v', '')
            Lts     = $_.lts
            Date    = $_.date
        }
    }
}

function Format-NodeVersionLabel {
    param($Item, [int]$Index)

    $script:NodeVersionInstalledMap = if ($script:NodeVersionInstalledMap) { $script:NodeVersionInstalledMap } else { @{} }
    $script:NodeVersionDefault = if ($null -ne $script:NodeVersionDefault) { $script:NodeVersionDefault } else { '' }
    $script:NodeVersionActive = if ($null -ne $script:NodeVersionActive) { $script:NodeVersionActive } else { '' }

    $tag = ''
    if ($Item.Version -eq $script:NodeVersionActive) { $tag += ' [当前]' }
    if ($script:NodeVersionInstalledMap.ContainsKey($Item.Version)) { $tag += ' [已安装]' }
    if ($Item.Version -eq $script:NodeVersionDefault) { $tag += ' [默认]' }
    if ($Item.Lts -and $Item.Lts -ne $false) { $tag += " [LTS:$($Item.Lts)]" }

    return "$($Item.Version)$tag"
}

# --- main ---

if (-not (Get-Command volta -ErrorAction SilentlyContinue)) {
    Write-MessageBlock -Title '未找到 Volta' -Lines @(
        '无法安装 Node 版本。',
        '请运行: winget install Volta.Volta'
    ) -TitleColor Red
    exit 1
}

Clear-Host
Write-Host ''
Write-Host ' 正在加载 Node 版本列表...' -ForegroundColor Yellow

$voltaInfo = Get-InstalledNodeVersions
$script:NodeVersionInstalledMap = $voltaInfo.Map
$script:NodeVersionDefault = $voltaInfo.Default
$script:NodeVersionActive = Get-ActiveNodeVersion

try {
    $remote = @(Get-AllRemoteVersions -LtsOnly:$LtsOnly)
}
catch {
    Write-MessageBlock -Title '加载失败' -Lines @($_.Exception.Message) -TitleColor Red
    exit 1
}

$items = [System.Collections.Generic.List[object]]::new()
$seen = @{}

foreach ($r in $remote) {
    if (-not $seen[$r.Version]) {
        $items.Add($r)
        $seen[$r.Version] = $true
    }
}

foreach ($ver in $script:NodeVersionInstalledMap.Keys) {
    if (-not $seen[$ver]) {
        $items.Add([PSCustomObject]@{
                Version = $ver
                Lts     = $false
                Date    = ''
            })
        $seen[$ver] = $true
    }
}

$items = @($items | Sort-Object { [version]($_.Version.Split('-')[0]) } -Descending)

if ($items.Count -eq 0) {
    Write-MessageBlock -Title '无可用版本' -TitleColor Yellow
    exit 0
}

$header = New-ToolMenuHeader -ToolConfig $toolConfig -SectionTitle '浏览并安装 · 选择版本'
$header.Description = 'Enter 确认后执行: volta install node@版本'

$selected = Show-PaginatedMenu -Header $header -Items $items -CountLabel '个版本' `
    -HideColHeader `
    -GetItemLabel ${function:Format-NodeVersionLabel}

if (-not $selected) {
    Write-MessageBlock -Title '已取消' -TitleColor Yellow
    exit 0
}

$ver = $selected.Version
$resultLines = @("已选择: $ver")

if ($script:NodeVersionInstalledMap.ContainsKey($ver)) {
    $resultLines += '该版本已安装，仍可通过 Volta 切换使用。'
}

$resultLines += "执行: volta install node@$ver"
Write-MessageBlock -Title '安装 Node' -Lines $resultLines -TitleColor Green

& volta install "node@$ver"
$code = $LASTEXITCODE

$after = @()
if ($code -eq 0) {
    $after += '安装完成。'
    if (Get-Command node -ErrorAction SilentlyContinue) {
        $after += "当前 node: $(node -v)"
    }
}
else {
    $after += '安装未成功，请查看上方 Volta 输出。'
}

Write-MessageBlock -Title $(if ($code -eq 0) { '完成' } else { '提示' }) -Lines $after `
    -TitleColor $(if ($code -eq 0) { 'Green' } else { 'Yellow' })

exit $code
