# claude-code — 共享 Shell 导入、i18n、通知页

$script:ClaudeCodeWingetPackageId = 'Anthropic.ClaudeCode'

function Import-ClaudeCodeShellCore {
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

    if (-not (Get-Command Initialize-ToolkitBatchExecutionView -ErrorAction SilentlyContinue)) {
        Import-ClaudeCodeDepProgressCore -CoreLib $CoreLib
    }
}

function Get-ClaudeCodeI18n {
    param(
        [string]$ToolRoot,
        [string]$Key,
        [hashtable]$Vars = @{}
    )

    return Get-ToolI18n -ToolRoot $ToolRoot -Key $Key -Vars $Vars
}

function Initialize-ClaudeCodeActionPage {
    param(
        [string]$ToolRoot,
        [hashtable]$ToolkitShell = $null,
        [int]$PageSize = 0,
        [int]$ViewHeight = 0
    )

    $coreLib = Join-Path $ToolRoot '..\..\core\lib'
    Import-ClaudeCodeShellCore -CoreLib $coreLib
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

function Invoke-ClaudeCodeCliRequiredNoticePage {
    param(
        [hashtable]$Shell,
        [string]$SectionTitle,
        [string]$ToolRoot,
        [string]$CacheKey
    )

    if (Test-ClaudeCodeCliAvailable) {
        return $null
    }

    return Invoke-ClaudeCodeNoticePage -Shell $Shell -SectionTitle $SectionTitle `
        -Message (Get-ClaudeCodeI18n -ToolRoot $ToolRoot -Key 'claude-code.cli.notInstalled') `
        -CacheKey $CacheKey
}

function Invoke-ClaudeCodeNoticePage {
    param(
        [hashtable]$Shell,
        [string]$SectionTitle,
        [string]$Message,
        [string]$CacheKey = ''
    )

    $cacheKey = if ([string]::IsNullOrWhiteSpace($CacheKey)) { 'ClaudeCodeNotice' } else { $CacheKey }
    Clear-ShellListCache -Shell $Shell -CacheKey $cacheKey

    return Invoke-ToolkitShellList @{
        Mode              = 'Single'
        Shell             = $Shell
        SectionTitle      = $SectionTitle
        Rows              = @()
        CacheKey          = $cacheKey
        Toolbar           = (New-ShellSystemToolbarConfig)
        EmptyListMessage  = $Message
    }
}

function Read-ClaudeCodeShellLineInput {
    param(
        [string]$Prompt,
        [switch]$Secret
    )

    try { Set-CursorVisible $true } catch {}

    if ($Secret) {
        $secure = Read-Host $Prompt -AsSecureString
        $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try {
            return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
        }
        finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
        }
    }

    return [string](Read-Host $Prompt)
}

function Invoke-ClaudeCodeShellLineInput {
    param(
        [hashtable]$Shell,
        [string[]]$Prompts,
        [switch[]]$SecretFlags = @()
    )

    Clear-Host
    try { Set-CursorVisible $true } catch {}

    $values = @()
    for ($i = 0; $i -lt $Prompts.Count; $i++) {
        $isSecret = ($i -lt $SecretFlags.Count) -and $SecretFlags[$i].IsPresent
        $values += (Read-ClaudeCodeShellLineInput -Prompt $Prompts[$i] -Secret:$isSecret)
    }

    try { Set-CursorVisible $false } catch {}
    $null = Ensure-ToolkitShellLayoutBrandInnerWidth -Shell $Shell
    return @($values)
}
