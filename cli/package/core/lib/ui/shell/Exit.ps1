# Shell 退出：Esc 进入退出栏，Y/Esc 确认退出

function Register-ToolkitShellFooter {
    param(
        [hashtable]$Shell,
        [scriptblock]$Renderer
    )

    if (-not $Shell) { return }
    $Shell['FooterRenderer'] = $Renderer
}

function Register-ShellExitExtension {
    param(
        [hashtable]$Shell,
        [scriptblock]$OnExitConfirmed
    )

    if (-not $Shell) { return }
    if ($OnExitConfirmed) {
        $Shell['ExitExtension'] = $OnExitConfirmed
    }
    else {
        $Shell.Remove('ExitExtension')
    }
}

function Clear-ShellExitExtension {
    param([hashtable]$Shell)

    if (-not $Shell) { return }
    $Shell.Remove('ExitExtension')
}

function Invoke-ShellExitExtension {
    param([hashtable]$Shell)

    if (-not $Shell) { return }
    if ($Shell.ExitExtension) {
        & $Shell.ExitExtension
    }
}

function Request-ShellExit {
    param([hashtable]$Shell)

    if (-not $Shell) {
        Invoke-MiaoShellQuit
    }

    Start-ShellExit -Shell $Shell
}

function Read-ShellExitIfActive {
    param([hashtable]$Shell)

    if (-not $Shell -or -not $Shell.ExitMode) {
        return $null
    }

    return (Read-ShellExitKey -Shell $Shell)
}

function Clear-ShellExit {
    param([hashtable]$Shell)

    if (-not $Shell) { return }

    $Shell['ExitMode'] = $false
    $Shell['ExitRestoreFooter'] = $null
}

function Reset-ShellExit {
    param([hashtable]$Shell)

    Clear-ShellExit -Shell $Shell
}

function Write-ShellExitFooter {
    param([hashtable]$Shell)

    $layout = $Shell.Layout
    $barWidth = if ($Shell.BrandInnerWidth -gt 0) { $Shell.BrandInnerWidth } else { $layout.BrandInnerWidth }
    $lineWidth = Get-BrandSeparatorLineWidth -BrandInnerWidth $barWidth
    $footerColCount = 3
    $bottomRow = $layout.BottomRow

    if ($layout.HintRow -ge 0 -and $layout.HintRow -ne $bottomRow) {
        Write-FixedLine $layout.HintRow '' -Color DarkGray
    }

    $segments = @(
        (Get-I18n -Key 'message.exitConfirmPrompt')
        (Get-I18nKeyHint -Key (Get-MiaoI18nKeys).Y -LabelKey 'common.confirm')
        (Get-I18nKeyHint -Key (Get-MiaoI18nKeys).N -LabelKey 'common.cancel')
    )
    Write-MenuBarLine -Row $bottomRow -InnerWidth $lineWidth -Segments $segments `
        -ColumnCount $footerColCount -Color ([System.ConsoleColor]::Yellow)
    Clear-ToolkitShellBelowFooter -Shell $Shell
}

function Start-ShellExit {
    param([hashtable]$Shell)

    if (-not $Shell) {
        Invoke-MiaoShellQuit
    }

    $Shell['ExitRestoreFooter'] = $Shell.FooterRenderer
    $Shell['ExitMode'] = $true
    Write-ShellExitFooter -Shell $Shell
    return 'exitConfirm'
}

function Restore-ShellExitFooter {
    param([hashtable]$Shell)

    if (-not $Shell) { return }

    $restore = if ($Shell.ExitRestoreFooter) { $Shell.ExitRestoreFooter } else { $Shell.FooterRenderer }
    Clear-ShellExit -Shell $Shell
    if ($restore) {
        & $restore
        Clear-ToolkitShellBelowFooter -Shell $Shell
    }
}

function Read-ShellExitKey {
    param([hashtable]$Shell)

    Prepare-ToolkitShellBodyDraw -Shell $Shell
    $key = [Console]::ReadKey($true)
    Set-CursorVisible $false

    if ($key.Key -eq 'Escape' -or ($key.KeyChar -match '^[yY]$')) {
        Clear-ShellExit -Shell $Shell
        Invoke-ShellExitExtension -Shell $Shell
        return 'exitConfirmed'
    }

    if ($key.KeyChar -match '^[nN]$' -or $key.Key -eq 'Delete' -or $key.Key -eq 'Backspace') {
        Restore-ShellExitFooter -Shell $Shell
        return 'exitCancel'
    }

    Restore-ShellExitFooter -Shell $Shell
    return 'exitCancel'
}

function Clear-ConsoleInputBuffer {
    while (Test-ConsoleKeyAvailable) {
        [void][Console]::ReadKey($true)
    }
}

function Drain-ConsoleStaleToolbarInput {
    param([int]$MaxEvents = 48)

    $drained = 0
    while ($drained -lt $MaxEvents -and (Test-ConsoleKeyAvailable)) {
        $peek = Get-ConsoleVirtualKeyPeek
        if (-not $peek) { break }
        if ($peek -in @('Enter', 'Escape', 'UpArrow', 'DownArrow')) { break }
        $null = Read-ConsoleVirtualKeyConsume
        $drained++
    }
}

function Drain-ConsoleEscInputIfAvailable {
    param(
        [hashtable]$Shell,
        [scriptblock]$ProcessEsc = $null
    )

    if (-not $Shell) { return }

    $handler = if ($ProcessEsc) { $ProcessEsc } else {
        { Process-ShellEscInputIfAvailable -Shell $Shell }.GetNewClosure()
    }

    while (Test-ConsoleKeyAvailable) {
        $peek = Get-ConsoleVirtualKeyPeek
        if ($peek -ne 'Escape') { break }
        $null = & $handler
    }
}

function Process-ShellEscInputIfAvailable {
    param([hashtable]$Shell)

    if (-not $Shell) { return $null }
    if (Test-ToolkitShellToolbarLocked -Shell $Shell) {
        Drain-ShellLockedToolbarKeys -Shell $Shell
        return $null
    }
    if (-not (Test-ConsoleKeyAvailable)) { return $null }

    if ($Shell.ExitMode) {
        return (Read-ShellExitKey -Shell $Shell)
    }

    $peek = Get-ConsoleVirtualKeyPeek
    if ($peek -ne 'Escape') { return $null }

    $vk = Read-ConsoleVirtualKeyConsume
    if ($vk -eq 'Escape') {
        Request-ShellExit -Shell $Shell
        return 'exitConfirm'
    }

    return $null
}
