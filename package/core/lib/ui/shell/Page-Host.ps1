# Shell 滚动内容页（help / update 等 DefaultBar 视图）

function Invoke-ToolkitShellContentView {
    param(
        [hashtable]$Shell,
        [string]$SectionTitle,
        [array]$Lines,
        [switch]$ShowSettings,
        [switch]$ShowBack
    )

    if ($null -eq $Lines) { $Lines = @() }

    Initialize-ToolkitShellBodyView -Shell $Shell -SectionTitle $SectionTitle `
        -FooterTemplate DefaultBar

    $scrollOffset = 0
    $viewport = $Shell.Layout.ListViewportHeight
    $scrollable = ($Lines.Count -gt $viewport)
    $maxScroll = [Math]::Max(0, $Lines.Count - $viewport)

    $writeFooter = Get-Item -Path function:Write-ToolkitShellFooter
    $footerRenderer = {
        param([hashtable]$FooterState = @{})

        & $writeFooter -Shell $Shell -Template DefaultBar `
            -ShowSettings:$ShowSettings -ShowBack:$ShowBack
    }.GetNewClosure()
    Register-ToolkitShellFooter -Shell $Shell -Renderer $footerRenderer

    Draw-BrandedContentLines -Layout $Shell.Layout -Lines $Lines -ScrollOffset $scrollOffset
    & $footerRenderer
    Finalize-ToolkitShellBodyView -Shell $Shell

    while ($true) {
        $result = Read-ToolkitShellDefaultBarKey -Shell $Shell -ShowSettings:$ShowSettings -ShowBack:$ShowBack `
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
        [ValidateSet('MenuSplit', 'DefaultBar')]
        [string]$FooterTemplate = 'DefaultBar',
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
