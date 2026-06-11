# 系统工具栏：退出 / 返回 / 系统 / 帮助（底栏第二行或内容页单行）

function Format-ShellSystemToolbarBarSegments {
    param(
        [string[]]$Segments,
        [int]$ColumnCount = 5
    )

    if ($null -eq $Segments) { $Segments = @() }

    # 隐藏项不占位：可见项左对齐，右侧补空列
    $visible = @($Segments | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    while ($visible.Count -lt $ColumnCount) {
        $visible += ''
    }
    if ($visible.Count -gt $ColumnCount) {
        $visible = @($visible[0..($ColumnCount - 1)])
    }

    return $visible
}

function New-ShellSystemToolbarConfig {
    param(
        [switch]$HideBack,
        [switch]$HideSystem,
        [switch]$HideHelp
    )

    $keys = Get-MiaoI18nKeys
    $segments = @(
        (Get-I18nKeyHint -Key $keys.Esc -LabelKey 'common.quit')
    )
    if (-not $HideBack) {
        $segments += (Get-I18nKeyHint -Key $keys.Q -LabelKey 'common.back')
    }
    if (-not $HideSystem) {
        $segments += (Get-I18nKeyHint -Key 'S' -LabelKey 'common.system')
    }
    if (-not $HideHelp) {
        $segments += (Get-I18nKeyHint -Key 'H' -LabelKey 'common.help')
    }

    $segments = @(Format-ShellSystemToolbarBarSegments -Segments $segments)

    $letterKeys = @{}
    if (-not $HideSystem) {
        $letterKeys['s'] = Get-ShellNavMarker -Action 'sys'
    }
    if (-not $HideHelp) {
        $letterKeys['h'] = Get-ShellNavMarker -Action 'help'
    }

    return @{
        Segments     = $segments
        LetterKeys   = $letterKeys
        EscMeansBack = (-not $HideBack)
    }
}

function Read-ShellSystemToolbarKey {
    param(
        [hashtable]$Shell,
        [hashtable]$ToolbarConfig,
        [switch]$Scrollable,
        [ref]$ScrollOffset,
        [int]$MaxScroll,
        [switch]$AllowEnter
    )

    if (-not $ToolbarConfig) {
        $ToolbarConfig = New-ShellSystemToolbarConfig
    }

    $confirm = Read-ShellExitIfActive -Shell $Shell
    if ($null -ne $confirm) {
        return $confirm
    }

    Prepare-ToolkitShellBodyDraw -Shell $Shell
    $key = [Console]::ReadKey($true)

    if ($key.Key -eq 'Escape') {
        if ($ToolbarConfig.EscMeansBack) {
            return (Get-ShellNavMarker -Action 'back')
        }
        return (Get-ShellNavMarker -Action 'quit')
    }

    if ($key.KeyChar) {
        $ch = [string]$key.KeyChar
        if ($ToolbarConfig.LetterKeys -and $ToolbarConfig.LetterKeys.ContainsKey($ch.ToLowerInvariant())) {
            return $ToolbarConfig.LetterKeys[$ch.ToLowerInvariant()]
        }
    }

    if ($Scrollable -and $ScrollOffset) {
        if ($key.Key -eq 'UpArrow') {
            if ($ScrollOffset.Value -gt 0) { $ScrollOffset.Value-- }
            return 'scroll'
        }
        if ($key.Key -eq 'DownArrow') {
            if ($ScrollOffset.Value -lt $MaxScroll) { $ScrollOffset.Value++ }
            return 'scroll'
        }
    }

    if ($AllowEnter -and $key.Key -eq 'Enter') {
        return 'enter'
    }

    return $null
}
