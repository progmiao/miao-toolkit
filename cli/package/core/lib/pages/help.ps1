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

    return New-BrandedBodyLine -Text $Text -Kind $Kind -Color $Color
}

function Get-ToolkitHelpLines {
    param([array]$Tools)

    $lines = @(
        (New-BrandedHelpLine -Text (Format-I18nSectionHeading -LabelKey 'common.command') -Kind 'heading' -Color ([System.ConsoleColor]::White))
        (New-BrandedHelpLine -Text "  miao                 $(Get-I18n -Key 'common.cmd.menu')")
        (New-BrandedHelpLine -Text "  miao list            $(Get-I18n -Key 'common.cmd.list')")
        (New-BrandedHelpLine -Text "  miao version         $(Get-I18n -Key 'common.cmd.version')")
        (New-BrandedHelpLine -Text "  miao help [tool]     $(Get-I18n -Key 'common.cmd.help')")
        (New-BrandedHelpLine -Text "  miao install [tool|all]  $(Get-I18n -Key 'common.cmd.install')")
        (New-BrandedHelpLine -Text "  miao update [tool|all]   $(Get-I18n -Key 'common.cmd.update')")
        (New-BrandedHelpLine -Text "  miao uninstall [tool|all] $(Get-I18n -Key 'common.cmd.uninstall')")
        (New-BrandedHelpLine -Text "  miao sys             $(Get-I18n -Key 'common.cmd.sys')")
        (New-BrandedHelpLine -Text "  miao sys lang        $(Get-I18n -Key 'common.cmd.sysLang')")
        (New-BrandedHelpLine -Text "  miao sys init        $(Get-I18n -Key 'common.cmd.sysInit')")
        (New-BrandedHelpLine -Text "  miao sys update      $(Get-I18n -Key 'common.cmd.sysUpdate')")
        (New-BrandedHelpLine -Text "  miao sys uninstall   $(Get-I18n -Key 'common.cmd.sysUninstall')")
        (New-BrandedHelpLine -Text "  miao <tool> [args]   $(Get-I18n -Key 'common.cmd.tool')")
        (New-BrandedHelpLine -Text '' )
        (New-BrandedHelpLine -Text (Format-I18nSectionHeading -LabelKey 'common.tool') -Kind 'heading' -Color ([System.ConsoleColor]::White))
    )

    foreach ($t in $Tools) {
        $lines += New-BrandedHelpLine -Text "  miao $($t.command)    $($t.name)"
        if ($t.description) {
            $lines += New-BrandedHelpLine -Text "               $($t.description)" -Color ([System.ConsoleColor]::DarkGray)
        }
    }

    return $lines
}

function Show-ToolkitHelpPage {
    param(
        [array]$Tools,
        [hashtable]$Shell = $null
    )

    $lines = Get-ToolkitHelpLines -Tools $Tools

    if ($Shell) {
        return Invoke-ToolkitShellContentView -Shell $Shell `
            -SectionTitle (Get-I18n -Key 'common.help') `
            -Lines $lines `
            -ToolbarConfig (New-ShellSystemToolbarConfig -HideSystem)
    }

    $letterKeys = @{}
    if (-not $Shell) {
        $letterKeys = @{ s = (New-SysMenuEntry) }
    }

    $null = Show-BrandedContentPage -SectionTitle (Get-I18n -Key 'common.help') `
        -Lines $lines -LetterKeys $letterKeys

    return 0
}

function Show-ToolkitHelp {
    param([array]$Tools)

    $lines = Get-ToolkitHelpLines -Tools $Tools
    foreach ($line in $lines) {
        $color = if ($line.Color) { $line.Color } else { [System.ConsoleColor]::Gray }
        Write-Host $line.Text -ForegroundColor $color
    }
}

function Invoke-HelpPage {
    param(
        [hashtable]$Shell,
        [array]$Tools
    )

    return Show-ToolkitHelpPage -Tools $Tools -Shell $Shell
}

function Start-HelpSession {
    param([array]$Tools)

    return (Start-ToolkitShellSession -Tools $Tools -InitialView Help)
}
