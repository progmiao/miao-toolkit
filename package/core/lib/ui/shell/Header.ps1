# Shell 顶栏：会话内只画一次，语言切换时重绘；已初始化时从快照读取

function Write-ToolkitShellBrandArea {
    param([hashtable]$Shell)

    if (Test-ToolkitInitValid) {
        $brand = Get-ToolkitBrandSnapshot -Locale (Get-CurrentLocale)
        if ($brand) {
            Write-MenuHeaderFromSnapshot -Snapshot $brand -StartRow 0
            $contentStart = [int]$brand.contentStartRow
            $barWidth = [int]$brand.brandInnerWidth
            $Shell.Layout['ContentStartRow'] = $contentStart
            $Shell.Layout['TopRows'] = $contentStart
            $Shell.Layout['BrandInnerWidth'] = $barWidth
            $Shell['BrandInnerWidth'] = $barWidth
            $Shell['HeaderLocale'] = (Get-CurrentLocale)
            $null = Sync-ToolkitShellContentMetrics -Shell $Shell
            return
        }
    }

    $header = New-ToolkitMenuHeader -HideSectionTitle
    Write-MenuHeader -Header $header -StartRow 0

    $contentStart = Get-MenuHeaderRowCount -Header $header
    $Shell.Layout['ContentStartRow'] = $contentStart
    $Shell.Layout['TopRows'] = $contentStart
    $barWidth = Get-BrandInnerWidth -Header $header
    $Shell.Layout['BrandInnerWidth'] = $barWidth
    $Shell['BrandInnerWidth'] = $barWidth
    $Shell['HeaderLocale'] = (Get-CurrentLocale)
    $null = Sync-ToolkitShellContentMetrics -Shell $Shell
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
        BrandInnerWidth = 0
    }

    Write-ToolkitShellBrandArea -Shell $script:ToolkitShell
    return $script:ToolkitShell
}

function Update-ToolkitShellBrandHeader {
    param([hashtable]$Shell)

    Write-ToolkitShellBrandArea -Shell $Shell
}

function Ensure-ShellHeader {
    param([hashtable]$Shell)

    if (-not $Shell -or -not $Shell.Initialized) {
        return Initialize-ToolkitShell
    }
    return $Shell
}
