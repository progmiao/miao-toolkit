# Shell 会话：viewStack 路由 home / help / sys / lang / update / install / tool / init

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
        [ValidateSet(
            'ToolList', 'Help', 'Sys', 'Lang', 'Update', 'Install', 'Tool',
            'ToolDep', 'Init', 'InitFromSys', 'ToolboxDepUpdate', 'ToolboxDepUninstall', 'SysUninstall'
        )]
        [string]$InitialView = 'ToolList',
        [string[]]$FocusToolIds = @(),
        $CurrentTool = $null,
        [string]$CurrentToolId = '',
        [ValidateSet('install', 'update', 'uninstall')]
        [string]$ToolDepIntent = 'install',
        [switch]$ToolboxDepSelectAll
    )

    $null = Sync-ToolkitSessionInitState -Refresh
    $shell = Initialize-ToolkitShell -Force
    if ($FocusToolIds.Count -gt 0) {
        $shell['InstallFocusToolIds'] = @($FocusToolIds)
    }
    if ($ToolboxDepSelectAll) {
        $shell['ToolboxDepSelectAll'] = $true
    }
    if ($InitialView -eq 'Tool' -or $InitialView -eq 'ToolDep') {
        $entryTool = $CurrentTool
        if (-not $entryTool -and -not [string]::IsNullOrWhiteSpace($CurrentToolId)) {
            $entryTool = Get-Tool $CurrentToolId -Tools $Tools
        }
        if ($entryTool) {
            $shell['CurrentTool'] = $entryTool
        }
    }
    if ($InitialView -eq 'ToolDep') {
        $shell['ToolDepIntent'] = $ToolDepIntent
    }

    $null = Sync-ToolkitSessionInitState -Shell $shell
    $viewStack = [System.Collections.Generic.List[string]]@(Get-ShellInitialViewStack -InitialView $InitialView)
    $sessionExitCode = 0
    $quitSession = $false

    try {
        while ($viewStack.Count -gt 0 -and -not $quitSession) {
            $view = $viewStack[$viewStack.Count - 1]
            Ensure-MiaoShellViewModule -View $view

            switch ($view) {
                'ToolList' {
                    if (-not $shell.InitReady) {
                        $shell.Layout['BodyDirty'] = $true
                        Import-MiaoModule -Name Init
                        Push-ShellViewStack -ViewStack $viewStack -View 'Init'
                        continue
                    }

                    $menuTools = Get-ToolkitMenuTools -RealTools $Tools
                    $picked = Invoke-HomePage -Tools $menuTools -Shell $shell

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
                    if (Test-ShellNavMarker $picked 'sys') {
                        $shell.Layout['BodyDirty'] = $true
                        $viewStack.Add('Sys')
                        continue
                    }
                    if (Test-ShellNavMarker $picked 'help') {
                        $shell.Layout['BodyDirty'] = $true
                        $viewStack.Add('Help')
                        continue
                    }
                    if (Test-IsMockTool $picked) {
                        Write-FixedLine $shell.Layout.ListStartRow `
                            " $(Get-I18n -Key 'message.mockToolNoEntry')" -Color DarkGray
                        Start-Sleep -Milliseconds 800
                        Finalize-ToolkitShellBodyView -Shell $shell
                        continue
                    }

                    $shell['CurrentTool'] = $picked
                    $shell.Layout['BodyDirty'] = $true
                    $viewStack.Add('Tool')
                }
                'Tool' {
                    $tool = $shell.CurrentTool
                    if (-not $tool) {
                        Write-Host (Get-I18n -Key 'message.unknownCommand' -Vars @{ command = $CurrentToolId }) -ForegroundColor Red
                        Pop-ShellViewStack -ViewStack $viewStack | Out-Null
                        $shell.Layout['BodyDirty'] = $true
                        continue
                    }
                    Import-MiaoModule -Name Tool
                    $nav = Invoke-Tool -Tool $tool -ToolkitShell $shell

                    if (Test-ShellNavMarker $nav 'back') {
                        $shell.Remove('CurrentTool')
                        Pop-ShellViewStack -ViewStack $viewStack | Out-Null
                        $shell.Layout['BodyDirty'] = $true
                        continue
                    }
                    if (Test-ShellNavMarker $nav 'quit') {
                        $sessionExitCode = Invoke-MiaoShellQuit
                        $quitSession = $true
                        break
                    }
                    if (Test-ShellNavMarker $nav 'sys') {
                        $shell.Layout['BodyDirty'] = $true
                        $viewStack.Add('Sys')
                        continue
                    }
                    if (Test-ShellNavMarker $nav 'help') {
                        $shell.Layout['BodyDirty'] = $true
                        $viewStack.Add('Help')
                        continue
                    }

                    $shell.Remove('CurrentTool')
                    Pop-ShellViewStack -ViewStack $viewStack | Out-Null
                    $shell.Layout['BodyDirty'] = $true
                }
                'ToolDep' {
                    $tool = $shell.CurrentTool
                    if (-not $tool) {
                        $sessionExitCode = 1
                        $quitSession = $true
                        break
                    }
                    Import-MiaoModule -Name ToolDeps
                    $intent = if ($shell.ToolDepIntent) { [string]$shell.ToolDepIntent } else { 'install' }
                    $result = Start-ToolkitDepOperation -Tool $tool -Intent $intent -Shell $shell
                    $shell.Remove('ToolDepIntent')
                    $shell.Remove('CurrentTool')

                    if (Test-ShellNavMarker $result 'quit') {
                        $sessionExitCode = Invoke-MiaoShellQuit
                        $quitSession = $true
                        break
                    }

                    $sessionExitCode = $(if ($result) { 0 } else { 1 })
                    $quitSession = $true
                }
                'Help' {
                    $nav = Invoke-HelpPage -Shell $shell -Tools $Tools
                    if (Test-ShellNavMarker $nav 'back') {
                        Pop-ShellViewStack -ViewStack $viewStack | Out-Null
                        $shell.Layout['BodyDirty'] = $true
                        continue
                    }
                    if (Test-ShellNavMarker $nav 'quit') {
                        $sessionExitCode = Invoke-MiaoShellQuit
                        $quitSession = $true
                        break
                    }
                    if (Test-ShellNavMarker $nav 'sys') {
                        $shell.Layout['BodyDirty'] = $true
                        $viewStack.Add('Sys')
                        continue
                    }
                }
                'Sys' {
                    $nav = Invoke-SysPage -Shell $shell -Tools $Tools
                    if (Test-ShellNavMarker $nav 'back') {
                        Pop-ShellViewStack -ViewStack $viewStack | Out-Null
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
                    if (Test-ShellNavMarker $nav 'init') {
                        $shell.Layout['BodyDirty'] = $true
                        Push-ShellViewStack -ViewStack $viewStack -View 'Init'
                        continue
                    }
                    if (Test-ShellNavMarker $nav 'sysUninstall') {
                        $shell.Layout['BodyDirty'] = $true
                        $viewStack.Add('SysUninstall')
                        continue
                    }
                }
                'Install' {
                    $focusIds = @()
                    if ($shell.InstallFocusToolIds) {
                        $focusIds = @($shell.InstallFocusToolIds)
                    }
                    $selectAll = [bool]$shell.ToolboxDepSelectAll
                    $nav = Invoke-InstallPage -Shell $shell -Tools $Tools -FocusToolIds $focusIds `
                        -SelectAll:$selectAll
                    $shell.Remove('InstallFocusToolIds')
                    $shell.Remove('ToolboxDepSelectAll')
                    if (Test-ShellNavMarker $nav 'back') {
                        if ($viewStack.Count -le 1) {
                            $sessionExitCode = 0
                            $quitSession = $true
                            break
                        }
                        Pop-ShellViewStack -ViewStack $viewStack | Out-Null
                        $shell.Layout['BodyDirty'] = $true
                        continue
                    }
                    if (Test-ShellNavMarker $nav 'quit') {
                        $sessionExitCode = Invoke-MiaoShellQuit
                        $quitSession = $true
                        break
                    }
                    $sessionExitCode = 0
                    $quitSession = $true
                }
                'ToolboxDepUpdate' {
                    $selectAll = [bool]$shell.ToolboxDepSelectAll
                    $nav = Invoke-ToolboxDepUpdatePage -Shell $shell -Tools $Tools -SelectAll:$selectAll
                    $shell.Remove('ToolboxDepSelectAll')
                    if (Test-ShellNavMarker $nav 'back') {
                        $sessionExitCode = 0
                        $quitSession = $true
                        break
                    }
                    if (Test-ShellNavMarker $nav 'quit') {
                        $sessionExitCode = Invoke-MiaoShellQuit
                        $quitSession = $true
                        break
                    }
                }
                'ToolboxDepUninstall' {
                    $selectAll = [bool]$shell.ToolboxDepSelectAll
                    $nav = Invoke-ToolboxDepUninstallPage -Shell $shell -Tools $Tools -SelectAll:$selectAll
                    $shell.Remove('ToolboxDepSelectAll')
                    if (Test-ShellNavMarker $nav 'back') {
                        $sessionExitCode = 0
                        $quitSession = $true
                        break
                    }
                    if (Test-ShellNavMarker $nav 'quit') {
                        $sessionExitCode = Invoke-MiaoShellQuit
                        $quitSession = $true
                        break
                    }
                }
                'Init' {
                    $nav = Invoke-ShellInitView -Shell $shell
                    if (Test-ShellNavMarker $nav 'back') {
                        $null = Sync-ToolkitSessionInitState -Shell $shell -Refresh
                        Pop-ShellViewStack -ViewStack $viewStack | Out-Null
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
                        if ($viewStack.Count -le 1) {
                            $sessionExitCode = 0
                            $quitSession = $true
                            break
                        }
                        Pop-ShellViewStack -ViewStack $viewStack | Out-Null
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
                            $sessionExitCode = 0
                            $quitSession = $true
                            break
                        }
                        Pop-ShellViewStack -ViewStack $viewStack | Out-Null
                        $shell.Layout['BodyDirty'] = $true
                        continue
                    }
                    if (Test-ShellNavMarker $nav 'quit') {
                        $sessionExitCode = Invoke-MiaoShellQuit
                        $quitSession = $true
                        break
                    }
                }
                'SysUninstall' {
                    $nav = Invoke-ToolkitSysUninstall -Shell $shell
                    if (Test-ShellNavMarker $nav 'back') {
                        Pop-ShellViewStack -ViewStack $viewStack | Out-Null
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
