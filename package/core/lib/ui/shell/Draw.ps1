# Shell 内容区绘制准备与 body view 初始化

function Prepare-ToolkitShellBodyDraw {
    param([hashtable]$Shell)

    Set-CursorVisible $false
    Sync-ConsoleViewportTop
    Set-ToolkitShellInputCursor -Shell $Shell
}

function Finalize-ToolkitShellBodyView {
    param([hashtable]$Shell)

    Set-CursorVisible $false
    Sync-ConsoleViewportTop
    Set-ToolkitShellInputCursor -Shell $Shell
}

function Set-ToolkitShellInputCursor {
    param([hashtable]$Shell)

    $safeRow = 0
    if ($Shell -and $Shell.Layout -and $Shell.Layout.ContentStartRow -ge 0) {
        $safeRow = $Shell.Layout.ContentStartRow
    }
    try { [Console]::SetCursorPosition(0, $safeRow) } catch {}
}

function Initialize-ToolkitShellBodyView {
    param(
        [hashtable]$Shell,
        [string]$SectionTitle,
        [ValidateSet('MenuSplit', 'DefaultBar')]
        [string]$FooterTemplate
    )

    Enter-ConsoleDrawBatch

    Prepare-ToolkitShellBodyDraw -Shell $Shell

    $previousLayout = Get-ToolkitShellLayoutSnapshot -Layout $Shell.Layout

    Update-ToolkitShellViewLayout -Shell $Shell -FooterTemplate $FooterTemplate -WithSectionTitle

    if ($Shell.Layout.BodyDirty) {
        $Shell.Layout['BodyDirty'] = $false
    }

    Clear-ToolkitShellOrphanRows -Shell $Shell -PreviousLayout $previousLayout
    Write-ToolkitShellSectionTitle -Shell $Shell -Title $SectionTitle

    Complete-ConsoleDrawBatch -ToolkitShell $Shell
}

function Clear-ToolkitShellBody {
    param([hashtable]$Shell)

    Enter-ConsoleDrawBatch

    $layout = $Shell.Layout
    $startRow = $layout.ContentStartRow
    $endRow = Get-ConsoleLineHeight - 1
    for ($row = $startRow; $row -le $endRow; $row++) {
        if ($row -ge 0) {
            Write-FixedLine $row '' -Color DarkGray
        }
    }
    $layout['BodyDirty'] = $false

    Complete-ConsoleDrawBatch -ToolkitShell $Shell
}
