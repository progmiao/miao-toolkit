# 工具箱统一 UI：固定顶栏 + 分页编号菜单（各级菜单共用）

function Initialize-PathsFromToolRoot {
    param([string]$ToolRoot)
    if ($script:HomeResolved) { return }
    $binDir = Join-Path $ToolRoot '..\..\bin'
    if (Test-Path $binDir) {
        Initialize-Paths -BinDirectory (Resolve-Path $binDir).Path
    }
}

function Get-AsciiLogo {
    $coreRoot = Get-CoreRoot
    $manifest = Get-Manifest
    $fileName = if ($manifest.logo) { $manifest.logo } else { 'ascii-logo.txt' }
    $path = Join-Path $coreRoot $fileName

    if (Test-Path $path) {
        return @(
            Get-Content -Path $path -Encoding UTF8 |
                ForEach-Object { $_.TrimEnd() } |
                Where-Object { $_ -match '\S' }
        )
    }

    return @(
        '    /\___/\    '
        (Get-I18n -Key 'header.fallbackLogoMiddle')
        '    \_____/   '
    )
}

function Test-WideCharacter {
    param([char]$Char)

    $code = [int][char]$Char
    if ($code -ge 0x1100 -and $code -le 0x115F) { return $true }
    if ($code -ge 0x2E80 -and $code -le 0xA4CF) { return $true }
    if ($code -ge 0xAC00 -and $code -le 0xD7A3) { return $true }
    if ($code -ge 0xF900 -and $code -le 0xFAFF) { return $true }
    if ($code -ge 0xFE10 -and $code -le 0xFE19) { return $true }
    if ($code -ge 0xFE30 -and $code -le 0xFE6F) { return $true }
    if ($code -ge 0xFF01 -and $code -le 0xFF60) { return $true }
    if ($code -ge 0xFFE0 -and $code -le 0xFFE6) { return $true }
    return $false
}

function Get-DisplayWidth {
    param([string]$Text)

    if ([string]::IsNullOrEmpty($Text)) { return 0 }
    $width = 0
    foreach ($ch in $Text.ToCharArray()) {
        $width += $(if (Test-WideCharacter $ch) { 2 } else { 1 })
    }
    return $width
}

function Truncate-DisplayText {
    param(
        [string]$Text,
        [int]$MaxWidth
    )

    if ($MaxWidth -le 0) { return '' }
    if ([string]::IsNullOrEmpty($Text)) { return '' }

    $sb = New-Object System.Text.StringBuilder
    $used = 0
    foreach ($ch in $Text.ToCharArray()) {
        $charWidth = $(if (Test-WideCharacter $ch) { 2 } else { 1 })
        if (($used + $charWidth) -gt $MaxWidth) { break }
        [void]$sb.Append($ch)
        $used += $charWidth
    }
    return $sb.ToString()
}

function Pad-DisplayText {
    param(
        [string]$Text,
        [int]$TargetWidth
    )

    $text = if ($null -eq $Text) { '' } else { $Text }
    $width = Get-DisplayWidth $text
    if ($width -gt $TargetWidth) {
        return Truncate-DisplayText $text $TargetWidth
    }
    return $text + (' ' * ($TargetWidth - $width))
}

function Get-BrandBlockRowCount {
    param([hashtable]$Header = $null)

    $logoCount = @(Get-AsciiLogo).Count
    # logo + welcome row（welcome 紧贴 logo 末行）
    return $logoCount + 1
}

function Get-MenuHeaderRowCount {
    param([hashtable]$Header = $null)

    # Shell 品牌顶栏（HideSectionTitle）行数，含 row0 窗体顶空行，内容区从该行数起算，不再单独留顶距
    # row0 顶空 | row1 cap | row2 品牌前空 | brand×N | 品牌后空
    $extra = if ($Header -and $Header.HideSectionTitle) { 4 } else { 7 }
    return (Get-BrandBlockRowCount -Header $Header) + $extra
}

function Center-DisplayText {
    param(
        [string]$Text,
        [int]$Width
    )

    if ([string]::IsNullOrEmpty($Text)) { return '' }
    $textWidth = Get-DisplayWidth $Text
    if ($textWidth -ge $Width) { return Truncate-DisplayText $Text $Width }
    $leftPad = [int][Math]::Floor(($Width - $textWidth) / 2)
    return (' ' * $leftPad) + $Text
}

function Format-LogoWelcomeLine {
    param([int]$LogoColumnWidth)

    $line = Get-I18n -Key 'header.welcomeLine'
    return Center-DisplayText $line $LogoColumnWidth
}

function Get-LogoColumnWidth {
    $max = 0
    foreach ($line in @(Get-AsciiLogo)) {
        $w = Get-DisplayWidth $line
        if ($w -gt $max) { $max = $w }
    }
    return $max
}

function Format-ProductAuthorLine {
    return Get-I18n -Key 'panel.authorLine' -Vars @{
        author = (Get-BrandAuthorName)
    }
}

function Format-ProductVersionLine {
    param([string]$Version)

    $verLabel = ($Version -replace '^v', '').Trim()
    if ([string]::IsNullOrWhiteSpace($verLabel)) { $verLabel = '0.0.0' }

    return Get-I18n -Key 'panel.versionLine' -Vars @{
        version = $verLabel
    }
}

function Format-ProductReleaseDateLine {
    param([string]$ReleaseDate)

    return Get-I18n -Key 'panel.releaseDateLine' -Vars @{
        releaseDate = $ReleaseDate
    }
}

function Format-ProductVersionReleaseLine {
    param([string]$Version)

    $verLabel = ($Version -replace '^v', '').Trim()
    if ([string]::IsNullOrWhiteSpace($verLabel)) { $verLabel = '0.0.0' }
    $released = Format-ReleaseDate (Get-Manifest).releaseDate

    return Get-I18n -Key 'panel.versionReleaseLine' -Vars @{
        version     = $verLabel
        releaseDate = $released
    }
}

function Format-ProductEmailLine {
    $email = Get-BrandContactEmail
    if ([string]::IsNullOrWhiteSpace($email)) { return '' }

    return Get-I18n -Key 'panel.emailLine' -Vars @{ email = $email }
}

function Get-ProductPanelRows {
    param([hashtable]$Header = $null)

    $manifest = Get-Manifest
    $ver = if ($Header -and $Header.Version) { $Header.Version } else { $manifest.version }
    $released = Format-ReleaseDate $manifest.releaseDate

    # logo 行 0..7：信息 + 空行交替；第 9 行（welcome）右侧显示邮箱
    $rows = @(
        [pscustomobject]@{ Text = (Get-I18n -Key 'brand.description'); Color = [System.ConsoleColor]::White }
        [pscustomobject]@{ Text = ''; Color = [System.ConsoleColor]::DarkGray }
        [pscustomobject]@{ Text = (Format-ProductVersionLine -Version $ver); Color = [System.ConsoleColor]::DarkGray }
        [pscustomobject]@{ Text = ''; Color = [System.ConsoleColor]::DarkGray }
        [pscustomobject]@{ Text = (Format-ProductReleaseDateLine -ReleaseDate $released); Color = [System.ConsoleColor]::DarkGray }
        [pscustomobject]@{ Text = ''; Color = [System.ConsoleColor]::DarkGray }
        [pscustomobject]@{ Text = (Format-ProductAuthorLine); Color = [System.ConsoleColor]::DarkGray }
        [pscustomobject]@{ Text = ''; Color = [System.ConsoleColor]::DarkGray }
    )

    return $rows
}

function Get-VisibleText {
    param([string]$Text)

    if ([string]::IsNullOrEmpty($Text)) { return '' }
    return $Text
}

function Get-BrandInnerWidth {
    param([hashtable]$Header = $null)

    $logoCol = Get-LogoColumnWidth
    $gap = 2
    $panelRows = @(Get-ProductPanelRows -Header $Header)
    $maxRight = 0

    foreach ($pr in $panelRows) {
        $w = Get-DisplayWidth (Get-VisibleText $pr.Text)
        if ($w -gt $maxRight) { $maxRight = $w }
    }

    $emailLine = Format-ProductEmailLine
    if (-not [string]::IsNullOrEmpty($emailLine)) {
        $emailWidth = Get-DisplayWidth $emailLine
        if ($emailWidth -gt $maxRight) { $maxRight = $emailWidth }
    }

    $innerWidth = $logoCol + $gap + $maxRight
    $consoleWidth = Get-ConsoleLineWidth
    if (($innerWidth + 1) -gt $consoleWidth) {
        $innerWidth = [Math]::Max(24, $consoleWidth - 1)
    }
    return $innerWidth
}

function Get-BrandSeparatorLineWidth {
    param([int]$BrandInnerWidth)

    return $BrandInnerWidth + (Get-BrandSeparatorExtra)
}

function Format-BrandHorizontalLine {
    param([int]$BrandInnerWidth)

    return ' ' + ('═' * ($BrandInnerWidth + (Get-BrandSeparatorExtra)))
}

function Format-BrandSectionCapLine {
    param(
        [string]$Title,
        [int]$BrandInnerWidth
    )

    $inner = $BrandInnerWidth + (Get-BrandSeparatorExtra)
    $titleCore = if ([string]::IsNullOrWhiteSpace($Title)) { '' } else { [string]$Title }
    $titlePart = if ($titleCore) { " $titleCore " } else { '' }
    $titleWidth = Get-DisplayWidth $titlePart

    if ([string]::IsNullOrEmpty($titlePart)) {
        return Format-BrandHorizontalLine -BrandInnerWidth $BrandInnerWidth
    }
    if ($titleWidth -ge $inner) {
        return ' ' + (Truncate-DisplayText $titleCore $inner)
    }

    $remain = $inner - $titleWidth
    $left = [Math]::Floor($remain / 2.0)
    $right = $remain - $left
    return ' ' + ('═' * $left) + $titlePart + ('═' * $right)
}

