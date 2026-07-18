# Shell Y/N 确认（消息行 + 底栏）

function Write-ToolkitShellYnConfirmFooter {
    param([hashtable]$Shell)

    $layout = $Shell.Layout
    $barWidth = if ($Shell.BrandInnerWidth -gt 0) { $Shell.BrandInnerWidth } else { $layout.BrandInnerWidth }
    $lineWidth = Get-BrandSeparatorLineWidth -BrandInnerWidth $barWidth
    $bottomRow = $layout.BottomRow

    $segments = @(
        (Get-I18n -Key 'message.ynConfirmHint')
        (Get-I18nKeyHint -Key (Get-MiaoI18nKeys).Y -LabelKey 'common.confirm')
        (Get-I18nKeyHint -Key (Get-MiaoI18nKeys).N -LabelKey 'common.cancel')
    )
    Write-MenuBarLine -Row $bottomRow -InnerWidth $lineWidth -Segments $segments `
        -ColumnCount 3 -Color ([System.ConsoleColor]::Yellow)
    Clear-ToolkitShellBelowFooter -Shell $Shell
}

function Start-ToolkitShellYnConfirm {
    param(
        [hashtable]$Shell,
        [string]$Message
    )

    if (-not $Shell) { return $false }

    $Shell['YnConfirmMode'] = $true
    $Shell['YnConfirmMessage'] = [string]$Message
    $Shell['YnConfirmRestoreFooter'] = $Shell.FooterRenderer

    Write-ToolkitShellMessageRow -Shell $Shell -Message $Message
    Write-ToolkitShellYnConfirmFooter -Shell $Shell
}

function Clear-ToolkitShellYnConfirm {
    param([hashtable]$Shell)

    if (-not $Shell) { return }

    $restore = if ($Shell.YnConfirmRestoreFooter) { $Shell.YnConfirmRestoreFooter } else { $Shell.FooterRenderer }
    $Shell.Remove('YnConfirmMode')
    $Shell.Remove('YnConfirmMessage')
    $Shell.Remove('YnConfirmRestoreFooter')

    Write-ToolkitShellMessageRow -Shell $Shell -Message ''
    if ($restore) {
        & $restore
        Clear-ToolkitShellBelowFooter -Shell $Shell
    }
}

function Read-ToolkitShellYnConfirmKey {
    param([hashtable]$Shell)

    Prepare-ToolkitShellBodyDraw -Shell $Shell
    $key = [Console]::ReadKey($true)
    Set-CursorVisible $false

    if ($key.KeyChar -match '^[yY]$') {
        Clear-ToolkitShellYnConfirm -Shell $Shell
        return $true
    }

    Clear-ToolkitShellYnConfirm -Shell $Shell
    return $false
}

function Get-ToolkitSharedDepItemConfirmMessage {
    param(
        $Tool,
        $Status
    )

    $otherNames = @($Status.OtherToolCommands) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $detail = Get-I18n -Key 'page.toolDeps.sharedUninstallItem' -Vars @{
        dep   = [string]$Status.Name
        tools = ($otherNames -join ', ')
    }

    return (Get-I18n -Key 'page.toolDeps.sharedUninstallPrompt' -Vars @{
        tool    = [string]$Tool.command
        details = $detail
    })
}

function Confirm-ToolkitDepItemSharedUninstall {
    param(
        $Tool,
        $Status,
        [hashtable]$Shell
    )

    if (-not $Shell -or -not $Status) { return $true }

    $message = Get-ToolkitSharedDepItemConfirmMessage -Tool $Tool -Status $Status
    Start-ToolkitShellYnConfirm -Shell $Shell -Message $message
    return (Read-ToolkitShellYnConfirmKey -Shell $Shell)
}

function Confirm-ToolkitSharedDepUninstall {
    param(
        $Tool,
        [hashtable]$Shell,
        [array]$SharedDeps
    )

    if (-not $Shell -or $SharedDeps.Count -eq 0) { return $true }

    $detailParts = @()
    foreach ($entry in @($SharedDeps)) {
        $otherNames = @($entry.OtherTools | ForEach-Object {
            $n = [string]$_.command
            if ([string]::IsNullOrWhiteSpace($n)) { $n = [string]$_.id }
            $n
        }) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        $detailParts += (Get-I18n -Key 'page.toolDeps.sharedUninstallItem' -Vars @{
            dep   = [string]$entry.Name
            tools = ($otherNames -join ', ')
        })
    }

    $message = Get-I18n -Key 'page.toolDeps.sharedUninstallPrompt' -Vars @{
        tool    = [string]$Tool.command
        details = ($detailParts -join '; ')
    }

    Start-ToolkitShellYnConfirm -Shell $Shell -Message $message
    return (Read-ToolkitShellYnConfirmKey -Shell $Shell)
}
