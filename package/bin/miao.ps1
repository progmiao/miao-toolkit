# Miao CLI 主入口（开发预览 / 正式安装均从此启动）

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

$Preview = Test-MiaoDevMode
$MiaoHome = Get-Home
$Tools = @(Discover-Tools)

function Show-DevBanner {
    if (-not $Preview) { return }
    Write-Host "[开发] MiaoHome=$MiaoHome" -ForegroundColor DarkGray
}

if ($MiaoArgs.Count -gt 0) {
    Show-DevBanner
}

if ($MiaoArgs.Count -eq 0) {
    exit (Start-ToolkitSession -Tools $Tools -Preview:$Preview)
}

$head = $MiaoArgs[0]
$rest = @()
if ($MiaoArgs.Count -gt 1) { $rest = $MiaoArgs[1..($MiaoArgs.Count - 1)] }

switch -Regex ($head) {
    '^(-helper|helper)$' {
        Show-ToolkitHelp -Tools $Tools
        exit 0
    }
    '^list$' {
        foreach ($t in $Tools) {
            Write-Host "$($t.id)  $($t.displayName)  $($t.summary)"
        }
        exit 0
    }
    '^version$' {
        Write-ToolkitVersionLine
        exit 0
    }
    '^lang$' {
        exit (Invoke-LangCommand -Rest $rest -Tools $Tools)
    }
    '^settings$' {
        exit (Start-SettingsSession -Tools $Tools -Preview:$Preview)
    }
    '^help$' {
        if ($rest.Count -eq 0) {
            exit (Show-ToolkitHelp -Tools $Tools)
        }
        else {
            $tool = Get-Tool $rest[0]
            if (-not $tool) {
                Write-Host (Get-I18n -Key 'error.unknownTool' -Vars @{ toolId = $rest[0] }) -ForegroundColor Red
                exit 1
            }
            Show-ToolHelp $tool
        }
        exit 0
    }
    '^install$' {
        exit (Invoke-ToolkitInstallDeps -Tools $Tools -ToolIds $rest -Preview:$Preview)
    }
    '^uninstall$' {
        exit (Invoke-ToolkitUninstallDeps -Tools $Tools -ToolIds $rest -Preview:$Preview)
    }
    '^update$' {
        exit (Invoke-ToolkitUpdate -Preview:$Preview)
    }
    default {
        $tool = Get-Tool $head
        if (-not $tool) {
            Write-Host (Get-I18n -Key 'error.unknownCommand' -Vars @{ command = $head }) -ForegroundColor Red
            Write-Host (Get-I18n -Key 'page.help.unknownCommand') -ForegroundColor DarkGray
            exit 1
        }
        exit (Invoke-Tool $tool -ToolArgs $rest -Direct -Preview:$Preview)
    }
}
