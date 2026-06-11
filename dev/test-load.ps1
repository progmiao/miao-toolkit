$ErrorActionPreference = 'Stop'
$lib = 'f:\code\miao\miao-toolkit\package\core\lib'
. (Join-Path $lib 'bootstrap\Load-Core.ps1') -LibDirectory $lib
Initialize-Paths -BinDirectory 'f:\code\miao\miao-toolkit\package\bin'

Import-MiaoModule -Name Help
Import-MiaoModule -Name Sys
Import-MiaoModule -Name Lang

$names = @(
    'Show-ToolkitHelp'
    'Start-SysSession'
    'Show-LanguagePicker'
    'Show-ToolkitHelpPage'
    'Initialize-ToolkitShell'
    'Invoke-HelpPage'
    'Invoke-SysPage'
)

foreach ($n in $names) {
    if (-not (Get-Command $n -ErrorAction SilentlyContinue)) {
        Write-Host "MISSING: $n"
        exit 1
    }
    Write-Host "OK: $n"
}

Write-Host 'ALL OK'
