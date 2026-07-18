# Shell 底栏：ListWithToolbar（列表双行）/ SystemToolbarOnly（单行系统工具栏）

function Get-ToolkitShellMessageRow {
    param([hashtable]$Shell)

    if (-not $Shell -or -not $Shell.Layout) { return -1 }
    $layout = $Shell.Layout
    if ($null -ne $layout.MessageRow -and [int]$layout.MessageRow -ge 0) {
        return [int]$layout.MessageRow
    }
    return -1
}

function Write-ToolkitShellMessageRow {
    param(
        [hashtable]$Shell = $null,
        [int]$MessageRow = -1,
        [string]$Message = ''
    )

    if ($MessageRow -lt 0 -and $Shell) {
        $MessageRow = Get-ToolkitShellMessageRow -Shell $Shell
    }
    if ($MessageRow -lt 0) { return }

    if (-not [string]::IsNullOrWhiteSpace($Message)) {
        Write-FixedLine $MessageRow " $Message" -Color Yellow
    }
    else {
        Write-FixedLine $MessageRow '' -Color DarkYellow
    }
}

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

    if ($Template -eq 'ListWithToolbar') {
        if (-not $MenuFooter) { return }
        $splitFlash = if (-not [string]::IsNullOrWhiteSpace($FlashMessage)) {
            $FlashMessage
        }
        else {
            [string]$MenuFooter.FlashMessage
        }
        Write-ToolkitShellMessageRow -Shell $Shell -Message $splitFlash
        Update-PaginatedMenuFooter -HintRow $layout.HintRow -StatusRow $layout.StatusRow `
            -PageIndex $MenuFooter.PageIndex -PageCount $MenuFooter.PageCount `
            -ItemCount $MenuFooter.ItemCount -SelectedIndex $MenuFooter.SelectedIndex `
            -NumberBuffer $MenuFooter.NumberBuffer -CountLabel $MenuFooter.CountLabel `
            -FooterLayout Split -BrandInnerWidth $barWidth `
            -MenuSplitActionSegments $MenuFooter.MenuSplitActionSegments `
            -MultiSelectNav:([bool]$MenuFooter.MultiSelectNav) `
            -CompactNavStatus:([bool]$MenuFooter.CompactNavStatus) `
            -LetterSearchActive:([bool]$MenuFooter.LetterSearchActive) `
            -LetterSearchEnabled:([bool]$MenuFooter.LetterSearchEnabled) `
            -LetterSearchToggleKey $(if ($MenuFooter.LetterSearchToggleKey) { [string]$MenuFooter.LetterSearchToggleKey } else { 'Slash' })
        Clear-ToolkitShellBelowFooter -Shell $Shell
        return
    }

    Write-ToolkitShellMessageRow -Shell $Shell -Message $FlashMessage

    if ($layout.HintRow -ge 0 -and $layout.HintRow -ne $layout.ToolbarRow) {
        Write-FixedLine $layout.HintRow '' -Color DarkGray
    }

    $lineWidth = Get-BrandSeparatorLineWidth -BrandInnerWidth $barWidth
    $footerColCount = 5

    if (-not $ToolbarConfig) {
        $ToolbarConfig = New-ShellSystemToolbarConfig
    }

    $barSegments = Format-ShellSystemToolbarBarSegments -Segments $ToolbarConfig.Segments -ColumnCount $footerColCount
    $barColor = Get-ShellSystemToolbarBarColor -Shell $Shell
    Write-MenuBarLine -Row $layout.ToolbarRow -InnerWidth $lineWidth `
        -Segments $barSegments -ColumnCount $footerColCount -Color $barColor
    Clear-ToolkitShellBelowFooter -Shell $Shell
}

function Invoke-ToolkitShellRegisteredFooter {
    param(
        [hashtable]$Shell,
        [hashtable]$InvokeArgs = @{}
    )

    if (-not $Shell) { return }

    if ($Shell.ExitMode) {
        Write-ShellExitFooter -Shell $Shell
        return
    }

    $renderer = $Shell.FooterRenderer
    if ($renderer) {
        & $renderer $InvokeArgs
    }
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
