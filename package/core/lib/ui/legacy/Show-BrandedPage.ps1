# 品牌页模板：固定顶栏 + 列表区内容 + 底栏（Esc 返回 / S 设置）
# legacy：standalone 路由逐步迁移至 Shell Page-Host

function New-BrandedContentLine {
    param(
        [string]$Text,
        [string]$Kind = 'text',
        [System.ConsoleColor]$Color = [System.ConsoleColor]::Gray
    )

    return [pscustomobject]@{
        Text  = $Text
        Kind  = $Kind
        Color = $Color
    }
}

function New-ToolkitBrandedHeader {
    param([string]$SectionTitle)

    return New-ToolkitMenuHeader -SectionTitle $SectionTitle
}

function Update-BrandedContentFooter {
    param(
        [int]$HintRow,
        [int]$StatusRow,
        [int]$BrandInnerWidth,
        [switch]$Scrollable
    )

    $barWidth = if ($BrandInnerWidth -gt 0) { $BrandInnerWidth } else {
        [Math]::Max(40, [Math]::Min((Get-ConsoleLineWidth - 2), 64))
    }
    $footerColCount = 4

    $navSegments = @(
        $(if ($Scrollable) { (Get-I18n -Key 'branded.footerScroll') } else { '' })
        ''
        ''
        ''
    )

    Write-MenuBarLine -Row $HintRow -InnerWidth $barWidth -Segments $navSegments -ColumnCount $footerColCount
    Write-MenuBarLine -Row $StatusRow -InnerWidth $barWidth -ColumnCount $footerColCount -Segments @(
        (Get-I18n -Key 'branded.footerEscBack')
        (Get-I18n -Key 'menu.footerActionSettings')
        ''
        ''
    )
}

function Draw-BrandedContentLines {
    param(
        [hashtable]$Layout,
        [array]$Lines,
        [int]$ScrollOffset
    )

    $viewport = $Layout.ListViewportHeight
    for ($row = 0; $row -lt $viewport; $row++) {
        $idx = $ScrollOffset + $row
        $screenRow = $Layout.ListStartRow + $row
        if ($idx -ge 0 -and $idx -lt $Lines.Count) {
            $line = $Lines[$idx]
            $text = if ($line.Text) { " $($line.Text)" } else { '' }
            $color = [System.ConsoleColor]::Gray
            if ($line.Color) {
                $color = $line.Color
            }
            elseif ($line.Kind -eq 'heading') {
                $color = [System.ConsoleColor]::White
            }
            Write-FixedLine $screenRow $text -Color $color
        }
        else {
            Write-FixedLine $screenRow '' -Color DarkGray
        }
    }

    if ($Layout.GapRow -ge 0) {
        Write-FixedLine $Layout.GapRow '' -Color DarkGray
    }
}

function Show-BrandedContentPage {
    param(
        [string]$SectionTitle,
        [array]$Lines,
        [hashtable]$LetterKeys = @{}
    )

    if ($null -eq $Lines) { $Lines = @() }

    $header = New-ToolkitBrandedHeader -SectionTitle $SectionTitle
    $layout = Get-MenuLayout -Header $header -HideColHeader -PinFooterToBottom -FooterGapRows 0
    $scrollOffset = 0
    $viewport = $layout.ListViewportHeight
    $scrollable = ($Lines.Count -gt $viewport)

    Clear-Host
    Set-CursorVisible $false

    try {
        Write-MenuHeader -Header $header -StartRow 0
        Draw-BrandedContentLines -Layout $layout -Lines $Lines -ScrollOffset $scrollOffset
        Update-BrandedContentFooter -HintRow $layout.HintRow -StatusRow $layout.StatusRow `
            -BrandInnerWidth $layout.BrandInnerWidth -Scrollable:$scrollable

        while ($true) {
            $oldScroll = $scrollOffset
            $key = [Console]::ReadKey($true)

            if ($key.Key -eq 'Escape' -or $key.Key -eq 'Enter') {
                return $null
            }

            if ($scrollable) {
                if ($key.Key -eq 'UpArrow') {
                    if ($scrollOffset -gt 0) { $scrollOffset-- }
                }
                elseif ($key.Key -eq 'DownArrow') {
                    $maxScroll = [Math]::Max(0, $Lines.Count - $viewport)
                    if ($scrollOffset -lt $maxScroll) { $scrollOffset++ }
                }
            }

            if ($key.KeyChar -match '^[a-zA-Z]$') {
                $letter = $key.KeyChar.ToString().ToLowerInvariant()
                if ($LetterKeys.ContainsKey($letter)) {
                    try { [Console]::SetCursorPosition(0, $layout.BottomRow) } catch {}
                    return $LetterKeys[$letter]
                }
            }

            if ($oldScroll -ne $scrollOffset) {
                Draw-BrandedContentLines -Layout $layout -Lines $Lines -ScrollOffset $scrollOffset
            }
        }
    }
    finally {
        Set-CursorVisible $true
    }
}
