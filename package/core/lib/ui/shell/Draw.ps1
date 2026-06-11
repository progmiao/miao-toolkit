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

function Initialize-ToolkitShellBodyView {
    param(
        [hashtable]$Shell,
        [string]$SectionTitle,
        [ValidateSet('ListWithToolbar', 'SystemToolbarOnly')]
        [string]$FooterTemplate
    )

    $useBatch = Test-ToolkitShellUseBufferDraw
    if ($useBatch) { Enter-ConsoleDrawBatch }

    Prepare-ToolkitShellBodyDraw -Shell $Shell

    $previousLayout = Get-ToolkitShellLayoutSnapshot -Layout $Shell.Layout

    Update-ToolkitShellViewLayout -Shell $Shell -FooterTemplate $FooterTemplate -WithSectionTitle
    $null = Sync-ToolkitShellContentMetrics -Shell $Shell

    if ($Shell.Layout.BodyDirty) {
        $Shell.Layout['BodyDirty'] = $false
    }

    Clear-ToolkitShellOrphanRows -Shell $Shell -PreviousLayout $previousLayout
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
