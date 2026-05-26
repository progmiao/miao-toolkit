# Shell 导航标记

function Get-ShellNavMarker {
    param([ValidateSet('back', 'quit', 'settings', 'help', 'update', 'lang', 'install')][string]$Action)

    return [pscustomobject]@{
        _kind  = 'shellNav'
        action = $Action
    }
}

function Test-ShellNavMarker {
    param(
        $Item,
        [string]$Action = ''
    )

    if (-not $Item -or $Item._kind -ne 'shellNav') { return $false }
    if ([string]::IsNullOrWhiteSpace($Action)) { return $true }
    return ($Item.action -eq $Action)
}
