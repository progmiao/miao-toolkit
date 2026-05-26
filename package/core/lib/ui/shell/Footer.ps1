# Shell 底栏：gap + toolbar（Home=MenuSplit D=3，Sub=DefaultBar D=2）

function Write-ToolkitShellFooter {
    param(
        [hashtable]$Shell,
        [ValidateSet('MenuSplit', 'DefaultBar')]
        [string]$Template,
        [switch]$ShowSettings,
        [switch]$ShowHelp,
        [switch]$ShowBack,
        [string]$FlashMessage = '',
        [hashtable]$MenuFooter = $null
    )

    $layout = $Shell.Layout
    $barWidth = if ($Shell.BrandInnerWidth -gt 0) { $Shell.BrandInnerWidth } else { $layout.BrandInnerWidth }

    if ($layout.GapRow -ge 0) {
        Write-FixedLine $layout.GapRow '' -Color DarkGray
    }

    if ($Template -eq 'MenuSplit') {
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
            -FlashMessage $splitFlash
        Clear-ToolkitShellBelowFooter -Shell $Shell
        return
    }

    if ($layout.HintRow -ge 0 -and $layout.HintRow -ne $layout.ToolbarRow) {
        Write-FixedLine $layout.HintRow '' -Color DarkGray
    }

    $lineWidth = Get-BrandSeparatorLineWidth -BrandInnerWidth $barWidth
    $footerColCount = 5

    if (-not [string]::IsNullOrWhiteSpace($FlashMessage)) {
        Write-MenuBarLine -Row $layout.ToolbarRow -InnerWidth $lineWidth `
            -Segments @($FlashMessage, '', '', '', '') -ColumnCount $footerColCount `
            -Color ([System.ConsoleColor]::Yellow)
        Clear-ToolkitShellBelowFooter -Shell $Shell
        return
    }

    $segments = @(
        (Get-I18n -Key 'shell.footerExit')
        $(if ($ShowBack) { (Get-I18n -Key 'shell.footerBack') } else { '' })
        $(if ($ShowSettings) { (Get-I18n -Key 'shell.footerSettings') } else { '' })
        ''
        ''
    )
    Write-MenuBarLine -Row $layout.ToolbarRow -InnerWidth $lineWidth -Segments $segments -ColumnCount $footerColCount
    Clear-ToolkitShellBelowFooter -Shell $Shell
}

function Read-ToolkitShellDefaultBarKey {
    param(
        [hashtable]$Shell,
        [switch]$ShowSettings,
        [switch]$ShowHelp,
        [switch]$ShowBack,
        [switch]$Scrollable,
        [ref]$ScrollOffset,
        [int]$MaxScroll
    )

    $confirm = Read-ShellExitIfActive -Shell $Shell
    if ($null -ne $confirm) {
        return $confirm
    }

    Prepare-ToolkitShellBodyDraw -Shell $Shell
    $key = [Console]::ReadKey($true)

    if ($key.Key -eq 'Escape') {
        Request-ShellExit -Shell $Shell
        return 'exitConfirm'
    }
    if ($ShowBack -and $key.KeyChar -match '^[qQ]$') {
        return (Get-ShellNavMarker -Action 'back')
    }
    if ($ShowSettings -and $key.KeyChar -match '^[sS]$') {
        return (Get-ShellNavMarker -Action 'settings')
    }
    if ($ShowHelp -and $key.KeyChar -match '^[hH]$') {
        return (Get-ShellNavMarker -Action 'help')
    }
    if ($Scrollable) {
        if ($key.Key -eq 'UpArrow' -and $ScrollOffset.Value -gt 0) {
            $ScrollOffset.Value--
            return 'scroll'
        }
        if ($key.Key -eq 'DownArrow' -and $ScrollOffset.Value -lt $MaxScroll) {
            $ScrollOffset.Value++
            return 'scroll'
        }
    }

    return $null
}

function New-ShellDefaultFooterRenderer {
    param(
        [hashtable]$Shell,
        [switch]$ShowSettings,
        [switch]$ShowHelp,
        [switch]$ShowBack
    )

    $writeFooter = Get-Item -Path function:Write-ToolkitShellFooter
    return {
        param([hashtable]$FooterState)

        & $writeFooter -Shell $Shell -Template DefaultBar `
            -ShowSettings:$ShowSettings -ShowHelp:$ShowHelp -ShowBack:$ShowBack `
            -FlashMessage $(if ($FooterState.FlashMessage) { [string]$FooterState.FlashMessage } else { '' })
    }.GetNewClosure()
}
