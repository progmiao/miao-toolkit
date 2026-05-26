$ErrorActionPreference = 'Stop'
$lib = 'f:\note\miao-toolkit\package\core\lib'
. (Join-Path $lib 'bootstrap\Load-Core.ps1') -LibDirectory $lib
Initialize-Paths -BinDirectory 'f:\note\miao-toolkit\package\bin'

$names = @(
    'Show-ToolkitHelp'
    'Start-SettingsSession'
    'Show-LanguagePicker'
    'Wait-SettingsContinue'
    'Show-ToolkitHelpPage'
    'Initialize-ToolkitShell'
    'Invoke-HelpPage'
    'Invoke-SettingsPage'
)

foreach ($n in $names) {
    if (-not (Get-Command $n -ErrorAction SilentlyContinue)) {
        Write-Host "MISSING: $n"
        exit 1
    }
    Write-Host "OK: $n"
}

Write-Host 'ALL OK'
