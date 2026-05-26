# Shell 会话：viewStack 路由 home / help / settings / lang / update

function Invoke-MiaoShellQuit {
    param([int]$ExitCode = 0)

    try { Set-CursorVisible $true } catch {}
    $script:ToolkitShell = $null
    Clear-Host
    return $ExitCode
}

function Start-ToolkitShellSession {
    param(
        [array]$Tools,
        [switch]$Preview,
        [ValidateSet('ToolList', 'Help', 'Settings', 'Lang', 'Update', 'Install')]
        [string]$InitialView = 'ToolList',
        [string[]]$FocusToolIds = @()
    )

    $shell = Initialize-ToolkitShell
    if ($FocusToolIds.Count -gt 0) {
        $shell['InstallFocusToolIds'] = @($FocusToolIds)
    }
    $viewStack = [System.Collections.Generic.List[string]]@($InitialView)
    $sessionExitCode = 0
    $quitSession = $false

    try {
        while ($viewStack.Count -gt 0 -and -not $quitSession) {
            $view = $viewStack[$viewStack.Count - 1]

            switch ($view) {
                'ToolList' {
                    $menuTools = Get-ToolkitMenuTools -RealTools $Tools
                    $picked = Invoke-HomePage -Tools $menuTools -Preview:$Preview -Shell $shell

                    if (Test-ShellNavMarker $picked 'quit') {
                        $sessionExitCode = Invoke-MiaoShellQuit
                        $quitSession = $true
                        break
                    }
                    if ($null -eq $picked) {
                        $sessionExitCode = Invoke-MiaoShellQuit
                        $quitSession = $true
                        break
                    }
                    if (Test-ShellNavMarker $picked 'settings') {
                        $shell.Layout['BodyDirty'] = $true
                        $viewStack.Add('Settings')
                        continue
                    }
                    if (Test-ShellNavMarker $picked 'help') {
                        $shell.Layout['BodyDirty'] = $true
                        $viewStack.Add('Help')
                        continue
                    }
                    if (Test-IsMockTool $picked) {
                        Write-FixedLine $shell.Layout.ListStartRow ' [预览] 模拟工具不可进入' -Color DarkGray
                        Start-Sleep -Milliseconds 800
                        Finalize-ToolkitShellBodyView -Shell $shell
                        continue
                    }

                    Set-CursorVisible $true
                    Clear-Host
                    $code = Invoke-Tool $picked -ToolArgs @() -Preview:$Preview
                    $next = Show-AfterToolPrompt
                    if ($next -eq 'exit') {
                        $sessionExitCode = Invoke-MiaoShellQuit -ExitCode $code
                        $quitSession = $true
                        break
                    }
                    $script:ToolkitShell = $null
                    $shell = Initialize-ToolkitShell -Force
                    $viewStack.Clear()
                    $viewStack.Add('ToolList')
                }
                'Help' {
                    $nav = Invoke-HelpPage -Shell $shell -Tools $Tools
                    if (Test-ShellNavMarker $nav 'back') {
                        $viewStack.RemoveAt($viewStack.Count - 1)
                        $shell.Layout['BodyDirty'] = $true
                        continue
                    }
                    if (Test-ShellNavMarker $nav 'quit') {
                        $sessionExitCode = Invoke-MiaoShellQuit
                        $quitSession = $true
                        break
                    }
                    if (Test-ShellNavMarker $nav 'settings') {
                        $shell.Layout['BodyDirty'] = $true
                        $viewStack.Add('Settings')
                        continue
                    }
                }
                'Settings' {
                    $nav = Invoke-SettingsPage -Shell $shell -Tools $Tools -Preview:$Preview
                    if (Test-ShellNavMarker $nav 'back') {
                        $viewStack.RemoveAt($viewStack.Count - 1)
                        $shell.Layout['BodyDirty'] = $true
                        continue
                    }
                    if (Test-ShellNavMarker $nav 'quit') {
                        $sessionExitCode = Invoke-MiaoShellQuit
                        $quitSession = $true
                        break
                    }
                    if (Test-ShellNavMarker $nav 'help') {
                        $shell.Layout['BodyDirty'] = $true
                        $viewStack.Add('Help')
                        continue
                    }
                    if (Test-ShellNavMarker $nav 'update') {
                        $shell.Layout['BodyDirty'] = $true
                        $viewStack.Add('Update')
                        continue
                    }
                    if (Test-ShellNavMarker $nav 'lang') {
                        $shell.Layout['BodyDirty'] = $true
                        $viewStack.Add('Lang')
                        continue
                    }
                    if (Test-ShellNavMarker $nav 'install') {
                        $shell.Layout['BodyDirty'] = $true
                        $viewStack.Add('Install')
                        continue
                    }
                }
                'Install' {
                    $focusIds = @()
                    if ($shell.InstallFocusToolIds) {
                        $focusIds = @($shell.InstallFocusToolIds)
                    }
                    $nav = Invoke-InstallDepsPage -Shell $shell -Tools $Tools -FocusToolIds $focusIds -Preview:$Preview
                    $shell.Remove('InstallFocusToolIds')
                    if (Test-ShellNavMarker $nav 'back') {
                        $viewStack.RemoveAt($viewStack.Count - 1)
                        $shell.Layout['BodyDirty'] = $true
                        continue
                    }
                    if (Test-ShellNavMarker $nav 'quit') {
                        $sessionExitCode = Invoke-MiaoShellQuit
                        $quitSession = $true
                        break
                    }
                }
                'Lang' {
                    $nav = Invoke-LangPage -Shell $shell
                    if (Test-ShellNavMarker $nav 'back') {
                        $viewStack.RemoveAt($viewStack.Count - 1)
                        $shell.Layout['BodyDirty'] = $true
                        continue
                    }
                    if (Test-ShellNavMarker $nav 'quit') {
                        $sessionExitCode = Invoke-MiaoShellQuit
                        $quitSession = $true
                        break
                    }
                    if (Test-ShellNavMarker $nav 'help') {
                        $shell.Layout['BodyDirty'] = $true
                        $viewStack.Add('Help')
                        continue
                    }
                }
                'Update' {
                    $nav = Invoke-UpdatePage -Shell $shell
                    if (Test-ShellNavMarker $nav 'back') {
                        if ($viewStack.Count -le 1) {
                            $sessionExitCode = Invoke-MiaoShellQuit
                            $quitSession = $true
                            break
                        }
                        $viewStack.RemoveAt($viewStack.Count - 1)
                        $shell.Layout['BodyDirty'] = $true
                        continue
                    }
                    if (Test-ShellNavMarker $nav 'quit') {
                        $sessionExitCode = Invoke-MiaoShellQuit
                        $quitSession = $true
                        break
                    }
                }
            }
        }
    }
    finally {
        Set-CursorVisible $true
    }

    return $sessionExitCode
}
