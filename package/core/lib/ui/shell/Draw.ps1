# Shell 内容区绘制准备与 body view 初始化

function Prepare-ToolkitShellBodyDraw {
    param([hashtable]$Shell)

    Set-CursorVisible $false
    Set-ToolkitShellInputCursor -Shell $Shell
}

function Finalize-ToolkitShellBodyView {
    param([hashtable]$Shell)

    Set-CursorVisible $false
    Set-ToolkitShellInputCursor -Shell $Shell
    if ((Get-ConsoleViewportTop) -gt 0) {
        $null = Sync-ConsoleViewportTop
    }
}

function Set-ToolkitShellInputCursor {
    param([hashtable]$Shell)

    $safeRow = 0
    if ($Shell -and $Shell.Layout -and $Shell.Layout.ContentStartRow -ge 0) {
        $safeRow = $Shell.Layout.ContentStartRow
    }
    try { [Console]::SetCursorPosition(0, $safeRow) } catch {}
}

function Test-ToolkitShellUseBufferDraw {
    return Test-ShellConsoleBatchDraw
}

function Clear-ToolkitShellListViewport {
    param([hashtable]$Shell)

    if (-not $Shell -or -not $Shell.Layout) { return }

    $layout = $Shell.Layout
    $startRow = [int]$layout.ListStartRow
    if ($startRow -lt 0) { return }

    $endRow = [int]$layout.ListEndRow
    if ($endRow -lt $startRow) { return }

    for ($row = $startRow; $row -le $endRow; $row++) {
        Write-FixedLine $row '' -Color DarkGray
    }
}

function Show-ToolkitShellNoticePage {
    param(
        [hashtable]$Shell,
        [string]$SectionTitle,
        [string]$Message,
        [System.ConsoleColor]$Color = [System.ConsoleColor]::Yellow,
        [int]$DelayMs = 900
    )

    Initialize-ToolkitShellBodyView -Shell $Shell -SectionTitle $SectionTitle `
        -FooterTemplate SystemToolbarOnly
    Clear-ToolkitShellListViewport -Shell $Shell
    Set-ToolkitShellBodyCatalogLine -Shell $Shell -CatalogLine ''
    Render-ToolkitShellCatalogRow -Shell $Shell

    $messageRow = Get-ToolkitShellMessageRow -Shell $Shell
    if ($messageRow -ge 0) {
        if (-not [string]::IsNullOrWhiteSpace($Message)) {
            Write-FixedLine $messageRow " $Message" -Color $Color
        }
        else {
            Write-ToolkitShellMessageRow -Shell $Shell -Message ''
        }
    }

    $toolbar = New-ShellSystemToolbarConfig
    $footerRenderer = New-ShellSystemToolbarFooterRenderer -Shell $Shell -ToolbarConfig $toolbar
    Register-ToolkitShellFooter -Shell $Shell -Renderer $footerRenderer
    & $footerRenderer
    Finalize-ToolkitShellBodyView -Shell $Shell

    if ($DelayMs -gt 0) {
        Start-Sleep -Milliseconds $DelayMs
    }
}

function Initialize-ToolkitShellBodyView {
    param(
        [hashtable]$Shell,
        [string]$SectionTitle,
        [ValidateSet('ListWithToolbar', 'SystemToolbarOnly')]
        [string]$FooterTemplate
    )

    $null = Ensure-ToolkitShellLayoutBrandInnerWidth -Shell $Shell

    $useBatch = Test-ToolkitShellUseBufferDraw
    if ($useBatch) { Enter-ConsoleDrawBatch }

    Prepare-ToolkitShellBodyDraw -Shell $Shell

    $previousLayout = Get-ToolkitShellLayoutSnapshot -Layout $Shell.Layout

    Update-ToolkitShellViewLayout -Shell $Shell -FooterTemplate $FooterTemplate -WithSectionTitle
    $null = Sync-ToolkitShellLayoutLineMetrics -Shell $Shell

    if ($Shell.Layout.BodyDirty) {
        $Shell.Layout['BodyDirty'] = $false
    }

    Clear-ToolkitShellOrphanRows -Shell $Shell -PreviousLayout $previousLayout
    Clear-ToolkitShellListViewport -Shell $Shell
    Write-ToolkitShellSectionTitle -Shell $Shell -Title $SectionTitle

    if ($useBatch) {
        $null = Complete-ConsoleDrawBatch -ToolkitShell $Shell
    }
    else {
        Set-ToolkitShellInputCursor -Shell $Shell
        if ((Get-ConsoleViewportTop) -gt 0) {
            $null = Sync-ConsoleViewportTop
        }
    }
}

function Clear-ToolkitShellBody {
    param([hashtable]$Shell)

    $useBatch = Test-ToolkitShellUseBufferDraw
    if ($useBatch) { Enter-ConsoleDrawBatch }

    $layout = $Shell.Layout
    $startRow = $layout.ContentStartRow
    $endRow = Get-ConsoleLineHeight - 1
    for ($row = $startRow; $row -le $endRow; $row++) {
        if ($row -ge 0) {
            Write-FixedLine $row '' -Color DarkGray
        }
    }
    $layout['BodyDirty'] = $false

    if ($useBatch) {
        $null = Complete-ConsoleDrawBatch -ToolkitShell $Shell
    }
}