function Write-BrandSectionCapLine {
    param(
        [int]$Row,
        [string]$Title,
        [int]$BrandInnerWidth,
        [System.ConsoleColor]$SepColor = [System.ConsoleColor]::DarkCyan,
        [System.ConsoleColor]$TitleColor = [System.ConsoleColor]::White
    )

    try { [Console]::SetCursorPosition(0, $Row) } catch { return }

    $inner = $BrandInnerWidth + (Get-BrandSeparatorExtra)
    $titleCore = if ([string]::IsNullOrWhiteSpace($Title)) { '' } else { [string]$Title }
    $titlePart = if ($titleCore) { " $titleCore " } else { '' }
    $titleWidth = Get-DisplayWidth $titlePart
    $width = Get-SafeWriteLineWidth -Row $Row
    $maxInner = [Math]::Max(0, $width - 1)
    if ($inner -gt $maxInner) { $inner = $maxInner }

    Write-Host ' ' -NoNewline

    if ([string]::IsNullOrEmpty($titlePart) -or $titleWidth -ge $inner) {
        $body = if ($titleWidth -ge $inner) { Truncate-DisplayText $titleCore $inner } else { '═' * $inner }
        Write-Host $body -NoNewline -ForegroundColor $SepColor
        $used = 1 + (Get-DisplayWidth $body)
    }
    else {
        $remain = $inner - $titleWidth
        $left = [Math]::Floor($remain / 2.0)
        $right = $remain - $left
        Write-Host ('═' * $left) -NoNewline -ForegroundColor $SepColor
        Write-Host $titlePart -NoNewline -ForegroundColor $TitleColor
        Write-Host ('═' * $right) -NoNewline -ForegroundColor $SepColor
        $used = 1 + $inner
    }

    if ($used -lt $width) {
        Write-Host (' ' * ($width - $used)) -NoNewline
    }

    Set-ConsoleCursorAfterRowWrite -Row $Row
}

function Write-HeaderBrandRow {
    param(
        [int]$Row,
        [string]$LeftText,
        [string]$RightText,
        [System.ConsoleColor]$LeftColor = [System.ConsoleColor]::DarkCyan,
        [System.ConsoleColor]$RightColor = [System.ConsoleColor]::DarkGray,
        [int]$LogoColumnWidth,
        [int]$Gap = 2,
        [int]$BrandInnerWidth = 0
    )

    try { [Console]::SetCursorPosition(0, $Row) } catch { return }

    $width = Get-SafeConsoleLineWidth
    $left = Pad-DisplayText $LeftText $LogoColumnWidth
    $leftWidth = Get-DisplayWidth $left

    if ($BrandInnerWidth -gt 0) {
        $rightMax = $BrandInnerWidth - $leftWidth - $Gap
    }
    else {
        $rightMax = $width - $leftWidth - $Gap
    }
    if ($rightMax -lt 0) { $rightMax = 0 }

    $visibleRight = Get-VisibleText $RightText
    $truncatedVisible = Truncate-DisplayText $visibleRight $rightMax
    if ($visibleRight -ne $RightText -and $truncatedVisible -eq $visibleRight) {
        $rightOutput = $RightText
    }
    elseif ($truncatedVisible -ne $visibleRight) {
        $rightOutput = $truncatedVisible
    }
    else {
        $rightOutput = $RightText
    }
    $rightWidth = Get-DisplayWidth $truncatedVisible

    if ($BrandInnerWidth -gt 0) {
        Write-Host ' ' -NoNewline
    }

    Write-Host $left -NoNewline -ForegroundColor $LeftColor
    if ($Gap -gt 0) {
        Write-Host (' ' * $Gap) -NoNewline
    }
    Write-Host $rightOutput -NoNewline -ForegroundColor $RightColor

    if ($BrandInnerWidth -gt 0) {
        $innerUsed = $leftWidth + $Gap + $rightWidth
        $innerPad = $BrandInnerWidth - $innerUsed
        if ($innerPad -gt 0) {
            Write-Host (' ' * $innerPad) -NoNewline
        }
        $used = 1 + $BrandInnerWidth
    }
    else {
        $used = $leftWidth + $Gap + $rightWidth
    }

    if ($used -lt $width) {
        Write-Host (' ' * ($width - $used)) -NoNewline
    }

    try { [Console]::SetCursorPosition(0, $Row) } catch {}
}

function Format-HeaderSeparator {
    $width = Get-ConsoleLineWidth
    $inner = [Math]::Max(40, [Math]::Min($width - 2, 64))
    return ' ' + ('═' * $inner)
}

function Set-CursorVisible {
    param([bool]$Visible)
    try { [Console]::CursorVisible = $Visible } catch {}
}

function Reset-ConsoleViewportTop {
  Sync-ConsoleViewportTop
}

$script:ConsoleDrawBatchDepth = 0

function Enter-ConsoleDrawBatch {
    if ($script:ConsoleDrawBatchDepth -le 0) {
        try { [Console]::SetCursorPosition(0, 0) } catch {}
    }
    $script:ConsoleDrawBatchDepth++
}

function Complete-ConsoleDrawBatch {
    param([hashtable]$ToolkitShell = $null)

    if ($script:ConsoleDrawBatchDepth -gt 0) {
        $script:ConsoleDrawBatchDepth--
    }
    if ($script:ConsoleDrawBatchDepth -gt 0) { return }

    Sync-ConsoleViewportTop
    try { [Console]::SetCursorPosition(0, 0) } catch {}
}

function Get-ConsoleViewportTop {
    try {
        $raw = $Host.UI.RawUI
        if ($null -ne $raw) { return [Math]::Max(0, [int]$raw.WindowTop) }
    }
    catch {}

    try { return [Math]::Max(0, [int][Console]::WindowTop) } catch {}
    return 0
}

function Test-ConsoleBottomRow {
    param([int]$Row)

    return ($Row -ge (Get-ConsoleLineHeight - 1) - 1)
}

function Prepare-ConsoleRowWrite {
    param([int]$Row)

    # 写底栏前先钉住 (0,0)，避免 SetCursor(末行) + Write-Host 触发缓冲上滚
    if (Test-ConsoleBottomRow -Row $Row) {
        try { [Console]::SetCursorPosition(0, 0) } catch {}
    }
}

function Set-ConsoleCursorAfterRowWrite {
    param([int]$Row)

    if (Test-ConsoleBottomRow -Row $Row) {
        try { [Console]::SetCursorPosition(0, 0) } catch {}
    }
    else {
        try { [Console]::SetCursorPosition(0, $Row) } catch {}
    }
}

function Sync-ConsoleViewportTop {
    if ($script:ConsoleDrawBatchDepth -gt 0) { return $false }
    if ((Get-ConsoleViewportTop) -le 0) { return $false }

    try {
        $raw = $Host.UI.RawUI
        if ($null -ne $raw) {
            $raw.WindowTop = 0
            if ((Get-ConsoleViewportTop) -le 0) { return $true }
        }
    }
    catch {}

    try {
        [Console]::SetWindowPosition(0, 0)
        return $true
    }
    catch {
        return $false
    }
}

function Set-MenuInputCursorPosition {
    param(
        [hashtable]$Layout,
        [hashtable]$ToolkitShell = $null
    )

    # Shell 内切换视图时勿移到底栏行，否则会带动视口滚动
    if ($ToolkitShell) { return }

    try { [Console]::SetCursorPosition(0, $Layout.BottomRow) } catch {}
}

function Get-ConsoleLineWidth {
    $width = [Console]::WindowWidth
    if ($null -eq $width -or $width -lt 20) { return 80 }
    return $width
}

function Get-SafeConsoleLineWidth {
    return [Math]::Max(1, (Get-ConsoleLineWidth - 1))
}

function Get-SafeWriteLineWidth {
    param([int]$Row = -1)

    $width = Get-SafeConsoleLineWidth
    if ($Row -ge 0) {
        $lastRow = Get-ConsoleLineHeight - 1
        # 末行及底栏上一行再缩 2 列，避免写满触发缓冲上滚
        if ($Row -ge ($lastRow - 1)) {
            return [Math]::Max(1, $width - 2)
        }
    }
    return $width
}

function Get-ConsoleSurfaceBackground {
    if ($null -ne $script:ConsoleSurfaceBackground) {
        return $script:ConsoleSurfaceBackground
    }

    try {
        $script:ConsoleSurfaceBackground = [System.ConsoleColor]$Host.UI.RawUI.BackgroundColor
    }
    catch {
        $script:ConsoleSurfaceBackground = [System.ConsoleColor]::Black
    }

    return $script:ConsoleSurfaceBackground
}

function New-ConsoleBufferCell {
    param(
        [char]$Character = ' ',
        [System.ConsoleColor]$Foreground = [System.ConsoleColor]::Gray,
        [System.ConsoleColor]$Background = [System.ConsoleColor]::Black,
        [System.Management.Automation.Host.BufferCellType]$CellType = [System.Management.Automation.Host.BufferCellType]::Complete
    )

    if ($Background -eq [System.ConsoleColor]::Black) {
        $Background = Get-ConsoleSurfaceBackground
    }

    New-Object System.Management.Automation.Host.BufferCell(
        $Character,
        $Foreground,
        $Background,
        $CellType
    )
}

