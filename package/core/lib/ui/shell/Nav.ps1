# Shell 导航标记

function Get-ShellNavMarker {
    param([ValidateSet('back', 'quit', 'sys', 'help', 'update', 'lang', 'install', 'init', 'sysUninstall')][string]$Action)

    return [pscustomobject]@{
        _kind  = 'shellNav'
        action = $Action
    }
}

function Pop-ShellViewStack {
    param([System.Collections.Generic.List[string]]$ViewStack)

    if (-not $ViewStack -or $ViewStack.Count -le 0) { return $false }
    $ViewStack.RemoveAt($ViewStack.Count - 1)
    return $true
}

function Push-ShellViewStack {
    param(
        [System.Collections.Generic.List[string]]$ViewStack,
        [string]$View
    )

    if (-not $ViewStack -or [string]::IsNullOrWhiteSpace($View)) { return }
    if ($ViewStack.Count -gt 0 -and $ViewStack[$ViewStack.Count - 1] -eq $View) { return }
    $ViewStack.Add($View)
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

function Get-ShellInitialViewStack {
    param(
        [ValidateSet(
            'ToolList', 'Help', 'Sys', 'Lang', 'Update', 'Install', 'Tool',
            'ToolDep', 'Init', 'InitFromSys', 'ToolboxDepUpdate', 'ToolboxDepUninstall', 'SysUninstall'
        )]
        [string]$InitialView
    )

    switch ($InitialView) {
        'ToolList' { return @('ToolList') }
        'Sys' { return @('ToolList', 'Sys') }
        'Help' { return @('ToolList', 'Help') }
        'Lang' { return @('Lang') }
        'Update' { return @('Update') }
        'Install' { return @('Install') }
        'ToolboxDepUpdate' { return @('ToolboxDepUpdate') }
        'ToolboxDepUninstall' { return @('ToolboxDepUninstall') }
        'Tool' { return @('ToolList', 'Tool') }
        'ToolDep' { return @('ToolDep') }
        'Init' { return @('ToolList', 'Init') }
        'InitFromSys' { return @('ToolList', 'Init') }
        'SysUninstall' { return @('SysUninstall') }
        default { return @($InitialView) }
    }
}
