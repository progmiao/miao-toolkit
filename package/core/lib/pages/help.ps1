# 帮助页

function New-HelpMenuEntry {
    return [pscustomobject]@{
        _kind = 'help'
        id    = 'help'
    }
}

function Test-IsHelpMenuEntry {
    param($Item)

    return ($Item -and $Item._kind -eq 'help')
}

function New-BrandedHelpLine {
    param(
        [string]$Text,
        [string]$Kind = 'text',
        [System.ConsoleColor]$Color = [System.ConsoleColor]::Gray
    )

    return New-BrandedContentLine -Text $Text -Kind $Kind -Color $Color
}

function Get-ToolkitHelpLines {
    param([array]$Tools)

    $lines = @(
        (New-BrandedHelpLine -Text (Get-I18n -Key 'page.help.commandsTitle') -Kind 'heading' -Color ([System.ConsoleColor]::White))
        (New-BrandedHelpLine -Text "  miao                 $(Get-I18n -Key 'common.cmd.menu')")
        (New-BrandedHelpLine -Text "  miao list            $(Get-I18n -Key 'common.cmd.list')")
        (New-BrandedHelpLine -Text "  miao version         $(Get-I18n -Key 'common.cmd.version')")
        (New-BrandedHelpLine -Text "  miao help [tool]     $(Get-I18n -Key 'common.cmd.help')")
        (New-BrandedHelpLine -Text "  miao install         $(Get-I18n -Key 'common.cmd.install')")
        (New-BrandedHelpLine -Text "  miao install <tool>  $(Get-I18n -Key 'common.cmd.installTool')")
        (New-BrandedHelpLine -Text "  miao uninstall <tool> $(Get-I18n -Key 'common.cmd.uninstallTool')")
        (New-BrandedHelpLine -Text "  miao update          $(Get-I18n -Key 'common.cmd.update')")
        (New-BrandedHelpLine -Text "  miao lang            $(Get-I18n -Key 'common.cmd.lang')")
        (New-BrandedHelpLine -Text "  miao settings        $(Get-I18n -Key 'common.cmd.settings')")
        (New-BrandedHelpLine -Text "  miao <tool> [args]   $(Get-I18n -Key 'common.cmd.tool')")
        (New-BrandedHelpLine -Text '' )
        (New-BrandedHelpLine -Text (Get-I18n -Key 'page.help.toolsTitle') -Kind 'heading' -Color ([System.ConsoleColor]::White))
    )

    foreach ($t in $Tools) {
        $name = if ($t.displayName) { $t.displayName } else { $t.id }
        $lines += New-BrandedHelpLine -Text "  miao $($t.id)    $name"
        if ($t.summary) {
            $lines += New-BrandedHelpLine -Text "               $($t.summary)" -Color ([System.ConsoleColor]::DarkGray)
        }
    }

    return $lines
}

function Show-ToolkitHelpPage {
    param(
        [array]$Tools,
        [hashtable]$LetterKeys = @{}
    )

    if ($LetterKeys.Count -eq 0) {
        $LetterKeys = @{ s = (New-SettingsMenuEntry) }
    }

    $lines = Get-ToolkitHelpLines -Tools $Tools
    return Show-BrandedContentPage -SectionTitle (Get-I18n -Key 'page.help.pageTitle') `
        -Lines $lines -LetterKeys $LetterKeys
}

function Invoke-HelpPage {
    param(
        [hashtable]$Shell,
        [array]$Tools
    )

    return Invoke-ToolkitShellContentView -Shell $Shell `
        -SectionTitle (Get-I18n -Key 'page.help.pageTitle') `
        -Lines (Get-ToolkitHelpLines -Tools $Tools) `
        -ShowSettings -ShowBack
}

function Invoke-ShellHelpView {
    param(
        [hashtable]$Shell,
        [array]$Tools
    )

    return Invoke-HelpPage -Shell $Shell -Tools $Tools
}

function Show-ToolkitHelp {
    param([array]$Tools)

    return (Start-ToolkitShellSession -Tools $Tools -InitialView Help)
}

function Show-ToolHelp {
    param($Tool)

    $helpPath = Join-Path $Tool._root $Tool.help
    if (-not (Test-Path $helpPath)) {
        Write-Host (Get-I18n -Key 'page.help.toolHelpMissing' -Vars @{ toolId = $Tool.id }) -ForegroundColor Yellow
        return
    }

    $rawLines = @(Get-Content -Path $helpPath -Encoding UTF8)
    $lines = foreach ($raw in $rawLines) {
        New-BrandedHelpLine -Text $raw
    }

    $title = if ($Tool.displayName) { $Tool.displayName } else { $Tool.id }
    $null = Show-BrandedContentPage -SectionTitle $title -Lines $lines
}