function Set-ConsoleBufferCellsChar {
    param(
        [System.Management.Automation.Host.BufferCell[]]$Cells,
        [int]$Width,
        [ref]$Col,
        [char]$Character,
        [System.ConsoleColor]$Foreground,
        [System.ConsoleColor]$Background
    )

    $col = $Col.Value
    if ($col -ge $Width) { return }

    $charWidth = $(if (Test-WideCharacter $Character) { 2 } else { 1 })
    if (($col + $charWidth) -gt $Width) { return }

    if ($charWidth -eq 2) {
        $Cells[$col] = New-ConsoleBufferCell -Character $Character -Foreground $Foreground `
            -Background $Background -CellType ([System.Management.Automation.Host.BufferCellType]::Leading)
        if ($col + 1 -lt $Width) {
            $Cells[$col + 1] = New-ConsoleBufferCell -Character ' ' -Foreground $Foreground `
                -Background $Background -CellType ([System.Management.Automation.Host.BufferCellType]::Trailing)
        }
        $Col.Value = $col + 2
    }
    else {
        $Cells[$col] = New-ConsoleBufferCell -Character $Character -Foreground $Foreground -Background $Background
        $Col.Value = $col + 1
    }
}

function Test-ConsoleBufferDrawAvailable {
    try {
        return ($null -ne $Host.UI.RawUI)
    }
    catch {
        return $false
    }
}

function Test-UseConsoleBufferDraw {
    param([int]$Row = -1)

    if (-not (Test-ConsoleBufferDrawAvailable)) { return $false }
    if ($script:ConsoleDrawBatchDepth -gt 0) { return $true }
    if ($Row -ge 0 -and (Test-ConsoleBottomRow -Row $Row)) { return $true }
    return $false
}

function Test-UseConsoleListBufferDraw {
    return (Test-ConsoleBufferDrawAvailable)
}

function New-ConsoleBufferRowCells {
    param(
        [int]$Width,
        [array]$Segments = $null,
        [string]$Text = '',
        [System.ConsoleColor]$Foreground = [System.ConsoleColor]::Gray,
        [System.ConsoleColor]$Background = [System.ConsoleColor]::Black,
        [System.ConsoleColor]$DefaultForeground = [System.ConsoleColor]::Gray
    )

    if ($Background -eq [System.ConsoleColor]::Black) {
        $Background = Get-ConsoleSurfaceBackground
    }

    $cells = New-Object 'System.Management.Automation.Host.BufferCell[]' $Width
    $blank = New-ConsoleBufferCell -Foreground $DefaultForeground -Background $Background
    for ($i = 0; $i -lt $Width; $i++) {
        $cells[$i] = $blank
    }

    if ($Text) {
        $padded = Pad-DisplayText -Text $Text -TargetWidth $Width
        $col = 0
        $colRef = [ref]$col
        foreach ($ch in $padded.ToCharArray()) {
            if ($col -ge $Width) { break }
            Set-ConsoleBufferCellsChar -Cells $cells -Width $Width -Col $colRef -Character $ch `
                -Foreground $Foreground -Background $Background
        }
        return $cells
    }

    if ($Segments) {
        $col = 0
        $colRef = [ref]$col
        foreach ($seg in $Segments) {
            if ($col -ge $Width) { break }
            $fg = if ($seg.Color) { $seg.Color } else { $DefaultForeground }
            $bg = if ($seg.Background) { $seg.Background } else { $Background }
            $segText = if ($seg.Text) { [string]$seg.Text } else { '' }
            foreach ($ch in $segText.ToCharArray()) {
                if ($col -ge $Width) { break }
                Set-ConsoleBufferCellsChar -Cells $cells -Width $Width -Col $colRef -Character $ch `
                    -Foreground $fg -Background $bg
            }
        }
    }

    return $cells
}

function Write-ConsoleBufferRowCells {
    param(
        [int]$Row,
        [System.Management.Automation.Host.BufferCell[]]$Cells
    )

    $width = $Cells.Length
    $block = New-Object 'System.Management.Automation.Host.BufferCell[,]' 1, $width
    for ($c = 0; $c -lt $width; $c++) {
        $block[0, $c] = $Cells[$c]
    }

    $origin = New-Object System.Management.Automation.Host.Coordinates 0, $Row
    $Host.UI.RawUI.SetBufferContents($origin, $block)
}

function Write-ConsoleBufferRow {
    param(
        [int]$Row,
        [string]$Text,
        [System.ConsoleColor]$Foreground = [System.ConsoleColor]::Gray,
        [System.ConsoleColor]$Background = [System.ConsoleColor]::Black
    )

    $width = Get-SafeWriteLineWidth -Row $Row
    $cells = New-ConsoleBufferRowCells -Width $width -Text $Text -Foreground $Foreground `
        -Background $Background -DefaultForeground $Foreground
    Write-ConsoleBufferRowCells -Row $Row -Cells $cells
}

function Write-ConsoleBufferRowSegments {
    param(
        [int]$Row,
        [array]$Segments,
        [System.ConsoleColor]$DefaultForeground = [System.ConsoleColor]::Gray,
        [System.ConsoleColor]$Background = [System.ConsoleColor]::Black
    )

    $width = Get-SafeWriteLineWidth -Row $Row
    $cells = New-ConsoleBufferRowCells -Width $width -Segments $Segments `
        -Background $Background -DefaultForeground $DefaultForeground
    Write-ConsoleBufferRowCells -Row $Row -Cells $cells
}

