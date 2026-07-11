# claude-code — 功能页标题（工具名 - 功能名 [- 子阶段]）

if (-not (Get-Command Format-ToolActionSectionTitle -ErrorAction SilentlyContinue)) {
    $claudeCodeActionTitleCoreLib = Join-Path $PSScriptRoot '..\..\..\core\lib'
    . (Join-Path $claudeCodeActionTitleCoreLib 'ui\shell\ToolActionSectionTitle.ps1')
}

function Import-ClaudeCodeActionTitleCore {
    param([string]$CoreLib)

    Import-ToolActionSectionTitleCore -CoreLib $CoreLib
}

function Resolve-ClaudeCodeToolAction {
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

function Get-ClaudeCodeActionSectionTitle {
    param(
        [string]$ToolRoot,
        $Action = $null,
        [string]$ScriptLeaf = '',
        [string]$SubPhaseKey = ''
    )

    $resolved = Resolve-ClaudeCodeToolAction -ToolRoot $ToolRoot -Action $Action -ScriptLeaf $ScriptLeaf
    if (-not $resolved) {
        return (Get-ToolkitToolDisplayName -ToolRoot $ToolRoot)
    }

    return (Format-ToolActionSectionTitle -ToolRoot $ToolRoot -ActionNameKey ([string]$resolved.name) `
        -SubPhaseKey $SubPhaseKey)
}

function Extend-ClaudeCodeActionSectionTitle {
    param(
        [string]$BaseTitle,
        [string]$ToolRoot,
        [string]$SubPhaseKey
    )

    return Extend-ToolActionSectionTitle -BaseTitle $BaseTitle -ToolRoot $ToolRoot `
        -SubPhaseKey $SubPhaseKey
}

function Get-ClaudeCodePluginSectionTitle {
    param([string]$ToolRoot)

    return (Format-ToolActionSectionTitle -ToolRoot $ToolRoot `
        -ActionNameKey 'claude-code.action.installPlugin.name')
}

function Get-ClaudeCodePluginBatchSectionTitle {
    param(
        [string]$ToolRoot,
        [string]$SubPhaseKey
    )

    $parentTitle = Get-ClaudeCodePluginSectionTitle -ToolRoot $ToolRoot
    return Extend-ClaudeCodeActionSectionTitle -BaseTitle $parentTitle -ToolRoot $ToolRoot `
        -SubPhaseKey $SubPhaseKey
}
