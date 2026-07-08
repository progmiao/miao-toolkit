# claude-code — 插件列表异步加载（委托 core ToolkitShellListLoad）

function Import-ClaudePluginListLoadCore {
    param([string]$CoreLib)

    if (-not (Get-Command Invoke-ToolkitShellListLoad -ErrorAction SilentlyContinue)) {
        . (Join-Path $CoreLib 'ui\shell\ToolkitShellListLoad.ps1')
    }
}

function Start-ClaudePluginListFetch {
    param(
        [string]$LibPath,
        [string]$ToolRoot,
        [ValidateSet('install', 'installed', 'update')]
        [string]$LoadMode
    )

    $job = Start-Job -ArgumentList @($LibPath, $ToolRoot, $LoadMode) -ScriptBlock {
        param(
            [string]$Lib,
            [string]$Root,
            [string]$Mode
        )

        $ErrorActionPreference = 'Stop'
        . (Join-Path $Lib 'claude-code-state.ps1')
        . (Join-Path $Lib 'claude-code-presets.ps1')
        . (Join-Path $Lib 'claude-plugin.ps1')

        switch ($Mode) {
            'install' { return @(Get-ClaudePluginInstallMenuItems -ToolRoot $Root) }
            'installed' { return @(Get-ClaudePluginInstalledMenuItems) }
            'update' { return @(Get-ClaudePluginInstalledMenuItems -ForUpdate) }
        }
    }

    return @{ Job = $job }
}

function Invoke-ClaudePluginMenuItemsWithLoading {
    param(
        [hashtable]$Shell,
        [string]$ToolRoot,
        [string]$SectionTitle,
        [ValidateSet('install', 'installed', 'update')]
        [string]$LoadMode
    )

    $coreLib = Join-Path $ToolRoot '..\..\core\lib'
    Import-ClaudePluginListLoadCore -CoreLib $coreLib
    Import-ToolkitShellListLoadCore -CoreLib $coreLib

    $libPath = Join-Path $ToolRoot 'lib'
    $fetch = Start-ClaudePluginListFetch -LibPath $libPath -ToolRoot $ToolRoot -LoadMode $LoadMode
    $loadResult = Wait-ToolkitShellListLoad -Shell $Shell -SectionTitle $SectionTitle -Fetch $fetch
    if ($loadResult.Nav) {
        return $loadResult
    }

    $progress = if ($loadResult.Progress) {
        $loadResult.Progress
    }
    else {
        @{ Percent = 55; SpinnerIndex = 0 }
    }

    if ($loadResult.Error) {
        return @{
            Nav      = $null
            Items    = $null
            Error    = $loadResult.Error
            Progress = $progress
        }
    }

    Update-ToolkitShellListLoadingProgress -Shell $Shell -Progress $progress -TargetPercent 72

    return @{
        Nav      = $null
        Items    = @($loadResult.Data)
        Error    = $null
        Progress = $progress
    }
}
