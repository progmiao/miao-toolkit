# Volta Node 版本选择器（上下键 + 回车安装）
# 用法: .\volta-node-menu.ps1  或双击 volta-node-menu.bat

param(
    [int]$PageSize = 20,
    [int]$LoadMore = 15,
    [int]$ViewHeight = 15,
    [switch]$LtsOnly
)

$ErrorActionPreference = "Stop"

function Get-InstalledNodeVersions {
    if (-not (Get-Command volta -ErrorAction SilentlyContinue)) {
        Write-Host "未找到 Volta，请先安装: https://volta.sh/" -ForegroundColor Red
        Read-Host "按回车退出"
        exit 1
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
    } catch {}
    return $null
}

function Get-AllRemoteVersions {
    param([bool]$LtsOnly)

    $releases = Invoke-RestMethod "https://nodejs.org/dist/index.json"
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

function Format-MenuLine {
    param($Version, $Lts, $IsInstalled, $IsDefault, $IsActive, $Selected)

    $prefix = if ($Selected) { " > " } else { "   " }
    $tag = ""
    if ($IsActive)    { $tag += " [当前]" }
    if ($IsInstalled) { $tag += " [已安装]" }
    if ($IsDefault)   { $tag += " [默认]" }
    if ($Lts -and $Lts -ne $false) { $tag += " [LTS:$Lts]" }

    return "$prefix$Version$tag"
}

function Get-ConsoleLineWidth {
    $width = [Console]::WindowWidth
    if ($null -eq $width -or $width -lt 20) { return 80 }
    return $width
}

function Write-FixedLine {
    param(
        [int]$Row,
        [string]$Text,
        [bool]$Selected = $false,
        [System.ConsoleColor]$Color = [System.ConsoleColor]::Gray
    )

    [Console]::SetCursorPosition(0, $Row)
    $width = Get-ConsoleLineWidth
    if ($Text.Length -gt $width) { $Text = $Text.Substring(0, $width) }
    $padded = $Text.PadRight($width)

    if ($Selected) {
        Write-Host $padded -NoNewline -ForegroundColor Black -BackgroundColor Cyan
    } else {
        Write-Host $padded -NoNewline -ForegroundColor $Color
    }
}

function Build-MenuLineText {
    param(
        $Item,
        [hashtable]$InstalledMap,
        [string]$DefaultVer,
        [string]$ActiveVer,
        [bool]$Selected
    )

    return Format-MenuLine -Version $Item.Version -Lts $Item.Lts `
        -IsInstalled $InstalledMap.ContainsKey($Item.Version) `
        -IsDefault ($Item.Version -eq $DefaultVer) `
        -IsActive ($Item.Version -eq $ActiveVer) `
        -Selected $Selected
}

function Update-MenuFooter {
    param(
        [int]$HintRow,
        [int]$StatusRow,
        [int]$ViewHeight,
        [int]$Loaded,
        [int]$Total,
        [int]$SelectedIndex
    )

    if ($Loaded -lt $Total) {
        $remaining = $Total - $Loaded
        Write-FixedLine $HintRow "   向下继续可加载更多（还有 $remaining 个版本）" -Color DarkGray
    } else {
        Write-FixedLine $HintRow "" -Color DarkGray
    }

    Write-FixedLine $StatusRow " 已加载 $Loaded / $Total | 视口 $ViewHeight 行 | 选中 $($SelectedIndex + 1)" -Color DarkGray
}

function Draw-MenuListRow {
    param(
        [array]$AllItems,
        [int]$ListStartRow,
        [int]$ViewRow,
        [int]$ItemIndex,
        [int]$LoadedCount,
        [hashtable]$InstalledMap,
        [string]$DefaultVer,
        [string]$ActiveVer,
        [bool]$Selected
    )

    $screenRow = $ListStartRow + $ViewRow
    if ($ItemIndex -ge 0 -and $ItemIndex -lt $LoadedCount) {
        $text = Build-MenuLineText -Item $AllItems[$ItemIndex] `
            -InstalledMap $InstalledMap -DefaultVer $DefaultVer -ActiveVer $ActiveVer `
            -Selected $Selected
        Write-FixedLine $screenRow $text -Selected $Selected
    } else {
        Write-FixedLine $screenRow "" -Selected $false
    }
}

function Redraw-MenuViewport {
    param(
        [array]$AllItems,
        [int]$ListStartRow,
        [int]$ViewHeight,
        [int]$ScrollTop,
        [int]$SelectedIndex,
        [int]$LoadedCount,
        [hashtable]$InstalledMap,
        [string]$DefaultVer,
        [string]$ActiveVer
    )

    for ($row = 0; $row -lt $ViewHeight; $row++) {
        $itemIndex = $ScrollTop + $row
        Draw-MenuListRow -AllItems $AllItems -ListStartRow $ListStartRow -ViewRow $row `
            -ItemIndex $itemIndex -LoadedCount $LoadedCount `
            -InstalledMap $InstalledMap -DefaultVer $DefaultVer -ActiveVer $ActiveVer `
            -Selected ($itemIndex -eq $SelectedIndex)
    }
}

function Show-NodeMenu {
    param(
        [array]$AllItems,
        [int]$InitialCount,
        [int]$LoadMoreCount,
        [int]$WindowHeight,
        [hashtable]$InstalledMap,
        [string]$DefaultVer,
        [string]$ActiveVer
    )

    $loadedCount = [Math]::Min($InitialCount, $AllItems.Count)
    $viewHeight = [Math]::Max(5, $WindowHeight)
    $index = 0
    $scrollTop = 0

    $listStartRow = 4
    $hintRow = $listStartRow + $viewHeight
    $statusRow = $hintRow + 1
    $menuBottomRow = $statusRow + 1

    $drawParams = @{
        AllItems      = $AllItems
        ListStartRow  = $listStartRow
        ViewHeight    = $viewHeight
        LoadedCount   = $loadedCount
        InstalledMap  = $InstalledMap
        DefaultVer    = $DefaultVer
        ActiveVer     = $ActiveVer
    }

    Clear-Host
    [Console]::CursorVisible = $false

    Write-FixedLine 0 " Node 版本列表（上下键选择，Enter 确认，Esc 取消）" -Color Cyan
    Write-FixedLine 1 " 确认后执行: volta install node@版本" -Color DarkGray
    Write-FixedLine 2 ("-" * 56) -Color DarkGray
    Write-FixedLine 3 ""

    Redraw-MenuViewport @drawParams -ScrollTop $scrollTop -SelectedIndex $index
    Update-MenuFooter -HintRow $hintRow -StatusRow $statusRow -ViewHeight $viewHeight `
        -Loaded $loadedCount -Total $AllItems.Count -SelectedIndex $index

    try {
        while ($true) {
            $oldIndex = $index
            $oldScrollTop = $scrollTop
            $loadedChanged = $false

            $key = [Console]::ReadKey($true)
            switch ($key.Key) {
                "UpArrow" {
                    if ($index -gt 0) { $index-- }
                }
                "DownArrow" {
                    if ($index -lt ($loadedCount - 1)) {
                        $index++
                    } elseif ($loadedCount -lt $AllItems.Count) {
                        $loadedCount = [Math]::Min($loadedCount + $LoadMoreCount, $AllItems.Count)
                        $drawParams.LoadedCount = $loadedCount
                        $loadedChanged = $true
                        if ($index -lt ($loadedCount - 1)) { $index++ }
                    }
                }
                "Enter" {
                    [Console]::SetCursorPosition(0, $menuBottomRow)
                    return $AllItems[$index]
                }
                "Escape" {
                    [Console]::SetCursorPosition(0, $menuBottomRow)
                    return $null
                }
            }

            if ($index -lt $scrollTop) {
                $scrollTop = $index
            } elseif ($index -ge ($scrollTop + $viewHeight)) {
                $scrollTop = $index - $viewHeight + 1
            }

            if ($oldScrollTop -ne $scrollTop) {
                Redraw-MenuViewport @drawParams -ScrollTop $scrollTop -SelectedIndex $index
            } elseif ($oldIndex -ne $index) {
                if ($oldIndex -ge $scrollTop -and $oldIndex -lt ($scrollTop + $viewHeight)) {
                    Draw-MenuListRow -AllItems $AllItems -ListStartRow $listStartRow `
                        -ViewRow ($oldIndex - $scrollTop) -ItemIndex $oldIndex -LoadedCount $loadedCount `
                        -InstalledMap $InstalledMap -DefaultVer $DefaultVer -ActiveVer $ActiveVer `
                        -Selected $false
                }
                if ($index -ge $scrollTop -and $index -lt ($scrollTop + $viewHeight)) {
                    Draw-MenuListRow -AllItems $AllItems -ListStartRow $listStartRow `
                        -ViewRow ($index - $scrollTop) -ItemIndex $index -LoadedCount $loadedCount `
                        -InstalledMap $InstalledMap -DefaultVer $DefaultVer -ActiveVer $ActiveVer `
                        -Selected $true
                }
            }

            if ($loadedChanged -or $oldIndex -ne $index -or $oldScrollTop -ne $scrollTop) {
                Update-MenuFooter -HintRow $hintRow -StatusRow $statusRow -ViewHeight $viewHeight `
                    -Loaded $loadedCount -Total $AllItems.Count -SelectedIndex $index
            }
        }
    } finally {
        [Console]::CursorVisible = $true
    }
}

# --- main ---
Clear-Host
Write-Host "正在加载 Node 版本列表..." -ForegroundColor Yellow

$voltaInfo = Get-InstalledNodeVersions
$installedMap = $voltaInfo.Map
$defaultVer = $voltaInfo.Default
$activeVer = Get-ActiveNodeVersion

$remote = @(Get-AllRemoteVersions -LtsOnly:$LtsOnly)
$items = [System.Collections.Generic.List[object]]::new()
$seen = @{}

foreach ($r in $remote) {
    $ver = $r.Version
    if (-not $seen[$ver]) {
        $items.Add($r)
        $seen[$ver] = $true
    }
}

foreach ($ver in $installedMap.Keys) {
    if (-not $seen[$ver]) {
        $items.Add([PSCustomObject]@{
            Version = $ver
            Lts     = $false
            Date    = ""
        })
        $seen[$ver] = $true
    }
}

$items = @($items | Sort-Object { [version]($_.Version.Split('-')[0]) } -Descending)

if ($items.Count -eq 0) {
    Write-Host "没有可用版本。" -ForegroundColor Red
    Read-Host "按回车退出"
    exit 0
}

$selected = Show-NodeMenu -AllItems $items -InitialCount $PageSize -LoadMoreCount $LoadMore `
    -WindowHeight $ViewHeight -InstalledMap $installedMap -DefaultVer $defaultVer -ActiveVer $activeVer

Write-Host ""
if (-not $selected) {
    Write-Host "已取消。" -ForegroundColor Yellow
    exit 0
}

$ver = $selected.Version
Write-Host "已选择: $ver" -ForegroundColor Green

if ($installedMap.ContainsKey($ver)) {
    Write-Host "该版本已安装，仍可通过 Volta 切换使用。" -ForegroundColor DarkGray
}

Write-Host "执行: volta install node@$ver" -ForegroundColor Cyan
& volta install "node@$ver"

Write-Host ""
if (Get-Command node -ErrorAction SilentlyContinue) {
    Write-Host "当前 node: $(node -v)" -ForegroundColor Green
}
Write-Host ""
Read-Host "按回车关闭"