function Write-ConsoleBufferBlock {
    param(
        [int]$StartRow,
        [array]$RowSpecs,
        [int]$Width = 0
    )

    if ($RowSpecs.Count -le 0) { return }
    if ($Width -le 0) {
        $Width = Get-SafeWriteLineWidth -Row $StartRow
    }

    $height = $RowSpecs.Count
    $block = New-Object 'System.Management.Automation.Host.BufferCell[,]' $height, $Width

    for ($r = 0; $r -lt $height; $r++) {
        $spec = $RowSpecs[$r]
        $rowCells = $null
        if ($null -ne $spec.Text -and $null -eq $spec.Segments) {
            $bg = if ($spec.Background) { $spec.Background } else { (Get-ConsoleSurfaceBackground) }
            $rowCells = New-ConsoleBufferRowCells -Width $Width -Text ([string]$spec.Text) `
                -Foreground $spec.Foreground -Background $bg `
                -DefaultForeground $spec.Foreground
        }
        else {
            $dfg = if ($spec.DefaultForeground) { $spec.DefaultForeground } else { [System.ConsoleColor]::Gray }
            $bg = if ($spec.Background) { $spec.Background } else { (Get-ConsoleSurfaceBackground) }
            $rowCells = New-ConsoleBufferRowCells -Width $Width -Segments $spec.Segments `
                -Background $bg -DefaultForeground $dfg
        }
        for ($c = 0; $c -lt $Width; $c++) {
            $block[$r, $c] = $rowCells[$c]
        }
    }

    $origin = New-Object System.Management.Automation.Host.Coordinates 0, $StartRow
    $Host.UI.RawUI.SetBufferContents($origin, $block)
}

function Write-FixedLine {
    param(
        [int]$Row,
        [string]$Text,
        [bool]$Selected = $false,
        [System.ConsoleColor]$Color = [System.ConsoleColor]::Gray,
        [switch]$Disabled
    )

    # 写满整行会触发 Windows 控制台自动换行/上滚，顶部分隔线会被挤没
    $width = Get-SafeWriteLineWidth -Row $Row
    $textWidth = Get-DisplayWidth $Text
    if ($textWidth -gt $width) {
        $Text = Truncate-DisplayText $Text $width
    }

    $foreground = $Color
    $background = Get-ConsoleSurfaceBackground
    if ($Selected) {
        $foreground = [System.ConsoleColor]::Black
        $background = [System.ConsoleColor]::Cyan
    }
    elseif ($Disabled) {
        $foreground = [System.ConsoleColor]::DarkGray
    }

    if (Test-UseConsoleBufferDraw -Row $Row) {
        try {
            Write-ConsoleBufferRow -Row $Row -Text $Text -Foreground $foreground -Background $background
            return
        }
        catch {
            # 非 ConsoleHost 等宿主回退 Write-Host 路径
        }
    }

    Prepare-ConsoleRowWrite -Row $Row
    try { [Console]::SetCursorPosition(0, $Row) } catch { return }

    $textWidth = Get-DisplayWidth $Text
    if ($textWidth -gt $width) {
        $Text = Truncate-DisplayText $Text $width
        $textWidth = Get-DisplayWidth $Text
    }
    $padded = $Text + (' ' * ($width - $textWidth))

    if ($Selected) {
        Write-Host $padded -NoNewline -ForegroundColor Black -BackgroundColor Cyan
    }
    elseif ($Disabled) {
        Write-Host $padded -NoNewline -ForegroundColor DarkGray
    }
    else {
        Write-Host $padded -NoNewline -ForegroundColor $Color
    }

    # 末行及上一行写完后勿把光标留在底栏，否则会触发缓冲上滚
    Set-ConsoleCursorAfterRowWrite -Row $Row
}

function New-ToolkitMenuHeader {
    param(
        [string]$SectionTitle = '',
        [string]$Version = '',
        [switch]$HideSectionTitle
    )

    if (-not $HideSectionTitle -and -not $SectionTitle) {
        $SectionTitle = Get-I18n -Key 'page.home.toolList'
    }

    if (-not $Version) {
        try { $Version = (Get-Manifest).version } catch { $Version = '' }
    }

    return @{
        Version          = $Version
        SectionTitle     = $SectionTitle
        HideSectionTitle = [bool]$HideSectionTitle
    }
}

function New-ToolMenuHeader {
    param(
        $ToolConfig,
        [string]$SectionTitle = ''
    )

    $version = ''
    try { $version = (Get-Manifest).version } catch { }

    if ([string]::IsNullOrWhiteSpace($SectionTitle)) {
        $SectionTitle = Get-I18n -Key 'page.home.toolMenuDefaultTitle'
    }

    return @{
        Version      = $version
        SectionTitle = $SectionTitle
    }
}

function Write-MenuHeader {
    param(
        [hashtable]$Header,
        [int]$StartRow = 0
    )

    $row = $StartRow
    $brandInnerWidth = Get-BrandInnerWidth -Header $Header

    if ($Header.HideSectionTitle) {
        Write-FixedLine $row '' -Color DarkGray
        $row++

        Write-BrandSectionCapLine -Row $row -Title (Get-BrandTitle) -BrandInnerWidth $brandInnerWidth
        $row++
    }
    else {
        Write-FixedLine $row '' -Color DarkGray
        $row++

        Write-FixedLine $row (Format-BrandHorizontalLine -BrandInnerWidth $brandInnerWidth) -Color DarkCyan
        $row++
    }

    Write-FixedLine $row '' -Color DarkGray
    $row++

    $logoLines = @(Get-AsciiLogo)
    $logoCol = Get-LogoColumnWidth
    $panelRows = @(Get-ProductPanelRows -Header $Header)
    $brandHeight = Get-BrandBlockRowCount -Header $Header
    $welcomeRow = $brandHeight - 1

    for ($r = 0; $r -lt $brandHeight; $r++) {
        $isWelcomeRow = ($r -eq $welcomeRow)

        if ($isWelcomeRow) {
            $leftText = Format-LogoWelcomeLine -LogoColumnWidth $logoCol
            $leftColor = [System.ConsoleColor]::Cyan
            $rightText = Format-ProductEmailLine
            $rightColor = [System.ConsoleColor]::DarkGray
        }
        elseif ($r -lt $logoLines.Count) {
            $leftText = $logoLines[$r]
            $leftColor = [System.ConsoleColor]::DarkCyan
            if ($r -lt $panelRows.Count) {
                $panelRow = $panelRows[$r]
                $rightText = $panelRow.Text
                $rightColor = $panelRow.Color
            }
            else {
                $rightText = ''
                $rightColor = [System.ConsoleColor]::DarkGray
            }
        }
        else {
            $leftText = ''
            $leftColor = [System.ConsoleColor]::DarkCyan
            $rightText = ''
            $rightColor = [System.ConsoleColor]::DarkGray
        }

        Write-HeaderBrandRow -Row $row `
            -LeftText $leftText `
            -RightText $rightText `
            -LeftColor $leftColor `
            -RightColor $rightColor `
            -LogoColumnWidth $logoCol `
            -BrandInnerWidth $brandInnerWidth
        $row++
    }

    Write-FixedLine $row '' -Color DarkGray
    $row++

    if (-not $Header.HideSectionTitle) {
        Write-FixedLine $row (Format-BrandHorizontalLine -BrandInnerWidth $brandInnerWidth) -Color DarkCyan
        $row++

        Write-FixedLine $row '' -Color DarkGray
        $row++

        $section = if ($Header.SectionTitle) {
            "  $($Header.SectionTitle)"
        }
        else {
            "  $(Get-I18n -Key 'page.home.defaultSection')"
        }
        Write-FixedLine $row $section -Color White
    }
}

function Get-ConsoleLineHeight {
    $height = [Console]::WindowHeight
    if ($null -eq $height -or $height -lt 10) { return 40 }
    return $height
}

function Format-MenuTableCell {
    param(
        [string]$Text,
        [int]$Width
    )

    $value = if ($null -eq $Text) { '' } else { [string]$Text }
    return Pad-DisplayText (Truncate-DisplayText $value $Width) $Width
}

function Format-MenuPageNumber {
    param(
        [int]$Value,
        [int]$PageCount
    )

    $width = Get-MenuPageNumberDisplayWidth -PageCount $PageCount
    return $Value.ToString().PadLeft($width, '0')
}

function Sync-MenuListScrollOffset {
    param(
        [int]$SelectedIndex,
        [int]$PageStart,
        [int]$ItemsOnPage,
        [int]$ViewportHeight,
        [int]$ScrollOffset
    )

    if ($ViewportHeight -le 0 -or $ItemsOnPage -le 0) { return 0 }

    $local = $SelectedIndex - $PageStart
    if ($local -lt 0) { return 0 }
    if ($ItemsOnPage -le $ViewportHeight) { return 0 }

    $maxOffset = $ItemsOnPage - $ViewportHeight
    if ($local -lt $ScrollOffset) { return $local }
    if ($local -ge ($ScrollOffset + $ViewportHeight)) {
        return [Math]::Min($maxOffset, $local - $ViewportHeight + 1)
    }
    return $ScrollOffset
}

function Format-MenuBarCellContent {
    param(
        [string]$Text,
        [int]$CellInnerWidth,
        [int]$CellPad = 2
    )

    $text = if ($Text) { $Text.Trim() } else { '' }
    if ($CellInnerWidth -le 0) { return '' }

    $textWidth = Get-DisplayWidth $text
    if ($textWidth -gt $CellInnerWidth) {
        return Truncate-DisplayText $text $CellInnerWidth
    }

    $free = $CellInnerWidth - $textWidth
    if ($free -ge (2 * $CellPad)) {
        $left = $CellPad + [int][Math]::Floor(($free - (2 * $CellPad)) / 2)
    }
    else {
        $left = [int][Math]::Floor($free / 2)
    }
    return (' ' * $left) + $text + (' ' * ($CellInnerWidth - $textWidth - $left))
}

function Format-MenuBarLine {
    param(
        [int]$InnerWidth,
        [string[]]$Segments,
        [int]$CellPad = 2,
        [int]$ColumnCount = 0
    )

    $parts = @($Segments)
    if ($ColumnCount -gt 0) {
        while ($parts.Count -lt $ColumnCount) {
            $parts += ''
        }
        if ($parts.Count -gt $ColumnCount) {
            $parts = @($parts[0..($ColumnCount - 1)])
        }
    }
    else {
        $parts = @($parts | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    if ($parts.Count -eq 0) { return ' |' }

    if ($InnerWidth -lt ($parts.Count + 1)) {
        $InnerWidth = $parts.Count + 1
    }

    $available = $InnerWidth - ($parts.Count + 1)
    $baseCell = [Math]::Floor($available / $parts.Count)
    $extra = $available % $parts.Count

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('|')
    for ($i = 0; $i -lt $parts.Count; $i++) {
        $cellInner = $baseCell + $(if ($i -lt $extra) { 1 } else { 0 })
        $content = Format-MenuBarCellContent -Text $parts[$i] -CellInnerWidth $cellInner -CellPad $CellPad
        [void]$sb.Append($content)
        [void]$sb.Append('|')
    }

    $bar = $sb.ToString()
    $barWidth = Get-DisplayWidth $bar
    if ($barWidth -gt $InnerWidth) {
        $bar = Truncate-DisplayText $bar $InnerWidth
    }
    elseif ($barWidth -lt $InnerWidth) {
        $bar = $bar + (' ' * ($InnerWidth - $barWidth))
    }

    return ' ' + $bar
}

function Write-MenuBarLine {
    param(
        [int]$Row,
        [int]$InnerWidth,
        [string[]]$Segments,
        [int]$ColumnCount = 0,
        [System.ConsoleColor]$Color = [System.ConsoleColor]::DarkGray
    )

    $text = Format-MenuBarLine -InnerWidth $InnerWidth -Segments $Segments -ColumnCount $ColumnCount
    Write-FixedLine $Row $text -Color $Color
}

function Select-MenuPageSelectionIndex {
    param(
        [int]$NewPageIndex,
        [int]$OldSelectedIndex,
        [int]$OldPageIndex,
        [int]$PageSize,
        [int]$ItemCount
    )

    $local = $OldSelectedIndex - ($OldPageIndex * $PageSize)
    if ($local -lt 0) { $local = 0 }

    $pageStart = $NewPageIndex * $PageSize
    if ($pageStart -ge $ItemCount) {
        return [Math]::Max(0, $ItemCount - 1)
    }

    $itemsOnPage = [Math]::Min($PageSize, $ItemCount - $pageStart)
    if ($itemsOnPage -le 0) { return $pageStart }

    $newLocal = [Math]::Min($local, $itemsOnPage - 1)
    return $pageStart + $newLocal
}

function Write-MenuBarLineBuffer {
    param(
        [int]$HintRow,
        [int]$StatusRow,
        [int]$InnerWidth,
        [string[]]$TopSegments,
        [string[]]$BottomSegments,
        [int]$ColumnCount = 0,
        [System.ConsoleColor]$TopColor = [System.ConsoleColor]::DarkGray,
        [System.ConsoleColor]$BottomColor = [System.ConsoleColor]::DarkGray
    )

    $surfaceBg = Get-ConsoleSurfaceBackground
    $topText = Format-MenuBarLine -InnerWidth $InnerWidth -Segments $TopSegments -ColumnCount $ColumnCount
    $bottomText = Format-MenuBarLine -InnerWidth $InnerWidth -Segments $BottomSegments -ColumnCount $ColumnCount

    if ($StatusRow -eq ($HintRow + 1)) {
        Write-ConsoleBufferBlock -StartRow $HintRow -RowSpecs @(
            @{ Text = $topText; Foreground = $TopColor; Background = $surfaceBg }
            @{ Text = $bottomText; Foreground = $BottomColor; Background = $surfaceBg }
        )
    }
    else {
        Write-ConsoleBufferRow -Row $HintRow -Text $topText -Foreground $TopColor -Background $surfaceBg
        Write-ConsoleBufferRow -Row $StatusRow -Text $bottomText -Foreground $BottomColor -Background $surfaceBg
    }
}

function Clear-MenuListChrome {
    param(
        [hashtable]$Layout,
        [int]$VisibleRowsDrawn = 0,
        [switch]$SkipViewportClear
    )

    $viewport = $Layout.ListViewportHeight
    if ($viewport -le 0) { $viewport = $Layout.PageSize }

    $useBatchBuffer = ($script:ConsoleDrawBatchDepth -gt 0 -and (Test-ConsoleBufferDrawAvailable))
    $surfaceBg = Get-ConsoleSurfaceBackground

    if (-not $SkipViewportClear) {
        if ($useBatchBuffer) {
            for ($row = $VisibleRowsDrawn; $row -lt $viewport; $row++) {
                Write-ConsoleBufferRow -Row ($Layout.ListStartRow + $row) -Text '' `
                    -Foreground ([System.ConsoleColor]::DarkGray) -Background $surfaceBg
            }
        }
        else {
            for ($row = $VisibleRowsDrawn; $row -lt $viewport; $row++) {
                Write-FixedLine ($Layout.ListStartRow + $row) '' -Selected $false
            }
        }
    }

    if ($Layout.GapRow -ge 0) {
        if ($useBatchBuffer) {
            Write-ConsoleBufferRow -Row $Layout.GapRow -Text '' `
                -Foreground ([System.ConsoleColor]::DarkGray) -Background $surfaceBg
        }
        else {
            Write-FixedLine $Layout.GapRow '' -Color DarkGray
        }
    }

    if ($Layout.PinFooterToBottom) {
        if ($Layout.HintRow -ge 0) {
            $clearEnd = $Layout.HintRow - 1
        }
        elseif ($Layout.ToolbarRow -ge 0) {
            $clearEnd = $Layout.ToolbarRow - 1
        }
        else {
            $clearEnd = $Layout.StatusRow - 1
        }
        if ($Layout.GapRow -ge 0) { $clearStart = $Layout.GapRow + 1 }
        else { $clearStart = $Layout.ListEndRow + 1 }

        if ($clearStart -le $clearEnd) {
            if ($useBatchBuffer) {
                $count = $clearEnd - $clearStart + 1
                $specs = New-Object 'object[]' $count
                for ($i = 0; $i -lt $count; $i++) {
                    $specs[$i] = @{
                        Text       = ''
                        Foreground = [System.ConsoleColor]::DarkGray
                        Background = $surfaceBg
                    }
                }
                Write-ConsoleBufferBlock -StartRow $clearStart -RowSpecs $specs
            }
            else {
                for ($row = $clearStart; $row -le $clearEnd; $row++) {
                    if ($row -ge 0) {
                        Write-FixedLine $row '' -Color DarkGray
                    }
                }
            }
        }
    }
}
function Update-PaginatedMenuFooter {
    param(
        [int]$HintRow,
        [int]$StatusRow,
        [int]$PageIndex,
        [int]$PageCount,
        [int]$ItemCount,
        [int]$SelectedIndex,
        [string]$NumberBuffer,
        [string]$CountLabel,
        [string[]]$FooterExtraHints = @(),
        [string]$FlashMessage = '',
        [ValidateSet('Default', 'Split')]
        [string]$FooterLayout = 'Default',
        [int]$BrandInnerWidth = 0
    )

    if ($FooterLayout -eq 'Split') {
        $lineWidth = if ($BrandInnerWidth -gt 0) {
            Get-BrandSeparatorLineWidth -BrandInnerWidth $BrandInnerWidth
        }
        else {
            [Math]::Max(40, [Math]::Min((Get-ConsoleLineWidth - 2), 64))
        }
        $footerColCount = 5

        $actionSegments = @(
            (Get-I18n -Key 'common.action.quitEsc')
            (Get-I18n -Key 'common.nav.settings')
            (Get-I18n -Key 'common.nav.help')
            ''
            ''
        )

        if ($FlashMessage) {
            if ($script:ConsoleDrawBatchDepth -gt 0 -and (Test-ConsoleBufferDrawAvailable)) {
                try {
                    Write-MenuBarLineBuffer -HintRow $HintRow -StatusRow $StatusRow -InnerWidth $lineWidth `
                        -TopSegments @($FlashMessage, '', '', '', '') -BottomSegments $actionSegments `
                        -ColumnCount $footerColCount -TopColor ([System.ConsoleColor]::Yellow)
                    return
                }
                catch { }
            }
            Write-MenuBarLine -Row $HintRow -InnerWidth $lineWidth `
                -Segments @($FlashMessage, '', '', '', '') -ColumnCount $footerColCount `
                -Color ([System.ConsoleColor]::Yellow)
            Write-MenuBarLine -Row $StatusRow -InnerWidth $lineWidth -ColumnCount $footerColCount -Segments $actionSegments
            return
        }

        $navSegments = @(
            (Get-I18n -Key 'common.pagination.page' -Vars @{
                current = (Format-MenuPageNumber -Value ($PageIndex + 1) -PageCount $PageCount)
                total   = (Format-MenuPageNumber -Value $PageCount -PageCount $PageCount)
            })
            (Get-I18n -Key 'common.pagination.totalCount' -Vars @{ count = $ItemCount; unit = $CountLabel })
            (Get-I18n -Key 'common.action.navSelect')
            (Get-I18n -Key 'common.action.navPage')
            (Get-I18n -Key 'common.action.confirmEnter')
        )

        if ($script:ConsoleDrawBatchDepth -gt 0 -and (Test-ConsoleBufferDrawAvailable)) {
            try {
                Write-MenuBarLineBuffer -HintRow $HintRow -StatusRow $StatusRow -InnerWidth $lineWidth `
                    -TopSegments $navSegments -BottomSegments $actionSegments -ColumnCount $footerColCount
                return
            }
            catch { }
        }

        Write-MenuBarLine -Row $HintRow -InnerWidth $lineWidth -Segments $navSegments -ColumnCount $footerColCount
        Write-MenuBarLine -Row $StatusRow -InnerWidth $lineWidth -ColumnCount $footerColCount -Segments $actionSegments
        return
    }

    if ($FlashMessage) {
        Write-FixedLine $HintRow " $FlashMessage" -Color Yellow
    }
    else {
        $index = if ($SelectedIndex -ge 0) { $SelectedIndex + 1 } else { 0 }
        $hint = Get-MenuListHintLine -Index $index -NumberBuffer $NumberBuffer
        foreach ($extra in $FooterExtraHints) {
            if ($extra) { $hint += " |  $extra" }
        }
        Write-FixedLine $HintRow $hint -Color DarkGray
    }

    $pageText = Get-I18n -Key 'common.pagination.page' -Vars @{
        current = (Format-MenuPageNumber -Value ($PageIndex + 1) -PageCount $PageCount)
        total   = (Format-MenuPageNumber -Value $PageCount -PageCount $PageCount)
    }
    $status = $pageText + (Get-I18n -Key 'common.pagination.totalCount' -Vars @{ count = $ItemCount; unit = $CountLabel })
    Write-FixedLine $StatusRow $status -Color DarkGray
}

