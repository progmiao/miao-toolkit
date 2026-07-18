# Miao CLI 主入口

param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$MiaoArgs
)

$ErrorActionPreference = 'Stop'

if ($null -eq $MiaoArgs) { $MiaoArgs = @() }
$MiaoArgs = @($MiaoArgs | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

$BinDir = $PSScriptRoot
$LibDir = Join-Path (Split-Path $BinDir -Parent) 'core/lib'

. (Join-Path $LibDir 'bootstrap\Load-Core.ps1') -LibDirectory $LibDir
Initialize-Paths -BinDirectory $BinDir

$null = Sync-ToolkitSessionInitState -Refresh
$Tools = @(Get-ToolkitTools)

if ($MiaoArgs.Count -eq 0) {
    exit (Start-ToolkitSession -Tools $Tools)
}

$head = $MiaoArgs[0]
$rest = @()
if ($MiaoArgs.Count -gt 1) { $rest = $MiaoArgs[1..($MiaoArgs.Count - 1)] }

switch -Regex ($head) {
    '^(-helper|helper)$' {
        Import-MiaoModule -Name Help
        Show-ToolkitHelp -Tools $Tools
        exit 0
    }
    '^list$' {
        foreach ($t in $Tools) {
            Write-Host "$($t.command)  $($t.name)  $($t.description)"
        }
        exit 0
    }
    '^version$' {
        Write-ToolkitVersionLine
        exit 0
    }
    '^help$' {
        Import-MiaoModule -Name Help
        if ($rest.Count -eq 0) {
            exit (Show-ToolkitHelp -Tools $Tools)
        }
        else {
            $tool = Get-Tool $rest[0] -Tools $Tools
            if (-not $tool) {
                Write-Host (Get-I18n -Key 'message.unknownTool' -Vars @{ toolId = $rest[0] }) -ForegroundColor Red
                exit 1
            }
            Show-ToolHelp $tool
        }
        exit 0
    }
    '^install$' {
        Import-MiaoModule -Name Install
        exit (Invoke-ToolkitInstallDeps -Tools $Tools -Rest $rest)
    }
    '^uninstall$' {
        Import-MiaoModule -Name Install
        exit (Invoke-ToolkitUninstallDeps -Tools $Tools -Rest $rest)
    }
    '^update$' {
        Import-MiaoModule -Name Install
        exit (Invoke-ToolkitUpdateDeps -Tools $Tools -Rest $rest)
    }
    '^sys$' {
        if ($rest.Count -eq 0) {
            Import-MiaoModule -Name Sys
            exit (Start-SysSession -Tools $Tools)
        }

        $sub = $rest[0]
        $subRest = @()
        if ($rest.Count -gt 1) { $subRest = $rest[1..($rest.Count - 1)] }

        switch -Regex ($sub) {
            '^lang$' {
                Import-MiaoModule -Name Lang
                exit (Invoke-LangCommand -Rest $subRest -Tools $Tools)
            }
            '^(init|cache)$' {
                Import-MiaoModule -Name Init
                if ($subRest -contains '--quiet') {
                    exit (Invoke-ToolkitInitQuiet)
                }
                exit (Start-ToolkitInitSession -Tools $Tools -FromSys)
            }
            '^update$' {
                Import-MiaoModule -Name Update
                exit (Invoke-ToolkitSysUpdate -Tools $Tools)
            }
            '^uninstall$' {
                Import-MiaoModule -Name Sys
                exit (Start-ToolkitShellSession -Tools $Tools -InitialView SysUninstall)
            }
            default {
                Write-Host (Get-I18n -Key 'message.unknownSysCommand' -Vars @{ command = $sub }) -ForegroundColor Red
                exit 1
            }
        }
    }
    default {
        $tool = Get-Tool $head -Tools $Tools
        if (-not $tool) {
            Write-Host (Get-I18n -Key 'message.unknownCommand' -Vars @{ command = $head }) -ForegroundColor Red
            Write-Host (Get-I18n -Key 'page.help.unknownCommand') -ForegroundColor DarkGray
            exit 1
        }
        Import-MiaoModule -Name Tool
        if ($rest.Count -eq 0 -and $tool.interactive -ne $false) {
            exit (Start-ToolkitShellSession -Tools $Tools -InitialView Tool `
                -CurrentTool $tool -CurrentToolId $head)
        }
        exit (Invoke-Tool $tool -ToolArgs $rest -Direct)
    }
}
