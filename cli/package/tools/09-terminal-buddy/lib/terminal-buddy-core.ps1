# terminal-buddy — 共享 Shell 导入、i18n、常量

$script:TerminalBuddyGiteeOwner = 'updateme'
$script:TerminalBuddyGiteeRepo = 'terminal-buddy'
$script:TerminalBuddyAssetName = 'terminal-buddy.exe'
$script:TerminalBuddyInstallDirName = 'terminal-buddy'
$script:TerminalBuddyMarkerFile = '.miao-toolkit-installed'
$script:TerminalBuddyDownloadTimeoutSec = 1800
$script:TerminalBuddyReleaseApiTimeoutSec = 30

function Get-TerminalBuddyKnownPaths {
    $installDir = Join-Path $env:LOCALAPPDATA (Join-Path 'Programs' $script:TerminalBuddyInstallDirName)
    $exePath = Join-Path $installDir $script:TerminalBuddyAssetName
    $markerPath = Join-Path $installDir $script:TerminalBuddyMarkerFile
    $shortcutPath = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\TerminalBuddy.lnk'
    $desktopShortcutPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'TerminalBuddy.lnk'
    $dataDir = Join-Path $env:APPDATA 'TerminalBuddy'

    return @{
        InstallDir          = $installDir
        ExePath             = $exePath
        MarkerPath          = $markerPath
        ShortcutPath        = $shortcutPath
        DesktopShortcutPath = $desktopShortcutPath
        DataDir             = $dataDir
    }
}

function Import-TerminalBuddyShellCore {
    param([string]$CoreLib)

    if (-not (Get-Command Initialize-PathsFromToolRoot -ErrorAction SilentlyContinue)) {
        . (Join-Path $CoreLib 'config\Paths.ps1')
        . (Join-Path $CoreLib 'config\ListLayout.ps1')
        . (Join-Path $CoreLib 'config\UserConfig.ps1')
        . (Join-Path $CoreLib 'config\I18n.ps1')
    }
    elseif (-not (Get-Command Resolve-ShellListPageSize -ErrorAction SilentlyContinue)) {
        . (Join-Path $CoreLib 'config\Paths.ps1')
    }

    foreach ($rel in @(
            'ui\console\Console-Menu.ps1'
            'ui\shell\Nav.ps1'
            'ui\shell\SystemToolbar.ps1'
            'ui\shell\SingleSelectList.ps1'
            'ui\shell\MultiSelectList.ps1'
            'ui\shell\ShellListModel.ps1'
            'ui\shell\ShellListLayout.ps1'
            'ui\shell\ToolkitShellList.ps1'
            'ui\shell\Draw.ps1'
            'ui\shell\Layout.ps1'
            'ui\shell\Header.ps1'
            'ui\shell\Title.ps1'
            'ui\shell\Exit.ps1'
            'ui\shell\Footer.ps1'
        )) {
        . (Join-Path $CoreLib $rel)
    }

    foreach ($rel in @(
            'ui\shell\ShellListSearch.ps1'
            'ui\shell\ToolkitShellListLoad.ps1'
        )) {
        . (Join-Path $CoreLib $rel)
    }

    if (-not (Get-Command Initialize-ToolkitDepBatchOperationView -ErrorAction SilentlyContinue)) {
        Import-TerminalBuddyDepProgressCore -CoreLib $CoreLib
    }
}

function Get-TerminalBuddyI18n {
    param(
        [string]$ToolRoot,
        [string]$Key,
        [hashtable]$Vars = @{}
    )

    return Get-ToolI18n -ToolRoot $ToolRoot -Key $Key -Vars $Vars
}