function Get-MenuLayout {
    param(
        [int]$PageSize = 0,
        [hashtable]$Header = $null,
        [switch]$HideColHeader,
        [switch]$PinFooterToBottom,
        [int]$FooterGapRows = 0
    )

    if ($PageSize -le 0) {
        $PageSize = Get-MenuPageSize
    }

    $headerRows = Get-MenuHeaderRowCount -Header $Header
    $brandInnerWidth = if ($Header) { Get-BrandInnerWidth -Header $Header } else { 0 }
    if ($HideColHeader) {
        $colHeaderRow = -1
        $listStartRow = $headerRows
    }
    else {
        $colHeaderRow = $headerRows
        $listStartRow = $headerRows + 1
    }

    $gapRow = -1
    if ($PinFooterToBottom) {
        $consoleHeight = Get-ConsoleLineHeight
        $statusRow = $consoleHeight - 1
        $hintRow = $consoleHeight - 2
        if ($FooterGapRows -gt 0) {
            $gapRow = $consoleHeight - 3
            $listEndRow = [Math]::Max($listStartRow, $gapRow - 1)
        }
        else {
            $listEndRow = [Math]::Max($listStartRow, $consoleHeight - 3)
        }
        $listViewportHeight = [Math]::Max(1, $listEndRow - $listStartRow + 1)
        $bottomRow = $statusRow
    }
    else {
        $listViewportHeight = $PageSize
        $listEndRow = $listStartRow + $PageSize - 1
        $hintRow = $listEndRow + 1 + $FooterGapRows
        if ($FooterGapRows -gt 0) {
            $gapRow = $listEndRow + 1
        }
        $statusRow = $hintRow + 1
        $bottomRow = $statusRow
    }

    return @{
        HeaderRows         = $headerRows
        ColHeaderRow       = $colHeaderRow
        ListStartRow       = $listStartRow
        ListEndRow         = $listEndRow
        ListViewportHeight = $listViewportHeight
        PageSize           = $PageSize
        HintRow            = $hintRow
        StatusRow          = $statusRow
        GapRow             = $gapRow
        BottomRow          = $bottomRow
        HideColHeader      = [bool]$HideColHeader
        PinFooterToBottom  = [bool]$PinFooterToBottom
        FooterGapRows      = $FooterGapRows
        BrandInnerWidth    = $brandInnerWidth
    }
}

function Format-MenuNumberedRow {
    param(
        [int]$GlobalIndex,
        [string]$Label,
        [int]$NumWidth,
        [bool]$Selected,
        [bool]$Disabled,
        [int]$DisplayNumber = 0
    )

    $numValue = if ($DisplayNumber -gt 0) { $DisplayNumber } else { $GlobalIndex + 1 }
    $num = Format-ListDisplayNumber -Number $numValue -NumWidth $NumWidth
    $mark = if ($Selected) { '>' } else { ' ' }
    return " $mark $num  $Label"
}

