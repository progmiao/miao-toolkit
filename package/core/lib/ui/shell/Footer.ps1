# Shell 底栏：ListWithToolbar（列表双行）/ SystemToolbarOnly（单行系统工具栏）

function Write-ToolkitShellFooter {
    param(
        [hashtable]$Shell,
        [ValidateSet('ListWithToolbar', 'SystemToolbarOnly')]
        [string]$Template,
        [hashtable]$ToolbarConfig = $null,
        [string]$FlashMessage = '',
        [hashtable]$MenuFooter = $null
    )

    $layout = $Shell.Layout
    $barWidth = Get-ToolkitShellLayoutBarInnerWidth -Shell $Shell

    if ($layout.GapRow -ge 0) {
        Write-FixedLine $layout.GapRow '' -Color DarkGray
    }

    if ($Template -eq 'ListWithToolbar') {
        if (-not $MenuFooter) { return }
        $splitFlash = if (-not [string]::IsNullOrWhiteSpace($FlashMessage)) {
            $FlashMessage
        }
        else {
            [string]$MenuFooter.FlashMessage
        }
        Update-PaginatedMenuFooter -HintRow $layout.HintRow -StatusRow $layout.StatusRow `
            -PageIndex $MenuFooter.PageIndex -PageCount $MenuFooter.PageCount `
            -ItemCount $MenuFooter.ItemCount -SelectedIndex $MenuFooter.SelectedIndex `
            -NumberBuffer $MenuFooter.NumberBuffer -CountLabel $MenuFooter.CountLabel `
            -FooterLayout Split -BrandInnerWidth $barWidth `
            -MenuSplitActionSegments $MenuFooter.MenuSplitActionSegments `
            -FlashMessage $splitFlash `
            -MultiSelectNav:([bool]$MenuFooter.MultiSelectNav) `
            -CompactNavStatus:([bool]$MenuFooter.CompactNavStatus)
        Clear-ToolkitShellBelowFooter -Shell $Shell
        return
    }

    if ($layout.HintRow -ge 0 -and $layout.HintRow -ne $layout.ToolbarRow) {
        Write-FixedLine $layout.HintRow '' -Color DarkGray
    }

    $lineWidth = Get-BrandSeparatorLineWidth -BrandInnerWidth $barWidth
    $footerColCount = 5

    if (-not $ToolbarConfig) {
        $ToolbarConfig = New-ShellSystemToolbarConfig
    }

    if (-not [string]::IsNullOrWhiteSpace($FlashMessage)) {
        Write-MenuBarLine -Row $layout.ToolbarRow -InnerWidth $lineWidth `
            -Segments @($FlashMessage, '', '', '', '') -ColumnCount $footerColCount `
            -Color ([System.ConsoleColor]::Yellow)
        Clear-ToolkitShellBelowFooter -Shell $Shell
        return
    }

    $barSegments = Format-ShellSystemToolbarBarSegments -Segments $ToolbarConfig.Segments -ColumnCount $footerColCount
    Write-MenuBarLine -Row $layout.ToolbarRow -InnerWidth $lineWidth `
        -Segments $barSegments -ColumnCount $footerColCount
    Clear-ToolkitShellBelowFooter -Shell $Shell
}

# 兼容旧名
function Read-ToolkitShellDefaultBarKey {
    param(
        [hashtable]$Shell,
        [hashtable]$ToolbarConfig = $null,
        [switch]$ShowSysShortcut,
        [switch]$ShowHelp,
        [switch]$ShowBack,
        [switch]$Scrollable,
        [ref]$ScrollOffset,
        [int]$MaxScroll
    )

    if (-not $ToolbarConfig) {
        $ToolbarConfig = New-ShellSystemToolbarConfig `
            -HideBack:(-not $ShowBack) `
            -HideSystem:(-not $ShowSysShortcut) `
            -HideHelp:(-not $ShowHelp)
    }

    return Read-ShellSystemToolbarKey -Shell $Shell -ToolbarConfig $ToolbarConfig `
        -Scrollable:$Scrollable -ScrollOffset $ScrollOffset -MaxScroll $MaxScroll
}

function New-ShellSystemToolbarFooterRenderer {
    param(
        [hashtable]$Shell,
        [hashtable]$ToolbarConfig
    )

    $capturedShell = $Shell
    $capturedToolbar = $ToolbarConfig
    $fnWriteFooter = ${function:Write-ToolkitShellFooter}
    if (-not $fnWriteFooter) {
        $cmd = Get-Command Write-ToolkitShellFooter -CommandType Function -ErrorAction SilentlyContinue
        if ($cmd) {
            $fnWriteFooter = $cmd.ScriptBlock
        }
    }
    if (-not $fnWriteFooter) {
        throw 'Write-ToolkitShellFooter is not available.'
    }

    return {
        param($InvokeArgs = @{})

        $flash = ''
        if ($null -ne $InvokeArgs -and $InvokeArgs -is [hashtable] -and $InvokeArgs.ContainsKey('FlashMessage')) {
            $flash = [string]$InvokeArgs.FlashMessage
        }

        & $fnWriteFooter -Shell $capturedShell -Template SystemToolbarOnly `
            -ToolbarConfig $capturedToolbar -FlashMessage $flash
    }.GetNewClosure()
}

function New-ShellDefaultFooterRenderer {
    param(
        [hashtable]$Shell,
        [hashtable]$ToolbarConfig
    )

    return New-ShellSystemToolbarFooterRenderer -Shell $Shell -ToolbarConfig $ToolbarConfig
}
