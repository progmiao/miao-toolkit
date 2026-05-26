# Shell 顶栏：会话内只画一次，语言切换时重绘

function Initialize-ToolkitShell {
    param([switch]$Force)

    if (-not $Force -and $script:ToolkitShell -and $script:ToolkitShell.Initialized) {
        return $script:ToolkitShell
    }

    Clear-Host
    Set-CursorVisible $false

    $header = New-ToolkitMenuHeader -HideSectionTitle
    Write-MenuHeader -Header $header -StartRow 0

    $contentStart = Get-MenuHeaderRowCount -Header $header
    $script:ToolkitShell = @{
        Initialized      = $true
        HeaderDrawn      = $true
        HeaderLocale     = (Get-CurrentLocale)
        ExitMode         = $false
        ExitRestoreFooter = $null
        FooterRenderer   = $null
        Layout           = @{
            ContentStartRow = $contentStart
            TopRows         = $contentStart
            BrandInnerWidth = (Get-BrandInnerWidth -Header $header)
        }
        BrandInnerWidth = (Get-BrandInnerWidth -Header $header)
    }
    return $script:ToolkitShell
}

function Update-ToolkitShellBrandHeader {
    param([hashtable]$Shell)

    $header = New-ToolkitMenuHeader -HideSectionTitle
    Write-MenuHeader -Header $header -StartRow 0

    $contentStart = Get-MenuHeaderRowCount -Header $header
    $Shell.Layout['ContentStartRow'] = $contentStart
    $Shell.Layout['TopRows'] = $contentStart
    $barWidth = Get-BrandInnerWidth -Header $header
    $Shell.Layout['BrandInnerWidth'] = $barWidth
    $Shell['BrandInnerWidth'] = $barWidth
    $Shell['HeaderLocale'] = (Get-CurrentLocale)
}

function Ensure-ShellHeader {
    param([hashtable]$Shell)

    if (-not $Shell -or -not $Shell.Initialized) {
        return Initialize-ToolkitShell
    }
    return $Shell
}