function Draw-PaginatedMenuRow {
    param(
        [array]$Items,
        [int]$ListStartRow,
        [int]$ViewRow,
        [int]$ItemIndex,
        [int]$NumWidth,
        [scriptblock]$GetItemLabel,
        [scriptblock]$TestItemEnabled,
        [bool]$Selected,
        [scriptblock]$GetItemDisplayNumber = $null,
        [scriptblock]$DrawListRow = $null
    )

    $screenRow = $ListStartRow + $ViewRow
    if ($ItemIndex -ge 0 -and $ItemIndex -lt $Items.Count) {
        $item = $Items[$ItemIndex]
        $enabled = & $TestItemEnabled $item $ItemIndex
        $displayNumber = 0
        if ($GetItemDisplayNumber) {
            $displayNumber = & $GetItemDisplayNumber $item $ItemIndex
        }

        if ($DrawListRow) {
            & $DrawListRow $screenRow $item $ItemIndex $Selected $NumWidth $displayNumber $enabled
            return
        }

        $label = & $GetItemLabel $item $ItemIndex
        $text = Format-MenuNumberedRow -GlobalIndex $ItemIndex -Label $label `
            -NumWidth $NumWidth -Selected $Selected -Disabled:(-not $enabled) `
            -DisplayNumber $displayNumber
        Write-FixedLine $screenRow $text -Selected $Selected -Disabled:(-not $enabled -and -not $Selected)
    }
    else {
        Write-FixedLine $screenRow '' -Selected $false
    }
}

function Set-MenuListScrollOffset {
    param(
        [ref]$ScrollOffset,
        [int]$SelectedIndex,
        [int]$PageIndex,
        [int]$PageSize,
        [int]$ItemCount,
        [int]$ViewportHeight
    )

    $pageStart = $PageIndex * $PageSize
    $itemsOnPage = if ($ItemCount -gt 0) {
        [Math]::Min($PageSize, $ItemCount - $pageStart)
    }
    else { 0 }

    $ScrollOffset.Value = Sync-MenuListScrollOffset -SelectedIndex $SelectedIndex `
        -PageStart $pageStart -ItemsOnPage $itemsOnPage `
        -ViewportHeight $ViewportHeight -ScrollOffset $ScrollOffset.Value
}

function Write-ListRowFromSpec {
    param(
        [int]$ScreenRow,
        [hashtable]$Spec
    )

    if ($null -ne $Spec.Text -and $null -eq $Spec.Segments) {
        $bg = if ($Spec.Background) { $Spec.Background } else { (Get-ConsoleSurfaceBackground) }
        Write-ConsoleBufferRow -Row $ScreenRow -Text ([string]$Spec.Text) `
            -Foreground $Spec.Foreground -Background $bg
    }
    else {
        $dfg = if ($Spec.DefaultForeground) { $Spec.DefaultForeground } else { [System.ConsoleColor]::Gray }
        $bg = if ($Spec.Background) { $Spec.Background } else { (Get-ConsoleSurfaceBackground) }
        Write-ConsoleBufferRowSegments -Row $ScreenRow -Segments $Spec.Segments `
            -DefaultForeground $dfg -Background $bg
    }
}

function Update-PaginatedMenuSelection {
    param(
        [array]$Items,
        [hashtable]$Layout,
        [int]$PageIndex,
        [int]$PageSize,
        [int]$OldIndex,
        [int]$NewIndex,
        [int]$ScrollOffset,
        [int]$NumWidth,
        [scriptblock]$GetItemLabel,
        [scriptblock]$TestItemEnabled,
        [scriptblock]$GetItemDisplayNumber = $null,
        [scriptblock]$DrawListRow = $null,
        [scriptblock]$GetListRowSpec = $null
    )

    $pageStart = $PageIndex * $PageSize
    $viewport = $Layout.ListViewportHeight
    if ($viewport -le 0) { $viewport = $PageSize }

    $oldLocal = $OldIndex - $pageStart - $ScrollOffset
    $newLocal = $NewIndex - $pageStart - $ScrollOffset

    if ($GetListRowSpec -and (Test-UseConsoleListBufferDraw)) {
        try {
            if ($OldIndex -ge 0 -and $oldLocal -ge 0 -and $oldLocal -lt $viewport) {
                $displayNumber = 0
                if ($GetItemDisplayNumber) {
                    $displayNumber = & $GetItemDisplayNumber $Items[$OldIndex] $OldIndex
                }
                $enabled = & $TestItemEnabled $Items[$OldIndex] $OldIndex
                $spec = & $GetListRowSpec $OldIndex $false $NumWidth $displayNumber $enabled
                Write-ListRowFromSpec -ScreenRow ($Layout.ListStartRow + $oldLocal) -Spec $spec
            }

            if ($NewIndex -ge 0 -and $newLocal -ge 0 -and $newLocal -lt $viewport) {
                $displayNumber = 0
                if ($GetItemDisplayNumber) {
                    $displayNumber = & $GetItemDisplayNumber $Items[$NewIndex] $NewIndex
                }
                $enabled = & $TestItemEnabled $Items[$NewIndex] $NewIndex
                $spec = & $GetListRowSpec $NewIndex $true $NumWidth $displayNumber $enabled
                Write-ListRowFromSpec -ScreenRow ($Layout.ListStartRow + $newLocal) -Spec $spec
            }
            return
        }
        catch {
            # 回退逐行 Draw
        }
    }

    if ($OldIndex -ge 0 -and $oldLocal -ge 0 -and $oldLocal -lt $viewport) {
        Draw-PaginatedMenuRow -Items $Items -ListStartRow $Layout.ListStartRow -ViewRow $oldLocal `
            -ItemIndex $OldIndex -NumWidth $NumWidth -GetItemLabel $GetItemLabel `
            -TestItemEnabled $TestItemEnabled -Selected $false `
            -GetItemDisplayNumber $GetItemDisplayNumber -DrawListRow $DrawListRow
    }

    if ($NewIndex -ge 0 -and $newLocal -ge 0 -and $newLocal -lt $viewport) {
        Draw-PaginatedMenuRow -Items $Items -ListStartRow $Layout.ListStartRow -ViewRow $newLocal `
            -ItemIndex $NewIndex -NumWidth $NumWidth -GetItemLabel $GetItemLabel `
            -TestItemEnabled $TestItemEnabled -Selected $true `
            -GetItemDisplayNumber $GetItemDisplayNumber -DrawListRow $DrawListRow
    }
}

