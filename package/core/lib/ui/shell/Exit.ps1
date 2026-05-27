# Shell 退出：Esc 进入退出栏，Y/Esc 确认退出

function Register-ToolkitShellFooter {
    param(
        [hashtable]$Shell,
        [scriptblock]$Renderer
    )

    if (-not $Shell) { return }
    $Shell['FooterRenderer'] = $Renderer
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
        (Get-I18n -Key 'shell.exitConfirmPrompt')
        (Get-I18n -Key 'common.action.confirmY')
        (Get-I18n -Key 'common.action.cancelN')
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

    if ($key.Key -eq 'Escape' -or ($key.KeyChar -match '^[yY]$')) {
        Clear-ShellExit -Shell $Shell
        return 'exitConfirmed'
    }

    if ($key.KeyChar -match '^[nN]$' -or $key.Key -eq 'Delete' -or $key.Key -eq 'Backspace') {
        Restore-ShellExitFooter -Shell $Shell
        return 'exitCancel'
    }

    Restore-ShellExitFooter -Shell $Shell
    return 'exitCancel'
}
