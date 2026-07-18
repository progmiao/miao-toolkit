# Shell 顶栏：会话内只画一次，语言切换时重绘；已初始化时从快照读取

function Write-ToolkitShellBrandArea {
    param([hashtable]$Shell)

    $layoutWidth = Get-ToolkitShellStandardBrandInnerWidth

    if (Test-ToolkitSessionInitReady) {
        $brand = $null
        if ($Shell -and $Shell.BrandSnapshot) {
            $brand = $Shell.BrandSnapshot
        }
        elseif ($script:ToolkitHomeBrandSnapshot -and `
            [string]$script:ToolkitHomeBrandSnapshotLocale -eq (Get-CurrentLocale)) {
            $brand = $script:ToolkitHomeBrandSnapshot
        }
        if (-not $brand) {
            $brand = Get-ToolkitBrandSnapshot -Locale (Get-CurrentLocale)
        }
        if ($brand) {
            Write-MenuHeaderFromSnapshot -Snapshot $brand -StartRow 0 -LayoutBrandInnerWidth $layoutWidth
            $contentStart = [int]$brand.contentStartRow
            $Shell.Layout['ContentStartRow'] = $contentStart
            $Shell.Layout['TopRows'] = $contentStart
            $Shell['HeaderLocale'] = (Get-CurrentLocale)
            $Shell['BrandSnapshot'] = $brand
            $null = Apply-ToolkitShellLayoutBrandInnerWidth -Shell $Shell -Width $layoutWidth
            return
        }
    }

    $header = New-ToolkitMenuHeader -HideSectionTitle
    Write-MenuHeader -Header $header -StartRow 0 -LayoutBrandInnerWidth $layoutWidth

    $contentStart = Get-MenuHeaderRowCount -Header $header
    $Shell.Layout['ContentStartRow'] = $contentStart
    $Shell.Layout['TopRows'] = $contentStart
    $Shell['HeaderLocale'] = (Get-CurrentLocale)
    $null = Apply-ToolkitShellLayoutBrandInnerWidth -Shell $Shell -Width $layoutWidth
}

function Initialize-ToolkitShell {
    param([switch]$Force)

    if (-not $Force -and $script:ToolkitShell -and $script:ToolkitShell.Initialized) {
        return $script:ToolkitShell
    }

    Clear-Host
    Set-CursorVisible $false

    $script:ToolkitShell = @{
        Initialized       = $true
        HeaderDrawn       = $true
        HeaderLocale      = (Get-CurrentLocale)
        ExitMode          = $false
        ExitRestoreFooter = $null
        FooterRenderer    = $null
        Layout            = @{
            ContentStartRow = 0
            TopRows         = 0
            BrandInnerWidth = 0
        }
        LayoutBrandInnerWidth = 0
        BrandInnerWidth = 0
    }

    $null = Write-ToolkitShellBrandArea -Shell $script:ToolkitShell
    return $script:ToolkitShell
}

function Update-ToolkitShellBrandHeader {
    param([hashtable]$Shell)

    $null = Write-ToolkitShellBrandArea -Shell $Shell
}

function Ensure-ShellHeader {
    param([hashtable]$Shell)

    if (-not $Shell -or -not $Shell.Initialized) {
        return Initialize-ToolkitShell
    }
    return $Shell
}

function Get-ToolkitShellBrandEndRow {
    param([hashtable]$Shell = $null)

    $target = if ($Shell) { $Shell } elseif ($script:ToolkitShell) { $script:ToolkitShell } else { $null }
    if (-not $target -or -not $target.Layout) { return 0 }

    $brandEnd = [Math]::Max(0, [int]$target.Layout.ContentStartRow)
    if ($brandEnd -le 0) {
        $header = New-ToolkitMenuHeader -HideSectionTitle
        $brandEnd = Get-MenuHeaderRowCount -Header $header
    }
    return $brandEnd
}

function Test-ToolkitShellBrandRowWriteBlocked {
    param(
        [int]$Row,
        [hashtable]$Shell = $null
    )

    if ($Row -lt 0) { return $false }
    if ($script:ToolkitShellBrandDrawing) { return $false }

    $target = if ($Shell) { $Shell } elseif ($script:ToolkitShell) { $script:ToolkitShell } else { $null }
    if (-not $target) { return $false }

    $brandEnd = Get-ToolkitShellBrandEndRow -Shell $target
    return ($brandEnd -gt 0 -and $Row -lt $brandEnd)
}

function Get-ToolkitShellBrandSnapshot {
    param([hashtable]$Shell = $null)

    $target = if ($Shell) { $Shell } elseif ($script:ToolkitShell) { $script:ToolkitShell } else { $null }
    if ($target -and $target.BrandSnapshot) {
        return $target.BrandSnapshot
    }
    if ($script:ToolkitHomeBrandSnapshot -and `
        [string]$script:ToolkitHomeBrandSnapshotLocale -eq (Get-CurrentLocale)) {
        return $script:ToolkitHomeBrandSnapshot
    }
    if (Get-Command Get-ToolkitBrandSnapshot -ErrorAction SilentlyContinue) {
        return (Get-ToolkitBrandSnapshot -Locale (Get-CurrentLocale))
    }
    return $null
}

function Resolve-BrandSnapshotConsoleColor {
    param(
        $Value,
        [System.ConsoleColor]$Default = [System.ConsoleColor]::Gray
    )

    if ($null -eq $Value) { return $Default }
    if ($Value -is [System.ConsoleColor]) { return $Value }
    try { return [System.ConsoleColor][int]$Value } catch { return $Default }
}

function Repair-ToolkitShellBrandPanelTextRows {
    param([hashtable]$Shell = $null)

    $target = if ($Shell) { $Shell } elseif ($script:ToolkitShell) { $script:ToolkitShell } else { $null }
    if (-not $target) { return }

    $brandEnd = Get-ToolkitShellBrandEndRow -Shell $target
    if ($brandEnd -le 0) { return }

    $brand = Get-ToolkitShellBrandSnapshot -Shell $target
    if (-not $brand -or -not $brand.rows) { return }

    $layoutWidth = if ([int]$target.LayoutBrandInnerWidth -gt 0) {
        [int]$target.LayoutBrandInnerWidth
    }
    elseif ([int]$target.BrandInnerWidth -gt 0) {
        [int]$target.BrandInnerWidth
    }
    elseif ([int]$brand.brandInnerWidth -gt 0) {
        [int]$brand.brandInnerWidth
    }
    else {
        Get-ToolkitShellStandardBrandInnerWidth
    }

    $fnWriteBrandBuffer = Get-Command Try-Write-HeaderBrandRowBuffer -ErrorAction SilentlyContinue
    $script:ToolkitShellBrandDrawing = $true
    try {
        foreach ($item in @($brand.rows)) {
            if ([string]$item.kind -ne 'brandRow') { continue }
            if ([int]$item.row -ge $brandEnd) { continue }
            if ([string]::IsNullOrWhiteSpace([string]$item.rightText)) { continue }

            $leftColor = Resolve-BrandSnapshotConsoleColor -Value $item.leftColor -Default ([System.ConsoleColor]::DarkCyan)
            $rightColor = Resolve-BrandSnapshotConsoleColor -Value $item.rightColor -Default ([System.ConsoleColor]::DarkGray)
            $drawRow = [int]$item.row
            $written = $false
            if ($fnWriteBrandBuffer) {
                $written = & $fnWriteBrandBuffer -Row $drawRow `
                    -LeftText ([string]$item.leftText) `
                    -RightText ([string]$item.rightText) `
                    -LeftColor $leftColor -RightColor $rightColor `
                    -LogoColumnWidth ([int]$item.logoColumnWidth) `
                    -Gap ([int]$item.gap) `
                    -BrandInnerWidth $layoutWidth
            }
            if (-not $written) {
                Write-HeaderBrandRow -Row $drawRow `
                    -LeftText ([string]$item.leftText) `
                    -RightText ([string]$item.rightText) `
                    -LeftColor $leftColor -RightColor $rightColor `
                    -LogoColumnWidth ([int]$item.logoColumnWidth) `
                    -Gap ([int]$item.gap) `
                    -BrandInnerWidth $layoutWidth
            }
        }
    }
    finally {
        $script:ToolkitShellBrandDrawing = $false
    }

    try { [Console]::SetCursorPosition(0, 0) } catch {}
}

function Restore-ToolkitShellBrandRowsForDepOperation {
    param([hashtable]$Shell = $null)

    Repair-ToolkitShellBrandPanelTextRows -Shell $Shell
}

function Restore-ToolkitShellBrandPanelForDepOperation {
    param([hashtable]$Shell = $null)

    Repair-ToolkitShellBrandPanelTextRows -Shell $Shell
}

function Ensure-ToolkitDepOperationConsoleBuffer {
    if ($script:ToolkitDepOperationBufferExpanded) { return }

    try {
        $raw = $Host.UI.RawUI
        if ($null -eq $raw) { return }

        $windowHeight = [Math]::Max(1, [int]$raw.WindowSize.Height)
        $currentHeight = [Math]::Max($windowHeight, [int]$raw.BufferSize.Height)
        $targetHeight = [Math]::Min([Math]::Max($currentHeight, $windowHeight * 8), 9999)
        if ($targetHeight -le $currentHeight) {
            $script:ToolkitDepOperationBufferExpanded = $true
            return
        }

        $savedTop = [Math]::Max(0, [int]$raw.WindowTop)
        $size = $raw.BufferSize
        $size.Height = $targetHeight
        $raw.BufferSize = $size

        try {
            if ([int]$raw.WindowTop -ne $savedTop) {
                $raw.WindowTop = $savedTop
            }
        }
        catch {}
    }
    catch {}

    $script:ToolkitDepOperationBufferExpanded = $true
}