function Redraw-PaginatedMenuPage {
    param(
        [array]$Items,
        [hashtable]$Layout,
        [int]$PageIndex,
        [int]$SelectedIndex,
        [int]$NumWidth,
        [scriptblock]$GetItemLabel,
        [scriptblock]$TestItemEnabled,
        [int]$PageSize = 0,
        [scriptblock]$GetItemDisplayNumber = $null,
        [int]$ListScrollOffset = 0,
        [scriptblock]$DrawListRow = $null,
        [scriptblock]$GetListRowSpec = $null
    )

    if ($PageSize -le 0) { $PageSize = $Layout.PageSize }

    $viewport = $Layout.ListViewportHeight
    if ($viewport -le 0) { $viewport = $PageSize }

    if ($Items.Count -eq 0) {
        Write-FixedLine $Layout.ListStartRow " $(Get-I18n -Key 'page.home.noToolsRegistered')" -Color DarkGray
        for ($row = 1; $row -lt $viewport; $row++) {
            Write-FixedLine ($Layout.ListStartRow + $row) '' -Selected $false
        }
        Clear-MenuListChrome -Layout $Layout -VisibleRowsDrawn 1
        return
    }

    $pageStart = $PageIndex * $PageSize
    $itemsOnPage = 0
    if ($Items.Count -gt 0) {
        $itemsOnPage = [Math]::Min($PageSize, $Items.Count - $pageStart)
    }

    if ($GetListRowSpec -and (Test-ConsoleBufferDrawAvailable)) {
        try {
            $rowSpecs = New-Object 'System.Collections.Generic.List[object]' $viewport
            $rowsDrawn = 0
            for ($row = 0; $row -lt $viewport; $row++) {
                $itemIndex = $pageStart + $ListScrollOffset + $row
                if ($itemIndex -lt ($pageStart + $itemsOnPage) -and $itemIndex -lt $Items.Count) {
                    $selected = ($SelectedIndex -eq $itemIndex)
                    $displayNumber = 0
                    if ($GetItemDisplayNumber) {
                        $displayNumber = & $GetItemDisplayNumber $Items[$itemIndex] $itemIndex
                    }
                    $enabled = & $TestItemEnabled $Items[$itemIndex] $itemIndex
                    $rowSpecs.Add((& $GetListRowSpec $itemIndex $selected $NumWidth $displayNumber $enabled))
                    $rowsDrawn++
                }
                else {
                    $surfaceBg = Get-ConsoleSurfaceBackground
                    $rowSpecs.Add(@{
                        Text       = ''
                        Foreground = [System.ConsoleColor]::DarkGray
                        Background = $surfaceBg
                    })
                }
            }
            Write-ConsoleBufferBlock -StartRow $Layout.ListStartRow -RowSpecs @($rowSpecs.ToArray())
            Clear-MenuListChrome -Layout $Layout -VisibleRowsDrawn $rowsDrawn -SkipViewportClear
            return
        }
        catch {
            # 回退逐行绘制
        }
    }

    $rowsDrawn = 0
    for ($row = 0; $row -lt $viewport; $row++) {
        $itemIndex = $pageStart + $ListScrollOffset + $row
        if ($itemIndex -lt ($pageStart + $itemsOnPage) -and $itemIndex -lt $Items.Count) {
            $selected = ($SelectedIndex -eq $itemIndex)
            Draw-PaginatedMenuRow -Items $Items -ListStartRow $Layout.ListStartRow -ViewRow $row `
                -ItemIndex $itemIndex -NumWidth $NumWidth -GetItemLabel $GetItemLabel `
                -TestItemEnabled $TestItemEnabled -Selected $selected `
                -GetItemDisplayNumber $GetItemDisplayNumber -DrawListRow $DrawListRow
            $rowsDrawn++
        }
        else {
            Write-FixedLine ($Layout.ListStartRow + $row) '' -Selected $false
        }
    }

    Clear-MenuListChrome -Layout $Layout -VisibleRowsDrawn $rowsDrawn
}

function Show-PaginatedMenu {
    <#
    .SYNOPSIS
        统一分页菜单：固定顶栏 + 编号列表 + ↑↓ 选择 + ←→ 翻页 + 数字快速定位 + Enter 确认当前高亮项。
        输入编号时保持列表高亮；Backspace 删空编号后恢复输入前选中项；方向键仅清空输入不影响选中。
    #>
    param(
        [hashtable]$Header,
        [array]$Items,
        [int]$PageSize = 0,
        [scriptblock]$GetItemLabel,
        [scriptblock]$TestItemEnabled = { param($Item, $Index) $true },
        [string]$CountLabel = '',
        [hashtable]$LetterKeys = @{},
        [string[]]$FooterExtraHints = @(),
        [switch]$HideColHeader,
        [ValidateSet('Default', 'Split')]
        [string]$FooterLayout = 'Default',
        [scriptblock]$GetItemDisplayNumber = $null,
        [scriptblock]$ResolveMenuNumber = $null,
        [int]$NumberDisplayWidth = 0,
        [scriptblock]$DrawListRow = $null,
        [hashtable]$ToolkitShell = $null,
        [scriptblock]$RenderFooter = $null,
        [scriptblock]$GetListRowSpec = $null,
        [switch]$EscMeansBack
    )

    if (-not $PSBoundParameters.ContainsKey('HideColHeader')) {
        $HideColHeader = $true
    }

    $resolveNumberFn = $ResolveMenuNumber
    if (-not $resolveNumberFn) {
        $resolveNumberFn = ${function:Resolve-ListNumberIndexDefault}
    }

    if (-not $CountLabel) {
        $CountLabel = Get-I18n -Key 'common.unit.item'
    }

    if ($PageSize -le 0) {
        $PageSize = Get-MenuPageSize
    }

    $pinFooter = ($FooterLayout -eq 'Split') -or [bool]$ToolkitShell
    if ($ToolkitShell) {
        $layout = $ToolkitShell.Layout
        if ($PageSize -le 0) {
            $PageSize = $layout.ListViewportHeight
        }
    }
    else {
        $layout = Get-MenuLayout -PageSize $PageSize -Header $Header -HideColHeader:$HideColHeader `
            -PinFooterToBottom:$pinFooter -FooterGapRows 0
    }
    if ($NumberDisplayWidth -gt 0) {
        $numWidth = $NumberDisplayWidth
    }
    else {
        $maxDisplay = 0
        for ($i = 0; $i -lt $Items.Count; $i++) {
            $dn = if ($GetItemDisplayNumber) {
                & $GetItemDisplayNumber $Items[$i] $i
            }
            else {
                $i + 1
            }
            if ($dn -gt $maxDisplay) { $maxDisplay = $dn }
        }
        $numWidth = Get-ListNumberDisplayWidth -MaxNumber $maxDisplay
    }
    $pageCount = [Math]::Max(1, [Math]::Ceiling($Items.Count / [double]$PageSize))

    $pageIndex = 0
    $selectedIndex = if ($Items.Count -eq 0) { -1 } else { 0 }
    $numberBuffer = ''
    $flashMessage = ''
    $listScrollOffset = 0

    function Apply-MenuNumberBuffer {
        param([string]$Buffer)
        if ([string]::IsNullOrEmpty($Buffer)) { return }
        if ($Items.Count -eq 0) {
            Set-Variable -Name flashMessage -Value (Get-I18n -Key 'flash.invalidNumber') -Scope 1
            return
        }
        $num = [int]$Buffer
        $idx = & $resolveNumberFn $Items $num
        if ($idx -ge 0 -and $idx -lt $Items.Count) {
            if (-not (& $TestItemEnabled $Items[$idx] $idx)) {
                Set-Variable -Name flashMessage -Value (Get-I18n -Key 'flash.disabledNumber') -Scope 1
                return
            }
            $newPage = [Math]::Floor($idx / [double]$PageSize)
            Set-Variable -Name selectedIndex -Value $idx -Scope 1
            Set-Variable -Name pageIndex -Value $newPage -Scope 1
            Set-MenuListScrollOffset -ScrollOffset ([ref]$listScrollOffset) `
                -SelectedIndex $idx -PageIndex $newPage -PageSize $PageSize `
                -ItemCount $Items.Count -ViewportHeight $layout.ListViewportHeight
        }
        else {
            Set-Variable -Name flashMessage -Value (Get-I18n -Key 'flash.invalidNumber') -Scope 1
        }
    }

    $redrawPage = {
        Redraw-PaginatedMenuPage -Items $Items -Layout $layout -PageIndex $pageIndex `
            -SelectedIndex $selectedIndex -NumWidth $numWidth `
            -GetItemLabel $GetItemLabel -TestItemEnabled $TestItemEnabled -PageSize $PageSize `
            -GetItemDisplayNumber $GetItemDisplayNumber -ListScrollOffset $listScrollOffset `
            -DrawListRow $DrawListRow -GetListRowSpec $GetListRowSpec
    }

    $invokeFooter = {
        param(
            [string]$FlashMessage = ''
        )

        if ($RenderFooter) {
            & $RenderFooter @{ FlashMessage = $FlashMessage }
            return
        }

        if ($ToolkitShell -and $FooterLayout -eq 'Split') {
            Write-ToolkitShellFooter -Shell $ToolkitShell -Template MenuSplit -MenuFooter @{
                PageIndex     = $pageIndex
                PageCount     = $pageCount
                ItemCount     = $Items.Count
                SelectedIndex = $selectedIndex
                NumberBuffer  = $numberBuffer
                CountLabel    = $CountLabel
                FlashMessage  = $FlashMessage
            }
            return
        }

        Update-PaginatedMenuFooter -HintRow $layout.HintRow -StatusRow $layout.StatusRow `
            -PageIndex $pageIndex -PageCount $pageCount -ItemCount $Items.Count `
            -SelectedIndex $selectedIndex -NumberBuffer $numberBuffer -CountLabel $CountLabel `
            -FooterExtraHints $FooterExtraHints -FooterLayout $FooterLayout `
            -BrandInnerWidth $layout.BrandInnerWidth -FlashMessage $FlashMessage
    }

    if (-not $ToolkitShell) {
        Clear-Host
        Set-CursorVisible $false
        Write-MenuHeader -Header $Header -StartRow 0
    }
    else {
        Set-CursorVisible $false
    }

    if (-not $layout.HideColHeader) {
        Write-FixedLine $layout.ColHeaderRow (Get-I18n -Key 'page.home.colHeader') -Color DarkGray
    }

    Set-MenuListScrollOffset -ScrollOffset ([ref]$listScrollOffset) `
        -SelectedIndex $selectedIndex -PageIndex $pageIndex -PageSize $PageSize `
        -ItemCount $Items.Count -ViewportHeight $layout.ListViewportHeight
    if ($ToolkitShell) {
        Enter-ConsoleDrawBatch
    }
    & $redrawPage
    & $invokeFooter
    if ($ToolkitShell) {
        Register-ToolkitShellFooter -Shell $ToolkitShell -Renderer {
            param([hashtable]$FooterState = @{})

            $flash = if ($FooterState.FlashMessage) { [string]$FooterState.FlashMessage } else { '' }
            & $invokeFooter -FlashMessage $flash
        }.GetNewClosure()
        Complete-ConsoleDrawBatch -ToolkitShell $ToolkitShell
    }

    try {
        while ($true) {
            if ($ToolkitShell) {
                $confirmResult = Read-ShellExitIfActive -Shell $ToolkitShell
                if ($confirmResult -eq 'exitCancel') {
                    continue
                }
                if ($confirmResult -eq 'exitConfirmed') {
                    return (Get-ShellNavMarker -Action 'quit')
                }
            }

            $oldIndex = $selectedIndex
            $oldPage = $pageIndex
            $oldScroll = $listScrollOffset
            $flashMessage = ''
            $pageStart = $pageIndex * $PageSize
            $itemsOnPage = [Math]::Min($PageSize, $Items.Count - $pageStart)
            $localIndex = $selectedIndex - $pageStart

            $key = [Console]::ReadKey($true)

            if ($key.Key -eq 'Backspace') {
                if (-not [string]::IsNullOrEmpty($numberBuffer)) {
                    $numberBuffer = $numberBuffer.Substring(0, $numberBuffer.Length - 1)
                    if (-not [string]::IsNullOrEmpty($numberBuffer)) {
                        Apply-MenuNumberBuffer -Buffer $numberBuffer
                    }
                }
            }
            elseif ($key.KeyChar -match '^[0-9]$') {
                $numberBuffer += $key.KeyChar
                Apply-MenuNumberBuffer -Buffer $numberBuffer
            }
            elseif ($key.KeyChar -match '^[qQ]$') {
                if ($EscMeansBack -or ($RenderFooter -and $ToolkitShell)) {
                    Set-MenuInputCursorPosition -Layout $layout -ToolkitShell $ToolkitShell
                    return [pscustomobject]@{ _kind = 'shellNav'; action = 'back' }
                }
            }
            elseif ($key.KeyChar -match '^[a-zA-Z]$') {
                $letter = $key.KeyChar.ToString().ToLowerInvariant()
                if ($LetterKeys.ContainsKey($letter)) {
                    Set-MenuInputCursorPosition -Layout $layout -ToolkitShell $ToolkitShell
                    return $LetterKeys[$letter]
                }
            }
            else {
                switch ($key.Key) {
                    'LeftArrow' {
                        $numberBuffer = ''
                        if ($pageCount -gt 1) {
                            $oldPage = $pageIndex
                            $oldSelected = $selectedIndex
                            if ($pageIndex -gt 0) {
                                $pageIndex--
                            }
                            else {
                                $pageIndex = $pageCount - 1
                            }
                            $selectedIndex = Select-MenuPageSelectionIndex -NewPageIndex $pageIndex `
                                -OldSelectedIndex $oldSelected -OldPageIndex $oldPage `
                                -PageSize $PageSize -ItemCount $Items.Count
                            $listScrollOffset = 0
                            Set-MenuListScrollOffset -ScrollOffset ([ref]$listScrollOffset) `
                                -SelectedIndex $selectedIndex -PageIndex $pageIndex -PageSize $PageSize `
                                -ItemCount $Items.Count -ViewportHeight $layout.ListViewportHeight
                        }
                    }
                    'RightArrow' {
                        $numberBuffer = ''
                        if ($pageCount -gt 1) {
                            $oldPage = $pageIndex
                            $oldSelected = $selectedIndex
                            if ($pageIndex -lt ($pageCount - 1)) {
                                $pageIndex++
                            }
                            else {
                                $pageIndex = 0
                            }
                            $selectedIndex = Select-MenuPageSelectionIndex -NewPageIndex $pageIndex `
                                -OldSelectedIndex $oldSelected -OldPageIndex $oldPage `
                                -PageSize $PageSize -ItemCount $Items.Count
                            $listScrollOffset = 0
                            Set-MenuListScrollOffset -ScrollOffset ([ref]$listScrollOffset) `
                                -SelectedIndex $selectedIndex -PageIndex $pageIndex -PageSize $PageSize `
                                -ItemCount $Items.Count -ViewportHeight $layout.ListViewportHeight
                        }
                    }
                    'UpArrow' {
                        $numberBuffer = ''
                        $pageStart = $pageIndex * $PageSize
                        $itemsOnPage = [Math]::Min($PageSize, $Items.Count - $pageStart)
                        $local = $selectedIndex - $pageStart

                        if ($local -gt 0) {
                            $selectedIndex--
                        }
                        elseif ($pageIndex -gt 0) {
                            $pageIndex--
                            $prevStart = $pageIndex * $PageSize
                            $prevItemsOnPage = [Math]::Min($PageSize, $Items.Count - $prevStart)
                            $selectedIndex = $prevStart + $prevItemsOnPage - 1
                            $listScrollOffset = 0
                        }
                        elseif ($Items.Count -gt 1) {
                            $pageIndex = $pageCount - 1
                            $selectedIndex = $Items.Count - 1
                            $listScrollOffset = 0
                        }
                        Set-MenuListScrollOffset -ScrollOffset ([ref]$listScrollOffset) `
                            -SelectedIndex $selectedIndex -PageIndex $pageIndex -PageSize $PageSize `
                            -ItemCount $Items.Count -ViewportHeight $layout.ListViewportHeight
                    }
                    'DownArrow' {
                        $numberBuffer = ''
                        $pageStart = $pageIndex * $PageSize
                        $itemsOnPage = [Math]::Min($PageSize, $Items.Count - $pageStart)
                        $local = $selectedIndex - $pageStart

                        if ($local -lt ($itemsOnPage - 1)) {
                            $selectedIndex++
                        }
                        elseif ($pageIndex -lt ($pageCount - 1)) {
                            $pageIndex++
                            $selectedIndex = $pageIndex * $PageSize
                            $listScrollOffset = 0
                        }
                        elseif ($Items.Count -gt 1) {
                            $pageIndex = 0
                            $selectedIndex = 0
                            $listScrollOffset = 0
                        }
                        Set-MenuListScrollOffset -ScrollOffset ([ref]$listScrollOffset) `
                            -SelectedIndex $selectedIndex -PageIndex $pageIndex -PageSize $PageSize `
                            -ItemCount $Items.Count -ViewportHeight $layout.ListViewportHeight
                    }
                    'Enter' {
                        $numberBuffer = ''
                        if ($selectedIndex -ge 0 -and $selectedIndex -lt $Items.Count) {
                            $item = $Items[$selectedIndex]
                            if (-not (& $TestItemEnabled $item $selectedIndex)) {
                                $flashMessage = Get-I18n -Key 'flash.disabledItem'
                            }
                            else {
                                Set-MenuInputCursorPosition -Layout $layout -ToolkitShell $ToolkitShell
                                return $item
                            }
                        }
                    }
                    'Escape' {
                        Set-MenuInputCursorPosition -Layout $layout -ToolkitShell $ToolkitShell
                        if ($ToolkitShell) {
                            Request-ShellExit -Shell $ToolkitShell
                            continue
                        }
                        elseif ($EscMeansBack) {
                            return [pscustomobject]@{ _kind = 'shellNav'; action = 'back' }
                        }
                        else {
                            return $null
                        }
                    }
                }
            }

            $scrollChanged = ($oldScroll -ne $listScrollOffset)
            $pageChanged = ($oldPage -ne $pageIndex)
            $selectionChanged = ($oldIndex -ne $selectedIndex)

            $footerChanged = $pageChanged -or $flashMessage
            if ($FooterLayout -ne 'Split' -and -not $RenderFooter) {
                $footerChanged = $footerChanged -or $selectionChanged -or $scrollChanged
            }

            if ($ToolkitShell -and ($pageChanged -or $scrollChanged -or $footerChanged)) {
                if ($script:ConsoleDrawBatchDepth -le 0) {
                    Enter-ConsoleDrawBatch
                }
            }

            if ($pageChanged -or $scrollChanged) {
                & $redrawPage
            }
            elseif ($selectionChanged) {
                Update-PaginatedMenuSelection -Items $Items -Layout $layout -PageIndex $pageIndex `
                    -PageSize $PageSize -OldIndex $oldIndex -NewIndex $selectedIndex `
                    -ScrollOffset $listScrollOffset -NumWidth $numWidth `
                    -GetItemLabel $GetItemLabel -TestItemEnabled $TestItemEnabled `
                    -GetItemDisplayNumber $GetItemDisplayNumber -DrawListRow $DrawListRow `
                    -GetListRowSpec $GetListRowSpec
            }

            if ($footerChanged) {
                & $invokeFooter -FlashMessage $flashMessage
                if (-not $ToolkitShell) {
                    Sync-ConsoleViewportTop
                }
            }

            if ($ToolkitShell -and ($pageChanged -or $scrollChanged -or $footerChanged)) {
                Complete-ConsoleDrawBatch -ToolkitShell $ToolkitShell
            }
        }
    }
    finally {
        # Shell 内视图切换时会话未结束，光标由 Shell 统一管理
        if (-not $ToolkitShell) {
            Set-CursorVisible $true
        }
    }
}

function Show-InteractiveMenu {
    param(
        [array]$Items,
        [string]$Title,
        [string]$Subtitle = '',
        [int]$ViewHeight = 0,
        [scriptblock]$FormatLine,
        [string]$CountLabel = ''
    )

    if ($ViewHeight -le 0) {
        $ViewHeight = Get-MenuPageSize
    }
    if (-not $CountLabel) {
        $CountLabel = Get-I18n -Key 'common.unit.item'
    }

    $header = @{
        Title        = $Title
        Description  = $Subtitle
        Developer    = ''
        Version      = ''
        SectionTitle = (Get-I18n -Key 'page.home.defaultSection')
    }

    $getLabel = {
        param($Item, $Index)
        & $FormatLine $Item $Index $false
    }

    return Show-PaginatedMenu -Header $header -Items $Items -PageSize $ViewHeight `
        -GetItemLabel $getLabel -CountLabel $CountLabel
}

function Write-MessageBlock {
    param(
        [string]$Title,
        [string[]]$Lines = @(),
        [System.ConsoleColor]$TitleColor = 'Cyan'
    )

    Write-Host ''
    Write-Host " $Title" -ForegroundColor $TitleColor
    if ($Lines.Count -gt 0) {
        Write-Host (' ' + ('─' * 48)) -ForegroundColor DarkGray
        foreach ($line in $Lines) {
            Write-Host " $line"
        }
    }
    Write-Host ''
}

function Show-AfterToolPrompt {
    Write-MessageBlock -Title (Get-I18n -Key 'page.afterTool.title') -Lines @(
        (Get-I18n -Key 'page.afterTool.returnList'),
        (Get-I18n -Key 'page.afterTool.exit')
    )

    if ($Host.Name -eq 'ConsoleHost') {
        try {
            while ($true) {
                $key = [Console]::ReadKey($true)
                if ($key.Key -eq 'Enter') { return 'list' }
                if ($key.Key -eq 'Escape') { return 'exit' }
                if ($key.KeyChar -match '^[qQ]$') { return 'exit' }
            }
        }
        catch { }
    }

    $line = Read-Host (Get-I18n -Key 'page.afterTool.promptFallback')
    if ($line -match '^[qQ]$') { return 'exit' }
    return 'list'
}
