# terminal-buddy — 功能页标题

if (-not (Get-Command Format-ToolActionSectionTitle -ErrorAction SilentlyContinue)) {
    $terminalBuddyActionTitleCoreLib = Join-Path $PSScriptRoot '..\..\..\core\lib'
    . (Join-Path $terminalBuddyActionTitleCoreLib 'ui\shell\ToolActionSectionTitle.ps1')
}

function Resolve-TerminalBuddyToolAction {
    param(
        [string]$ToolRoot,
        $Action = $null,
        [string]$ScriptLeaf = ''
    )

    if ($Action) { return $Action }

    $configPath = Join-Path $ToolRoot 'index.json'
    if (-not (Test-Path -LiteralPath $configPath)) { return $null }

    $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $actions = @($config.actions)
    if ([string]::IsNullOrWhiteSpace($ScriptLeaf)) { return $null }

    return @($actions | Where-Object {
        $scriptPath = [string]$_.script
        $scriptPath -and ($scriptPath -replace '\\', '/') -like "*$ScriptLeaf"
    } | Select-Object -First 1)
}

function Get-TerminalBuddyActionSectionTitle {
    param(
        [string]$ToolRoot,
        $Action = $null,
        [string]$ScriptLeaf = ''
    )

    $resolved = Resolve-TerminalBuddyToolAction -ToolRoot $ToolRoot -Action $Action -ScriptLeaf $ScriptLeaf
    if (-not $resolved) {
        return (Get-ToolkitToolDisplayName -ToolRoot $ToolRoot)
    }

    return (Format-ToolActionSectionTitle -ToolRoot $ToolRoot -ActionNameKey ([string]$resolved.name))
}
