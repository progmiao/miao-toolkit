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

    foreach ($rel in @(
            'ui\console\Console-Menu.ps1'
            'ui\shell\Nav.ps1'
            'ui\shell\SystemToolbar.ps1'
            'ui\shell\SingleSelectList.ps1'
            'ui\shell\MultiSelectList.ps1'
            'ui\shell\Draw.ps1'
            'ui\shell\Layout.ps1'
            'ui\shell\Header.ps1'
            'ui\shell\Title.ps1'
            'ui\shell\Exit.ps1'
            'ui\shell\Footer.ps1'
        )) {
        . (Join-Path $CoreLib $rel)
    }

    if (-not (Get-Command Draw-ToolkitDepOperationView -ErrorAction SilentlyContinue)) {
        . (Join-Path $CoreLib 'ui\shell\DepOperationView.ps1')
    }
    if (-not (Get-Command Initialize-ToolkitDepBatchOperationView -ErrorAction SilentlyContinue)) {
        . (Join-Path $CoreLib 'ui\shell\ToolkitDepBatchOperation.ps1')
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

function Invoke-ClaudeCodeNoticePage {
    param(
        [hashtable]$Shell,
        [string]$SectionTitle,
        [string]$Message,
        [string]$CacheKey = '',
        [System.ConsoleColor]$Color = [System.ConsoleColor]::Yellow
    )

    if (-not [string]::IsNullOrWhiteSpace($CacheKey)) {
        Clear-ShellSingleSelectListCache -Shell $Shell -CacheKey $CacheKey
    }

    $toolbar = New-ShellSystemToolbarConfig
    Initialize-ToolkitShellBodyView -Shell $Shell -SectionTitle $SectionTitle `
        -FooterTemplate SystemToolbarOnly
    Clear-ToolkitShellListViewport -Shell $Shell
    Set-ToolkitShellBodyCatalogLine -Shell $Shell -CatalogLine ''
    Render-ToolkitShellCatalogRow -Shell $Shell

    $messageRow = Get-ToolkitShellMessageRow -Shell $Shell
    if ($messageRow -ge 0) {
        if (-not [string]::IsNullOrWhiteSpace($Message)) {
            Write-FixedLine $messageRow " $Message" -Color $Color
        }
        else {
            Write-ToolkitShellMessageRow -Shell $Shell -Message ''
        }
    }

    $footerRenderer = New-ShellSystemToolbarFooterRenderer -Shell $Shell -ToolbarConfig $toolbar
    Register-ToolkitShellFooter -Shell $Shell -Renderer $footerRenderer
    & $footerRenderer
    Finalize-ToolkitShellBodyView -Shell $Shell

    while ($true) {
        $result = Read-ShellSystemToolbarKey -Shell $Shell -ToolbarConfig $toolbar
        if ($result -eq 'exitCancel' -or $result -eq 'exitConfirm') {
            continue
        }
        if ($result -eq 'exitConfirmed') {
            return (Get-ShellNavMarker -Action 'quit')
        }
        if (Test-ShellNavMarker $result) {
            return $result
        }
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