function Initialize-TerminalBuddyActionPage {
    param(
        [string]$ToolRoot,
        [hashtable]$ToolkitShell = $null,
        [int]$PageSize = 0,
        [int]$ViewHeight = 0
    )

    $coreLib = (Resolve-Path -LiteralPath (Join-Path $ToolRoot '..\..\core\lib')).Path
    Import-TerminalBuddyShellCore -CoreLib $coreLib
    Initialize-PathsFromToolRoot -ToolRoot $ToolRoot

    $paging = Resolve-MenuPagingDefaults -PageSize $PageSize -ViewHeight $ViewHeight
    $standaloneShell = $false
    if (-not $ToolkitShell) {
        $ToolkitShell = Initialize-ToolkitShell
        $standaloneShell = $true
    }

    Sync-MiaoLocaleFromShell -Shell $ToolkitShell

    return [pscustomobject]@{
        ToolRoot        = $ToolRoot
        CoreLib         = $coreLib
        Shell           = $ToolkitShell
        PageSize        = $paging.PageSize
        ViewHeight      = $paging.ViewHeight
        StandaloneShell = $standaloneShell
    }
}

function Invoke-TerminalBuddyNoticePage {
    param(
        [hashtable]$Shell,
        [string]$SectionTitle,
        [string]$Message,
        [string]$CacheKey = ''
    )

    $cacheKey = if ([string]::IsNullOrWhiteSpace($CacheKey)) { 'TerminalBuddyNotice' } else { $CacheKey }
    Clear-ShellListCache -Shell $Shell -CacheKey $cacheKey

    return Invoke-ToolkitShellList @{
        Mode             = 'Single'
        Shell            = $Shell
        SectionTitle     = $SectionTitle
        Rows             = @()
        CacheKey         = $cacheKey
        Toolbar          = (New-ShellSystemToolbarConfig)
        EmptyListMessage = $Message
    }
}

function Invoke-TerminalBuddyRequiredNoticePage {
    param(
        [hashtable]$Shell,
        [string]$SectionTitle,
        [string]$ToolRoot,
        [string]$CacheKey
    )

    if (Test-TerminalBuddyInstalled) {
        return $null
    }

    return Invoke-TerminalBuddyNoticePage -Shell $Shell -SectionTitle $SectionTitle `
        -Message (Get-TerminalBuddyI18n -ToolRoot $ToolRoot -Key 'terminal-buddy.app.notInstalled') `
        -CacheKey $CacheKey
}

function Import-TerminalBuddyDepProgressCore {
    param([string]$CoreLib)

    if (Get-Command Initialize-ToolkitDepBatchOperationView -ErrorAction SilentlyContinue) {
        return
    }

    $resolvedCore = if (Test-Path -LiteralPath $CoreLib) {
        (Resolve-Path -LiteralPath $CoreLib).Path
    }
    else {
        [string]$CoreLib
    }

    $batchPath = Join-Path $resolvedCore 'ui\shell\BatchExecution.ps1'
    if (Test-Path -LiteralPath $batchPath) {
        . $batchPath
    }

    if (-not (Get-Command Initialize-ToolkitDepBatchOperationView -ErrorAction SilentlyContinue)) {
        $depBatchPath = Join-Path $resolvedCore 'ui\shell\ToolkitDepBatchOperation.ps1'
        if (Test-Path -LiteralPath $depBatchPath) {
            . $depBatchPath
        }
    }
}

function Write-TerminalBuddyBatchLogLine {
    param(
        $Log,
        [string]$Text,
        [string]$Kind = 'text',
        [switch]$WithTimestamp
    )

    if ($null -eq $Log -or $null -eq $Log.Lines) { return }

    $lineColor = [System.ConsoleColor]::Gray
    switch ($Kind) {
        'section' { $lineColor = [System.ConsoleColor]::Cyan }
        'success' { $lineColor = [System.ConsoleColor]::Green }
        'error' { $lineColor = [System.ConsoleColor]::Red }
        'heading' { $lineColor = [System.ConsoleColor]::White }
    }

    $timestamp = if ($WithTimestamp) { (Get-Date).ToString('HH:mm:ss') } else { '' }
    $Log.Lines.Add([pscustomobject]@{
        Timestamp = $timestamp
        Text      = [string]$Text
        Kind      = $Kind
        Color     = $lineColor
    }) | Out-Null

    while ($Log.Lines.Count -gt 500) {
        $Log.Lines.RemoveAt(0)
    }
}

function Get-TerminalBuddyGiteeConfig {
    param([string]$ToolRoot)

    $configPath = Join-Path $ToolRoot 'index.json'
    $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $config.gitee) {
        throw "gitee config missing in $configPath"
    }

    return $config.gitee
}
