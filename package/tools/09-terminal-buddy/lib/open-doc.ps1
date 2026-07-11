# terminal-buddy — 在浏览器中打开文档链接

param(
    [hashtable]$ToolkitShell = $null,
    $Action = $null,
    [int]$PageSize = 0,
    [int]$ViewHeight = 0
)

$ErrorActionPreference = 'Stop'
$toolRoot = Split-Path $PSScriptRoot -Parent

. (Join-Path $PSScriptRoot 'terminal-buddy-core.ps1')

$url = ''
if ($Action -and $Action.PSObject.Properties['url']) {
    $url = [string]$Action.url
}

if ([string]::IsNullOrWhiteSpace($url)) {
    Write-Host '缺少文档 URL 配置。' -ForegroundColor Red
    return 1
}

try {
    Start-Process -FilePath $url
    return 0
}
catch {
    $message = Get-TerminalBuddyI18n -ToolRoot $toolRoot -Key 'terminal-buddy.app.openDocFailed' `
        -Vars @{ detail = [string]$_.Exception.Message }
    Write-Host $message -ForegroundColor Red
    return 1
}
