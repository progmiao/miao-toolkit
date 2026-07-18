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
        Segments   = $segments
        LetterKeys = $letterKeys
        AllowBack  = (-not $HideBack)
    }
}

function Set-ToolkitShellToolbarLocked {
    param(
        [hashtable]$Shell,
        [bool]$Locked = $true
    )

    if (-not $Shell) { return }
    $Shell['ToolbarLocked'] = $Locked
}

function Test-ToolkitShellToolbarLocked {
    param([hashtable]$Shell)

    return ($Shell -and $Shell.ContainsKey('ToolbarLocked') -and [bool]$Shell['ToolbarLocked'])
}

function Get-ShellSystemToolbarBarColor {
    param([hashtable]$Shell)

    if (Test-ToolkitShellToolbarLocked -Shell $Shell) {
        return [System.ConsoleColor]::DarkGray
    }
    return [System.ConsoleColor]::Gray
}

function Drain-ShellLockedToolbarKeys {
    param(
        [hashtable]$Shell,
        [switch]$AllowLogScroll,
        [int]$MaxEvents = 16
    )

    if (-not (Test-ToolkitShellToolbarLocked -Shell $Shell)) { return }

    $fnTestKey = Get-Command Test-ConsoleKeyAvailable -CommandType Function -ErrorAction SilentlyContinue
    $fnPeek = Get-Command Get-ConsoleVirtualKeyPeek -CommandType Function -ErrorAction SilentlyContinue
    $fnRead = Get-Command Read-ConsoleVirtualKeyConsume -CommandType Function -ErrorAction SilentlyContinue
    if (-not $fnTestKey -or -not $fnPeek -or -not $fnRead) { return }

    $drained = 0
    while ($drained -lt $MaxEvents -and (& $fnTestKey)) {
        $peek = & $fnPeek
        if (-not $peek) { break }
        if ($AllowLogScroll -and $peek -in @('UpArrow', 'DownArrow')) { break }
        $null = & $fnRead
        $drained++
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

    if (Test-ToolkitShellToolbarLocked -Shell $Shell) {
        Drain-ShellLockedToolbarKeys -Shell $Shell
        return $null
    }

    Prepare-ToolkitShellBodyDraw -Shell $Shell
    $key = [Console]::ReadKey($true)
    Set-CursorVisible $false

    if ($key.Key -eq 'Escape') {
        Request-ShellExit -Shell $Shell
        return 'exitConfirm'
    }

    if ($key.KeyChar -match '^[qQ]$' -and $ToolbarConfig.AllowBack) {
        return (Get-ShellNavMarker -Action 'back')
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
