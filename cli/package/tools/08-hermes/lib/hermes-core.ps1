# hermes — 共享 Shell 导入、i18n、通知页

$script:HermesInstallScriptUrl = 'https://hermes-agent.nousresearch.com/install.ps1'
$script:HermesWingetDesktopPackageId = 'fathah.HermesDesktop'
$script:HermesInstallProcessExitWaitMs = 7200000
$script:HermesUpdateProcessExitWaitMs = 7200000
$script:HermesUpdateCheckTimeoutMs = 60000
$script:HermesUninstallTimeoutMs = 120000
$script:HermesUpdateNetworkPreflightSec = 5

function Get-HermesKnownPaths {
    $hermesHome = Join-Path $env:LOCALAPPDATA 'hermes'
    return @{
        HermesHome     = $hermesHome
        HermesAgentDir = Join-Path $hermesHome 'hermes-agent'
        HermesExe      = Join-Path $hermesHome 'hermes-agent\venv\Scripts\hermes.exe'
        HermesCmdShim  = Join-Path $hermesHome 'bin\hermes.cmd'
    }
}

function Import-HermesShellCore {
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
        Import-HermesDepProgressCore -CoreLib $CoreLib
    }
}

function Get-HermesI18n {
    param(
        [string]$ToolRoot,
        [string]$Key,
        [hashtable]$Vars = @{}
    )

    return Get-ToolI18n -ToolRoot $ToolRoot -Key $Key -Vars $Vars
}

function Initialize-HermesActionPage {
    param(
        [string]$ToolRoot,
        [hashtable]$ToolkitShell = $null,
        [int]$PageSize = 0,
        [int]$ViewHeight = 0
    )

    $coreLib = (Resolve-Path -LiteralPath (Join-Path $ToolRoot '..\..\core\lib')).Path
    Import-HermesShellCore -CoreLib $coreLib
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

function Invoke-HermesNoticePage {
    param(
        [hashtable]$Shell,
        [string]$SectionTitle,
        [string]$Message,
        [string]$CacheKey = ''
    )

    $cacheKey = if ([string]::IsNullOrWhiteSpace($CacheKey)) { 'HermesNotice' } else { $CacheKey }
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

function Invoke-HermesCliRequiredNoticePage {
    param(
        [hashtable]$Shell,
        [string]$SectionTitle,
        [string]$ToolRoot,
        [string]$CacheKey
    )

    if (Test-HermesInstalled) {
        return $null
    }

    return Invoke-HermesNoticePage -Shell $Shell -SectionTitle $SectionTitle `
        -Message (Get-HermesI18n -ToolRoot $ToolRoot -Key 'hermes.cli.notInstalled') `
        -CacheKey $CacheKey
}

function Import-HermesDepProgressCore {
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

    $importBlock = {
        param([string]$Root)

        if (Get-Command Initialize-ToolkitDepBatchOperationView -ErrorAction SilentlyContinue) {
            return
        }

        $batchPath = Join-Path $Root 'ui\shell\BatchExecution.ps1'
        if (Test-Path -LiteralPath $batchPath) {
            . $batchPath
        }

        if (-not (Get-Command Initialize-ToolkitDepBatchOperationView -ErrorAction SilentlyContinue)) {
            $depBatchPath = Join-Path $Root 'ui\shell\ToolkitDepBatchOperation.ps1'
            if (Test-Path -LiteralPath $depBatchPath) {
                . $depBatchPath
            }
        }
    }

    $stack = @(Get-PSCallStack)
    if ($stack.Count -gt 1 -and $null -ne $stack[1].InvocationInfo) {
        $callerState = $stack[1].InvocationInfo.MyCommand.SessionState
        if ($null -ne $callerState) {
            $null = $callerState.InvokeScript($importBlock, $resolvedCore)
            return
        }
    }

    & $importBlock $resolvedCore
}
