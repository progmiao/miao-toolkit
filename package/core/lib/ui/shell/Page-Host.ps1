# Shell 滚动内容页（help / update 等 SystemToolbarOnly 视图）

function Invoke-ToolkitShellContentView {
    param(
        [hashtable]$Shell,
        [string]$SectionTitle,
        [array]$Lines,
        [hashtable]$ToolbarConfig = $null
    )

    if ($null -eq $Lines) { $Lines = @() }
    if (-not $ToolbarConfig) {
        $ToolbarConfig = New-ShellSystemToolbarConfig
    }

    Initialize-ToolkitShellBodyView -Shell $Shell -SectionTitle $SectionTitle `
        -FooterTemplate SystemToolbarOnly

    $scrollOffset = 0
    $viewport = $Shell.Layout.ListViewportHeight
    $scrollable = ($Lines.Count -gt $viewport)
    $maxScroll = [Math]::Max(0, $Lines.Count - $viewport)

    $footerRenderer = New-ShellSystemToolbarFooterRenderer -Shell $Shell -ToolbarConfig $ToolbarConfig
    Register-ToolkitShellFooter -Shell $Shell -Renderer $footerRenderer

    Draw-BrandedContentLines -Layout $Shell.Layout -Lines $Lines -ScrollOffset $scrollOffset
    & $footerRenderer
    Finalize-ToolkitShellBodyView -Shell $Shell

    while ($true) {
        $result = Read-ShellSystemToolbarKey -Shell $Shell -ToolbarConfig $ToolbarConfig `
            -Scrollable:$scrollable -ScrollOffset ([ref]$scrollOffset) -MaxScroll $maxScroll

        if ($result -eq 'exitCancel' -or $result -eq 'exitConfirm') {
            continue
        }
        if ($result -eq 'exitConfirmed') {
            return (Get-ShellNavMarker -Action 'quit')
        }

        if ($result -eq 'scroll') {
            Draw-BrandedContentLines -Layout $Shell.Layout -Lines $Lines -ScrollOffset $scrollOffset
            & $footerRenderer
            Finalize-ToolkitShellBodyView -Shell $Shell
            continue
        }
        if (Test-ShellNavMarker $result) {
            return $result
        }
    }
}

function Invoke-ShellPage {
    param(
        [hashtable]$Shell,
        [string]$SectionTitle,
        [ValidateSet('ListWithToolbar', 'SystemToolbarOnly')]
        [string]$FooterTemplate = 'SystemToolbarOnly',
        [scriptblock]$RenderBody,
        [scriptblock]$RunInputLoop
    )

    Initialize-ToolkitShellBodyView -Shell $Shell -SectionTitle $SectionTitle `
        -FooterTemplate $FooterTemplate

    if ($RenderBody) {
        & $RenderBody
    }

    if ($RunInputLoop) {
        return (& $RunInputLoop)
    }
}

function Invoke-StandalonePage {
    param(
        [scriptblock]$RunPage
    )

    $shell = Initialize-ToolkitShell
    try {
        & $RunPage -Shell $shell
    }
    finally {
        Set-CursorVisible $true
    }
}
